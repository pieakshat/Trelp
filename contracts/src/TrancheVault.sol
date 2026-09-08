// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {IAquaRegistry} from "./interfaces/IAquaRegistry.sol";
import {IBufferStrategy} from "./interfaces/IBufferStrategy.sol";
import {IPositionVenue} from "./interfaces/IPositionVenue.sol";
import {IQuoteOracle} from "./interfaces/IQuoteOracle.sol";
import {ISpotSwapper} from "./interfaces/ISpotSwapper.sol";
import {RiskPolicy} from "./libraries/RiskPolicy.sol";
import {SolvencyLib} from "./libraries/SolvencyLib.sol";
import {TrancheToken} from "./TrancheToken.sol";

/// @title TrancheVault
/// @notice A single-epoch tranched LP position: senior takes a capped, fee-dependent claim paid
///         first; junior takes first loss and the entire residual.
///
/// @dev One instance runs one epoch and terminates in `Settled`; rolling is a new deployment,
///      which removes cross-epoch accounting state entirely.
///
///      Phases: Subscription -> Active -> Unwinding -> Settled. There is no entry or exit during
///      Active — the senior coupon is only quotable against a known `j`, and redemption at NAV
///      mid-drawdown would let junior exit before absorbing the loss it exists to absorb.
///      `Unwinding` is separate from `Settled` so the cost of the forced conversion is recorded in
///      `unwindCost` rather than hidden.
contract TrancheVault {
    using SafeTransferLib for ERC20;


    error WrongPhase();
    error NotCurator();
    error VenuesAlreadySet();
    error VenuesNotSet();
    error ZeroAmount();
    error SubscriptionClosed();
    error SubscriptionOpen();
    error EpochNotOver();
    error DegenerateEpoch();
    error JuniorShareOutOfBounds(uint256 juniorShareWad);
    error CouponAboveMax();
    error RiskyInventoryOutstanding(uint256 balance);
    error CoverageAboveThreshold(int256 coverageWad, int256 thresholdWad);
    error NothingShipped();
    error GraceNotElapsed();
    error NothingToLiquidate();
    error LiquidationBelowFloor(uint256 received, uint256 floor);
    error NoValidSplit(uint256 juniorShareWad);
    error RebalanceTooSoon(uint64 nextAllowedAt);
    error RebalanceBlockedInDistress(int256 coverageWad, int256 floorWad);


    event Deposited(address indexed who, bool indexed isSenior, uint256 assets);
    event Activated(
        uint256 seniorPrincipal,
        uint256 juniorPrincipal,
        uint256 juniorShareWad,
        uint256 feeSplitWad,
        uint256 shipped
    );
    event BufferCalled(address indexed caller, int256 coverageWad, uint256 shippedQuote);
    event Rebalanced(address indexed curator, uint256 cost, uint256 cumulativeCost);
    event Liquidated(address indexed caller, uint256 riskySold, uint256 quoteReceived);
    event Donated(address indexed who, uint256 assets);
    event SettlementBegun(
        uint256 navBeforeUnwind,
        uint256 quoteReturned,
        uint256 unwindCost,
        uint64 unwindDeadline
    );
    event Settled(uint256 nav, uint256 seniorClaim, uint256 seniorPot, uint256 juniorPot);
    event Cancelled(uint256 seniorPrincipal, uint256 juniorPrincipal);
    event Redeemed(address indexed who, bool indexed isSenior, uint256 shares, uint256 assets);


    enum Phase {
        Subscription,
        Active,
        Unwinding,
        Settled
    }

    /// @param couponWad            c, senior coupon over the whole epoch
    /// @param lambdaWad            fraction of the safe split envelope senior is given. The only
    ///                             curator input to pricing; `s` is derived from realised `j`.
    /// @param maxCouponWad         governance bound on `c`. See the note in SolvencyLib on why the
    ///                             plan's `max_rate` cannot be a third term in the payout.
    /// @param minJuniorShareWad    reject epochs with too thin a buffer to be worth structuring
    /// @param maxJuniorShareWad    reject epochs that are really just a junior-only LP vault
    /// @param bufferShipShareWad   fraction of J shipped to the buffer rather than the pool
    /// @param bufferCallCoverageWad  b threshold below which `callBuffer()` is permissionless
    /// @param minRebalanceCoverageWad  b floor below which the range freezes
    /// @param liquidationSlippageWad  most a settlement sale may give up against the oracle mark
    /// @param risk                 quoting policy, shared by every venue
    /// @param subscriptionEnd      earliest timestamp at which the epoch may be activated
    /// @param epochDuration        T, seconds
    /// @param activationGrace      how long after `subscriptionEnd` before depositors may cancel
    /// @param unwindWindow         how long the vault quotes its way out before settling
    /// @param rebalanceCooldown    minimum spacing between range moves
    struct Config {
        uint256 couponWad;
        uint256 lambdaWad;
        uint256 maxCouponWad;
        uint256 minJuniorShareWad;
        uint256 maxJuniorShareWad;
        uint256 bufferShipShareWad;
        int256 bufferCallCoverageWad;
        int256 minRebalanceCoverageWad;
        uint256 liquidationSlippageWad;
        RiskPolicy.Params risk;
        uint64 subscriptionEnd;
        uint64 epochDuration;
        uint64 activationGrace;
        uint64 unwindWindow;
        uint64 rebalanceCooldown;
    }


    uint256 internal constant WAD = 1e18;

    ERC20 public immutable quote;
    ERC20 public immutable risky;
    IAquaRegistry public immutable aqua;
    IQuoteOracle public immutable oracle;
    TrancheToken public immutable senior;
    TrancheToken public immutable junior;
    address public immutable curator;

    Config public config;
    IPositionVenue public positionVenue;
    IBufferStrategy public bufferStrategy;
    ISpotSwapper public swapper;

    /// @dev Aqua records the maker as `msg.sender`, so the vault ships for itself. The capital
    ///      never leaves this contract, which is why `nav()` already counts it.
    bytes32 public bufferStrategyHash;
    address public bufferApp;
    address[] internal bufferTokens;
    uint256 public shippedQuote;
    bool public bufferShipped;

    Phase public phase;
    SolvencyLib.Terms public terms;

    /// @notice Quote value lost converting the position back to the quote asset at settlement.
    /// @dev Every epoch ends in a scheduled, publicly known conversion. Recording it keeps that
    ///      cost inside the reported returns.
    uint256 public unwindCost;
    /// @notice Cumulative quote value lost to curator range moves.
    /// @dev Range authority is discretion that lands on senior, so its cost is measured rather
    ///      than inferred from the final number.
    uint256 public rebalanceCost;
    uint32 public rebalanceCount;
    uint64 public lastRebalanceAt;

    /// @notice When the unwind window closes. Set at `beginSettlement`.
    uint64 public unwindDeadline;

    uint256 public navAtSettlement;
    uint256 public seniorClaimAtSettlement;
    uint256 public seniorPot;
    uint256 public juniorPot;
    uint256 public seniorSupplyAtSettlement;
    uint256 public juniorSupplyAtSettlement;

    constructor(
        ERC20 quote_,
        ERC20 risky_,
        IQuoteOracle oracle_,
        IAquaRegistry aqua_,
        address curator_,
        Config memory config_
    ) {
        if (config_.couponWad > config_.maxCouponWad) revert CouponAboveMax();

        quote = quote_;
        risky = risky_;
        oracle = oracle_;
        aqua = aqua_;
        curator = curator_;
        config = config_;

        uint8 d = quote_.decimals();
        senior = new TrancheToken("Trelp Senior Claim", "trSNR", d, address(this));
        junior = new TrancheToken("Trelp Junior Claim", "trJNR", d, address(this));
    }

    /// @dev Wired after construction because venues need the vault address. One-time and
    ///      subscription-only, so depositors see the venues before activation.
    function setVenues(IPositionVenue positionVenue_, IBufferStrategy bufferStrategy_, ISpotSwapper swapper_)
        external
    {
        if (msg.sender != curator) revert NotCurator();
        if (phase != Phase.Subscription) revert WrongPhase();
        if (address(positionVenue) != address(0)) revert VenuesAlreadySet();
        positionVenue = positionVenue_;
        bufferStrategy = bufferStrategy_;
        swapper = swapper_;
    }

    function depositSenior(uint256 assets) external {
        _deposit(senior, assets, true);
    }

    function depositJunior(uint256 assets) external {
        _deposit(junior, assets, false);
    }

    /// @dev Capital is idle during subscription, so claims mint 1:1 and no share price is needed.
    ///      That is what makes `j` unambiguous at activation.
    function _deposit(TrancheToken token, uint256 assets, bool isSenior) internal {
        if (phase != Phase.Subscription) revert WrongPhase();
        if (block.timestamp >= config.subscriptionEnd) revert SubscriptionClosed();
        if (assets == 0) revert ZeroAmount();

        quote.safeTransferFrom(msg.sender, address(this), assets);
        token.mint(msg.sender, assets);
        emit Deposited(msg.sender, isSenior, assets);
    }

    /// @notice Close subscription, fix the senior terms, and deploy capital.
    function activate() external {
        if (phase != Phase.Subscription) revert WrongPhase();
        if (block.timestamp < config.subscriptionEnd) revert SubscriptionOpen();
        if (address(positionVenue) == address(0)) revert VenuesNotSet();

        uint256 s0 = senior.totalSupply();
        uint256 j0 = junior.totalSupply();
        // A one-sided epoch is not a tranche structure; refuse rather than mis-quote it.
        if (s0 == 0 || j0 == 0) revert DegenerateEpoch();

        uint256 j = (j0 * WAD) / (s0 + j0);
        if (j < config.minJuniorShareWad || j > config.maxJuniorShareWad) revert JuniorShareOutOfBounds(j);

        // Senior's terms are priced off realised demand, not configured ahead of it. At j >= 50%
        // no split leaves junior better off than simply LPing, so no valid terms exist and the
        // epoch cannot activate.
        uint256 split = SolvencyLib.splitFromJuniorShare(j, config.lambdaWad);
        if (split == 0) revert NoValidSplit(j);

        terms = SolvencyLib.Terms({
            seniorPrincipal: s0,
            juniorPrincipal: j0,
            couponWad: config.couponWad,
            feeSplitWad: split,
            start: uint64(block.timestamp),
            duration: config.epochDuration
        });

        // Ship first: Aqua takes no custody, so this only writes an allowance. The tokens stay here
        // and back the buffer's quotes from this contract's own balance.
        uint256 shipped = (j0 * config.bufferShipShareWad) / WAD;
        if (shipped != 0) _ship(shipped);

        uint256 toDeploy = quote.balanceOf(address(this)) - shipped;
        quote.safeTransfer(address(positionVenue), toDeploy);
        positionVenue.deploy(toDeploy);

        phase = Phase.Active;
        emit Activated(s0, j0, j, split, shipped);
    }

    /// @notice Refund path if the epoch is never activated. Deposits were 1:1 and capital never
    ///         moved, so the settled pots are exactly the principals.
    function cancel() external {
        if (phase != Phase.Subscription) revert WrongPhase();
        if (block.timestamp < config.subscriptionEnd + config.activationGrace) revert GraceNotElapsed();

        seniorSupplyAtSettlement = senior.totalSupply();
        juniorSupplyAtSettlement = junior.totalSupply();
        seniorPot = seniorSupplyAtSettlement;
        juniorPot = juniorSupplyAtSettlement;
        phase = Phase.Settled;
        emit Cancelled(seniorPot, juniorPot);
    }

    /// @notice NAV(t), in quote base units.
    /// @dev Shipped buffer capital is absent as a separate term on purpose: Aqua holds nothing, so
    ///      it is already inside this contract's balances. Adding `shippedQuote` would double-count.
    function nav() public view returns (uint256 total) {
        total = quote.balanceOf(address(this));

        // Filling against the buffer leaves this vault holding the risky asset. That inventory is
        // the buffer being adversely selected, and it is a NAV term like any other.
        uint256 riskyBalance = risky.balanceOf(address(this));
        if (riskyBalance != 0) total += oracle.valueInQuote(address(risky), riskyBalance);

        if (address(positionVenue) != address(0)) total += positionVenue.valueInQuote();
    }

    /// @notice S_claim(t), the accruing senior claim used by the live coverage signal.
    function seniorClaim() public view returns (uint256) {
        return SolvencyLib.accruedSeniorClaim(terms, block.timestamp);
    }

    /// @notice b(t) = (NAV - S_claim) / S_claim. Signed: coverage can be exhausted.
    function coverageWad() public view returns (int256) {
        return SolvencyLib.coverageWad(nav(), seniorClaim());
    }

    /// @notice Revoke the buffer's Aqua strategy, converting junior's capital from a committed
    ///         quoting position back into idle loss absorption.
    /// @dev Permissionless once coverage breaches the threshold; the curator may call any time.
    ///
    ///      TODO: read a TWAP and require the breach to persist several blocks, so a single-block
    ///      price move cannot force the call.
    function callBuffer() external {
        if (phase != Phase.Active) revert WrongPhase();
        if (!bufferShipped) revert NothingShipped();

        int256 b = coverageWad();
        if (msg.sender != curator && b >= config.bufferCallCoverageWad) {
            revert CoverageAboveThreshold(b, config.bufferCallCoverageWad);
        }

        uint256 shipped = shippedQuote;
        _dock();
        emit BufferCalled(msg.sender, b, shipped);
    }

    /// @dev No tokens move: Aqua records an allowance against this contract and pulls at fill
    ///      time.
    function _ship(uint256 quoteAmount) internal {
        (address app, bytes memory strategy, address[] memory tokens, uint256[] memory amounts) =
            bufferStrategy.shipParams(quoteAmount);

        // Approve exactly what is shipped. The virtual balance caps each strategy, but a bounded
        // allowance keeps the blast radius of any future app the vault ships to bounded too.
        quote.safeApprove(address(aqua), quoteAmount);

        bufferApp = app;
        delete bufferTokens;
        for (uint256 i; i < tokens.length; ++i) bufferTokens.push(tokens[i]);

        bufferStrategyHash = aqua.ship(app, strategy, tokens, amounts);
        shippedQuote = quoteAmount;
        bufferShipped = true;
    }

    /// @dev A permission change, not a withdrawal, so it cannot fail for liquidity reasons. Aqua
    ///      closes every token at once, so a partial call would need a second shipped strategy.
    function _dock() internal {
        aqua.dock(bufferApp, bufferStrategyHash, bufferTokens);
        bufferShipped = false;
        shippedQuote = 0;
        quote.safeApprove(address(aqua), 0);
    }

    /// @notice Add quote to the vault without minting any claim.
    /// @dev A cure right with no mid-epoch share price to settle: it lifts coverage and can stop
    ///      the breaker firing. The donor recovers it only through the junior residual, so it is
    ///      rational only for a concentrated junior holder.
    function donate(uint256 assets) external {
        if (phase != Phase.Active) revert WrongPhase();
        if (assets == 0) revert ZeroAmount();
        quote.safeTransferFrom(msg.sender, address(this), assets);
        emit Donated(msg.sender, assets);
    }

    /// @notice Stop quoting, dock the buffer, and unwind the LP position to the quote asset.
    function beginSettlement() external {
        if (phase != Phase.Active) revert WrongPhase();
        if (block.timestamp < uint256(terms.start) + terms.duration) revert EpochNotOver();

        uint256 navBefore = nav();

        if (bufferShipped) _dock();
        uint256 returned = positionVenue.unwind();

        uint256 navAfter = nav();
        unwindCost = navBefore > navAfter ? navBefore - navAfter : 0;

        unwindDeadline = uint64(block.timestamp) + config.unwindWindow;
        phase = Phase.Unwinding;
        emit SettlementBegun(navBefore, returned, unwindCost, unwindDeadline);
    }

    /// @notice Sell risky inventory back to the quote asset so the epoch can settle.
    /// @dev Unwinding the LP position returns both currencies, and the buffer may have been filled
    ///      into risky during the epoch, but `settle()` reads the quote balance alone. Without a
    ///      way to convert, the vault would sit in `Unwinding` with no reachable exit and no way to
    ///      redeem.
    ///
    ///      Permissionless, because settlement must not depend on the curator staying alive. The
    ///      caller cannot grief the vault: the proceeds are floored against the oracle mark less
    ///      `liquidationSlippageWad`, so a sale into a bad venue reverts rather than settling low.
    ///
    ///      Takes an amount so a large inventory can be worked down across several venues or
    ///      blocks rather than demanding one deep fill.
    function liquidate(uint256 amount) external returns (uint256 received) {
        if (phase != Phase.Unwinding) revert WrongPhase();

        uint256 held = risky.balanceOf(address(this));
        if (amount == 0 || held == 0) revert NothingToLiquidate();
        if (amount > held) amount = held;

        uint256 floor;
        {
            uint256 mark = oracle.valueInQuote(address(risky), amount);
            floor = mark - (mark * config.liquidationSlippageWad) / WAD;
        }

        risky.safeApprove(address(swapper), amount);
        received = swapper.swapExactIn(address(risky), address(quote), amount, floor);
        risky.safeApprove(address(swapper), 0);

        // The swapper is external and enforces its own minimum; re-check what actually arrived.
        if (received < floor) revert LiquidationBelowFloor(received, floor);

        emit Liquidated(msg.sender, amount, received);
    }

    /// @notice Run the waterfall and open redemptions.
    /// @dev Requires the risky leg to be flat. The leg is quoted out over `unwindWindow` rather
    ///      than sold here: a market order inside settlement would be an unpriced, unbounded action
    ///      in the middle of the accounting step, at a time everyone can predict.
    function settle() external {
        if (phase != Phase.Unwinding) revert WrongPhase();
        uint256 riskyBalance = risky.balanceOf(address(this));
        if (riskyBalance != 0) revert RiskyInventoryOutstanding(riskyBalance);

        navAtSettlement = quote.balanceOf(address(this));
        seniorClaimAtSettlement = SolvencyLib.finalSeniorClaim(terms, navAtSettlement);
        (seniorPot, juniorPot) = SolvencyLib.waterfall(navAtSettlement, seniorClaimAtSettlement);

        seniorSupplyAtSettlement = senior.totalSupply();
        juniorSupplyAtSettlement = junior.totalSupply();

        phase = Phase.Settled;
        emit Settled(navAtSettlement, seniorClaimAtSettlement, seniorPot, juniorPot);
    }

    function redeemSenior(uint256 shares) external returns (uint256 assets) {
        return _redeem(senior, shares, seniorPot, seniorSupplyAtSettlement, true);
    }

    function redeemJunior(uint256 shares) external returns (uint256 assets) {
        return _redeem(junior, shares, juniorPot, juniorSupplyAtSettlement, false);
    }

    function _redeem(TrancheToken token, uint256 shares, uint256 pot, uint256 supply, bool isSenior)
        internal
        returns (uint256 assets)
    {
        if (phase != Phase.Settled) revert WrongPhase();
        if (shares == 0) revert ZeroAmount();

        assets = (shares * pot) / supply;
        token.burn(msg.sender, shares);
        if (assets != 0) quote.safeTransfer(msg.sender, assets);
        emit Redeemed(msg.sender, isSenior, shares, assets);
    }

    // ---------------------------------------------------------------- range authority

    /// @notice Move the LP position to a new range.
    /// @dev Unbounded rebalancing is worse for senior than a static range: re-centring downward
    ///      after a fall sells the accumulated asset at the bottom and re-arms from a lower base,
    ///      which compounds through a trend with no single event to point at.
    ///
    ///      So the authority is bounded on both sides. The vault enforces a coverage floor and a
    ///      cooldown and measures the cost; the venue enforces the range covenant, since only it
    ///      knows the range. The floor matters most: re-centring does the most damage exactly when
    ///      a curator is most tempted to reach for it.
    function rebalance(bytes calldata venueData) external {
        if (msg.sender != curator) revert NotCurator();
        if (phase != Phase.Active) revert WrongPhase();

        uint64 nextAllowed = lastRebalanceAt + config.rebalanceCooldown;
        if (lastRebalanceAt != 0 && block.timestamp < nextAllowed) revert RebalanceTooSoon(nextAllowed);

        int256 b = coverageWad();
        if (b < config.minRebalanceCoverageWad) {
            revert RebalanceBlockedInDistress(b, config.minRebalanceCoverageWad);
        }

        uint256 navBefore = nav();
        positionVenue.rebalance(venueData);
        uint256 navAfter = nav();

        uint256 cost = navBefore > navAfter ? navBefore - navAfter : 0;
        rebalanceCost += cost;
        rebalanceCount += 1;
        lastRebalanceAt = uint64(block.timestamp);

        emit Rebalanced(msg.sender, cost, rebalanceCost);
    }

    // ---------------------------------------------------------------- quoting policy

    /// @notice Quote-denominated value of the risky inventory this vault is holding.
    function riskyValue() public view returns (uint256) {
        uint256 bal = risky.balanceOf(address(this));
        return bal == 0 ? 0 : oracle.valueInQuote(address(risky), bal);
    }

    /// @notice The hard ceiling on convertible capital.
    /// @dev A deviation band caps extraction per fill, not per epoch, so it does not bound total
    ///      loss on its own — an underwater junior can loop it. This ceiling is the structural
    ///      control, sized so inventory conversion cannot cost more than junior's buffer absorbs.
    function maxRiskyValue() public view returns (uint256) {
        return (SolvencyLib.totalPrincipal(terms) * config.risk.maxInventoryWad) / WAD;
    }

    /// @notice The current quoting instruction. Read by the v4 hook and by the Aqua buffer's
    ///         Extruction target, so both venues price off one policy.
    function riskQuote() external view returns (RiskPolicy.Quote memory) {
        return RiskPolicy.evaluate(config.risk, coverageWad(), riskyValue(), SolvencyLib.totalPrincipal(terms));
    }

    // ---------------------------------------------------------------- views

    function juniorShareWad() external view returns (uint256) {
        return SolvencyLib.juniorShareWad(terms);
    }

    function initialCoverageWad() external view returns (uint256) {
        return SolvencyLib.initialCoverageWad(terms);
    }
}
