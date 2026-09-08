// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {IBufferVenue} from "./interfaces/IBufferVenue.sol";
import {IPositionVenue} from "./interfaces/IPositionVenue.sol";
import {IQuoteOracle} from "./interfaces/IQuoteOracle.sol";
import {RiskPolicy} from "./libraries/RiskPolicy.sol";
import {SolvencyLib} from "./libraries/SolvencyLib.sol";
import {TrancheToken} from "./TrancheToken.sol";

/// @title TrancheVault
/// @notice A single-epoch tranched LP position: senior takes a capped, fee-dependent claim paid
///         first; junior takes first loss and the entire residual.
///
/// @dev SCOPE. One vault instance runs exactly one epoch and terminates in `Settled`. Rolling is a
///      new deployment. This removes a whole class of cross-epoch accounting bugs and costs nothing
///      the demo needs. Auto-roll (plan §4) is a router on top, not vault state.
///
///      PHASES. Subscription -> Active -> Unwinding -> Settled. There is deliberately no
///      entry or exit during Active: the senior coupon is only quotable against a known `j`, and
///      redemption at NAV mid-drawdown would let junior exit before absorbing the loss it exists to
///      absorb. `Unwinding` is split out from `Settled` because the forced unwind is a real,
///      scheduled market order whose cost is recorded in `unwindCost` rather than hidden.
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
    /// @param bufferShipShareWad   fraction of J shipped to the buffer venue (the §8 frontier knob)
    /// @param bufferCallCoverageWad  b threshold below which `callBuffer()` is permissionless
    /// @param minRebalanceCoverageWad  b floor below which the range freezes
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
    IQuoteOracle public immutable oracle;
    TrancheToken public immutable senior;
    TrancheToken public immutable junior;
    address public immutable curator;

    Config public config;
    IPositionVenue public positionVenue;
    IBufferVenue public bufferVenue;

    Phase public phase;
    SolvencyLib.Terms public terms;

    /// @notice Quote value lost converting the position back to the quote asset at settlement.
    /// @dev Every epoch ends in a scheduled, publicly known unwind. Recording it keeps that cost in
    ///      the returns rather than outside them.
    uint256 public unwindCost;
    /// @notice Cumulative quote value lost to curator range moves.
    /// @dev Range authority is discretion that lands on senior, so it is measured. Junior can read
    ///      what curator activity cost them instead of inferring it from the final number.
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

    constructor(ERC20 quote_, ERC20 risky_, IQuoteOracle oracle_, address curator_, Config memory config_) {
        if (config_.couponWad > config_.maxCouponWad) revert CouponAboveMax();

        quote = quote_;
        risky = risky_;
        oracle = oracle_;
        curator = curator_;
        config = config_;

        uint8 d = quote_.decimals();
        senior = new TrancheToken("Trelp Senior Claim", "trSNR", d, address(this));
        junior = new TrancheToken("Trelp Junior Claim", "trJNR", d, address(this));
    }

    /// @dev Venues are wired after construction because they need the vault address. One-time and
    ///      subscription-only, so depositors can see the venues before the epoch activates.
    function setVenues(IPositionVenue positionVenue_, IBufferVenue bufferVenue_) external {
        if (msg.sender != curator) revert NotCurator();
        if (phase != Phase.Subscription) revert WrongPhase();
        if (address(positionVenue) != address(0)) revert VenuesAlreadySet();
        positionVenue = positionVenue_;
        bufferVenue = bufferVenue_;
    }

    function depositSenior(uint256 assets) external {
        _deposit(senior, assets, true);
    }

    function depositJunior(uint256 assets) external {
        _deposit(junior, assets, false);
    }

    /// @dev Capital is idle during subscription, so claims mint 1:1 with deposits and no share
    ///      price is needed. This is what makes `j` unambiguous at activation.
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
        if (shipped != 0) bufferVenue.ship(shipped);

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
    /// @dev Buffer capital shipped to Aqua is deliberately absent as a separate term. Aqua holds
    ///      nothing, so that capital is already inside this contract's own token balances. Adding
    ///      `bufferVenue.shippedQuote()` here would double-count it.
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
    ///      This is stage 1.5 of the breaker.
    ///
    ///      TODO(breaker): the real trigger must read a TWAP and require the breach to persist for
    ///      N blocks, so a single-block manipulation cannot force the call (plan §11).
    function callBuffer() external {
        if (phase != Phase.Active) revert WrongPhase();
        if (!bufferVenue.isShipped()) revert NothingShipped();

        int256 b = coverageWad();
        if (msg.sender != curator && b >= config.bufferCallCoverageWad) {
            revert CoverageAboveThreshold(b, config.bufferCallCoverageWad);
        }

        uint256 shipped = bufferVenue.shippedQuote();
        bufferVenue.dock();
        emit BufferCalled(msg.sender, b, shipped);
    }

    /// @notice Add quote to the vault without minting any claim.
    /// @dev The minimal, unambiguous form of a junior cure right: it lifts coverage and can stop the
    ///      breaker firing, with no mid-epoch share price to argue about. A donor recovers it only
    ///      through the junior residual, so it is rational only for a concentrated junior holder.
    ///      A share-minting cure is the better product and the open design question.
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

        if (bufferVenue.isShipped()) bufferVenue.dock();
        uint256 returned = positionVenue.unwind();

        uint256 navAfter = nav();
        unwindCost = navBefore > navAfter ? navBefore - navAfter : 0;

        unwindDeadline = uint64(block.timestamp) + config.unwindWindow;
        phase = Phase.Unwinding;
        emit SettlementBegun(navBefore, returned, unwindCost, unwindDeadline);
    }

    /// @notice Run the waterfall and open redemptions.
    /// @dev Requires the risky leg to be flat. The vault quotes its way out over `unwindWindow`
    ///      rather than market-selling: every epoch ends in a scheduled, publicly known conversion,
    ///      and an auction at a widening discount is a better exit than a market order at a time
    ///      everyone can predict. A market sell inside settlement would also be an unpriced,
    ///      unbounded action in the middle of the accounting step.
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
    /// @dev Naive rebalancing is strictly worse for senior than a static range: re-centring
    ///      downward after a fall sells the accumulated asset at the bottom and re-arms the same
    ///      exposure from a lower base, and in a trend that compounds until senior's protection is
    ///      gone with no single event to point at.
    ///
    ///      So this is discretion inside a covenant box, the way a managed securitisation works:
    ///        - the vault enforces policy: a coverage floor and a cooldown, and it measures cost;
    ///        - the venue enforces the range covenant: the position's value at its own lower bound
    ///          must still cover the senior claim with margin.
    ///
    ///      The coverage floor matters most. Exactly when a curator is most tempted to fix things
    ///      is when re-centring does the most damage, so the range freezes in distress.
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
    /// @dev An oracle deviation band caps what an adversary extracts per fill, not per epoch, so a
    ///      band alone does not bound total loss -- an underwater junior can simply loop it. This
    ///      ceiling is the structural control, sized against principal so that inventory conversion
    ///      cannot cost more than junior's buffer absorbs.
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
