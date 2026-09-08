// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IBufferVenue} from "./interfaces/IBufferVenue.sol";
import {IPositionVenue} from "./interfaces/IPositionVenue.sol";
import {IQuoteOracle} from "./interfaces/IQuoteOracle.sol";
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
///      PHASES (plan §4). Subscription -> Active -> Settling -> Settled. There is deliberately no
///      entry or exit during Active: the senior coupon is only quotable against a known `j`, and
///      redemption at NAV mid-drawdown would let junior exit before absorbing the loss it exists to
///      absorb. `Settling` is split out from `Settled` because the forced unwind is a real,
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


    event Deposited(address indexed who, bool indexed isSenior, uint256 assets);
    event Activated(uint256 seniorPrincipal, uint256 juniorPrincipal, uint256 juniorShareWad, uint256 shipped);
    event BufferCalled(address indexed caller, int256 coverageWad, uint256 shippedQuote);
    event Donated(address indexed who, uint256 assets);
    event SettlementBegun(uint256 navBeforeUnwind, uint256 quoteReturned, uint256 unwindCost, uint256 fees);
    event Settled(uint256 nav, uint256 seniorClaim, uint256 seniorPot, uint256 juniorPot);
    event Cancelled(uint256 seniorPrincipal, uint256 juniorPrincipal);
    event Redeemed(address indexed who, bool indexed isSenior, uint256 shares, uint256 assets);


    enum Phase {
        Subscription,
        Active,
        Settling,
        Settled
    }

    /// @param couponWad            c, senior coupon over the whole epoch
    /// @param feeSplitWad          s, senior's share of realised fees (the split clause)
    /// @param maxCouponWad         governance bound on `c`. See the note in SolvencyLib on why the
    ///                             plan's `max_rate` cannot be a third term in the payout.
    /// @param minJuniorShareWad    reject epochs with too thin a buffer to be worth structuring
    /// @param maxJuniorShareWad    reject epochs that are really just a junior-only LP vault
    /// @param bufferShipShareWad   fraction of J shipped to the buffer venue (the §8 frontier knob)
    /// @param bufferCallCoverageWad  b threshold below which `callBuffer()` is permissionless
    /// @param subscriptionEnd      earliest timestamp at which the epoch may be activated
    /// @param epochDuration        T, seconds
    /// @param activationGrace      how long after `subscriptionEnd` before depositors may cancel
    struct Config {
        uint256 couponWad;
        uint256 feeSplitWad;
        uint256 maxCouponWad;
        uint256 minJuniorShareWad;
        uint256 maxJuniorShareWad;
        uint256 bufferShipShareWad;
        int256 bufferCallCoverageWad;
        uint64 subscriptionEnd;
        uint64 epochDuration;
        uint64 activationGrace;
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
    uint256 public feesAtSettlement;
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

        terms = SolvencyLib.Terms({
            seniorPrincipal: s0,
            juniorPrincipal: j0,
            couponWad: config.couponWad,
            feeSplitWad: config.feeSplitWad,
            start: uint64(block.timestamp),
            duration: config.epochDuration
        });

        uint256 j = SolvencyLib.juniorShareWad(terms);
        if (j < config.minJuniorShareWad || j > config.maxJuniorShareWad) revert JuniorShareOutOfBounds(j);

        // Ship first: Aqua takes no custody, so this only writes an allowance. The tokens stay here
        // and back the buffer's quotes from this contract's own balance.
        uint256 shipped = (j0 * config.bufferShipShareWad) / WAD;
        if (shipped != 0) bufferVenue.ship(shipped);

        uint256 toDeploy = quote.balanceOf(address(this)) - shipped;
        quote.safeTransfer(address(positionVenue), toDeploy);
        positionVenue.deploy(toDeploy);

        phase = Phase.Active;
        emit Activated(s0, j0, j, shipped);
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
        feesAtSettlement = positionVenue.feesInQuote();

        if (bufferVenue.isShipped()) bufferVenue.dock();
        uint256 returned = positionVenue.unwind();

        uint256 navAfter = nav();
        unwindCost = navBefore > navAfter ? navBefore - navAfter : 0;

        phase = Phase.Settling;
        emit SettlementBegun(navBefore, returned, unwindCost, feesAtSettlement);
    }

    /// @notice Run the waterfall and open redemptions.
    /// @dev Requires the risky leg to be flat. Converting residual inventory is the keeper's job
    ///      (breaker stage 3) and is deliberately not done here: a market sell inside settlement
    ///      would be an unpriced, unbounded action in the middle of the accounting step.
    function settle() external {
        if (phase != Phase.Settling) revert WrongPhase();
        uint256 riskyBalance = risky.balanceOf(address(this));
        if (riskyBalance != 0) revert RiskyInventoryOutstanding(riskyBalance);

        navAtSettlement = quote.balanceOf(address(this));
        seniorClaimAtSettlement = SolvencyLib.finalSeniorClaim(terms, feesAtSettlement);
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

    function juniorShareWad() external view returns (uint256) {
        return SolvencyLib.juniorShareWad(terms);
    }

    function initialCoverageWad() external view returns (uint256) {
        return SolvencyLib.initialCoverageWad(terms);
    }
}
