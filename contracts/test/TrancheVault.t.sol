// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {TrancheVault} from "../src/TrancheVault.sol";
import {IBufferVenue} from "../src/interfaces/IBufferVenue.sol";
import {IPositionVenue} from "../src/interfaces/IPositionVenue.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {RiskPolicy} from "../src/libraries/RiskPolicy.sol";
import {MockBufferVenue, MockERC20, MockOracle, MockPositionVenue} from "./mocks/Mocks.sol";

contract TrancheVaultTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant V0 = 1_000_000e6;
    uint256 constant S0 = 700_000e6;
    uint256 constant J0 = 300_000e6;
    uint64 constant T = 30 days;

    MockERC20 quote;
    MockERC20 risky;
    MockOracle oracle;
    TrancheVault vault;
    MockPositionVenue position;
    MockBufferVenue buffer;

    address curator = address(0xC0);
    address alice = address(0xA1); // senior
    address bob = address(0xB0); // junior

    uint64 subEnd;

    function setUp() public {
        vm.warp(1_000_000);
        subEnd = uint64(block.timestamp + 1 days);

        quote = new MockERC20("USD Coin", "USDC", 6);
        risky = new MockERC20("Wrapped Ether", "WETH", 18);
        oracle = new MockOracle();
        oracle.setPrice(address(risky), 2000e6);

        _deploy(0); // no buffer shipped by default
    }

    function _deploy(uint256 bufferShipShareWad) internal {
        TrancheVault.Config memory cfg = TrancheVault.Config({
            couponWad: 0.01e18,
            lambdaWad: 0.7e18,
            maxCouponWad: 0.015e18,
            minJuniorShareWad: 0.05e18,
            maxJuniorShareWad: 0.6e18,
            bufferShipShareWad: bufferShipShareWad,
            bufferCallCoverageWad: 0.1e18,
            minRebalanceCoverageWad: 0.2e18,
            risk: RiskPolicy.Params({
                baseSpreadWad: 0.0005e18,
                alphaWad: 2e18,
                kappaWad: 0.5e18,
                targetCoverageWad: 0.4285e18,
                bidCutoffWad: 0.9e18,
                maxInventoryWad: 0.3e18
            }),
            subscriptionEnd: subEnd,
            epochDuration: T,
            activationGrace: 1 days,
            unwindWindow: 1 days,
            rebalanceCooldown: 6 hours
        });

        vault = new TrancheVault(quote, risky, oracle, curator, cfg);
        position = new MockPositionVenue(quote, address(vault));
        buffer = new MockBufferVenue();
        vm.prank(curator);
        vault.setVenues(IPositionVenue(address(position)), IBufferVenue(address(buffer)));
    }

    function _subscribe() internal {
        quote.mint(alice, S0);
        quote.mint(bob, J0);
        vm.startPrank(alice);
        quote.approve(address(vault), S0);
        vault.depositSenior(S0);
        vm.stopPrank();
        vm.startPrank(bob);
        quote.approve(address(vault), J0);
        vault.depositJunior(J0);
        vm.stopPrank();
    }

    function _activate() internal {
        _subscribe();
        vm.warp(subEnd);
        vault.activate();
    }

    // ------------------------------------------------------------ lifecycle

    /// @notice The plan's §2.6 worked example, end to end through the vault.
    function test_fullEpoch_flatPrice_matchesWorkedExample() public {
        _activate();
        assertEq(uint8(vault.phase()), uint8(TrancheVault.Phase.Active));
        assertEq(vault.juniorShareWad(), 0.3e18);
        assertEq(vault.nav(), V0);

        uint256 fees = (V0 * 12) / 100; // f = 12%, flat price
        position.setValue(V0 + fees);

        vm.warp(subEnd + T);
        vault.beginSettlement();
        assertEq(vault.unwindCost(), 0, "no slippage in this path");
        vault.settle();

        assertEq(vault.seniorPot(), S0 + (S0 * 0.01e18) / WAD, "senior earns exactly 1%");

        vm.prank(alice);
        uint256 seniorAssets = vault.redeemSenior(S0);
        vm.prank(bob);
        uint256 juniorAssets = vault.redeemJunior(J0);

        assertApproxEqRel((seniorAssets * WAD) / S0 - WAD, 0.01e18, 1e12, "senior +1%");
        assertApproxEqRel((juniorAssets * WAD) / J0 - WAD, 0.3766666e18, 1e12, "junior +37.7%");
        assertEq(seniorAssets + juniorAssets, V0 + fees, "all value distributed");
    }

    function test_crash_seniorImpairedJuniorWiped() public {
        _activate();
        position.setValue(V0 / 2); // -50% NAV

        vm.warp(subEnd + T);
        vault.beginSettlement();
        vault.settle();

        assertEq(vault.juniorPot(), 0, "junior wiped");
        assertEq(vault.seniorPot(), V0 / 2, "senior takes everything left");

        vm.prank(bob);
        assertEq(vault.redeemJunior(J0), 0);
    }

    /// @notice The forced unwind at every epoch boundary is a real cost, and it is recorded.
    function test_unwindCostIsRecorded() public {
        _activate();
        position.setValue(V0);
        // The venue reports V0 but only returns 99% of it when actually converted.
        uint256 leak = V0 / 100;
        vm.prank(address(position));
        quote.transfer(address(0xdead), leak);

        vm.warp(subEnd + T);
        vault.beginSettlement();
        assertEq(vault.unwindCost(), leak, "slippage surfaced, not hidden");
    }

    // ------------------------------------------------------------ Aqua accounting

    /// @notice Aqua takes no custody, so shipped buffer capital stays in the vault and is counted
    ///         exactly once. This is the accounting trap the §8 design depends on getting right.
    function test_shippedBufferStaysInVaultAndIsNotDoubleCounted() public {
        _deploy(WAD); // ship 100% of junior
        _activate();

        assertEq(buffer.shippedQuote(), J0, "buffer shipped");
        assertEq(quote.balanceOf(address(vault)), J0, "capital never left the vault");
        assertEq(position.valueInQuote(), S0, "only senior capital went into the pool");
        assertEq(vault.nav(), V0, "NAV counts the buffer once, not twice");
    }

    function test_callBuffer_permissionlessOnlyBelowThreshold() public {
        _deploy(WAD);
        _activate();

        // Coverage healthy: an outsider cannot dock the buffer.
        vm.expectRevert();
        vm.prank(alice);
        vault.callBuffer();

        // Drive NAV down until b < 10%.
        position.setValue(S0 - 250_000e6); // nav = 300k + 450k = 750k, claim ~= 700k, b ~= 7.1%
        assertLt(vault.coverageWad(), int256(0.1e18));

        vm.prank(alice);
        vault.callBuffer();
        assertFalse(buffer.isShipped(), "buffer docked");
        assertEq(vault.nav(), 750_000e6, "docking moves no capital, so NAV is unchanged");
    }

    function test_curatorCanCallBufferAtAnyCoverage() public {
        _deploy(WAD);
        _activate();
        vm.prank(curator);
        vault.callBuffer();
        assertFalse(buffer.isShipped());
    }

    /// @notice Filling against the buffer leaves the vault holding the risky asset, and that
    ///         inventory is marked into NAV like any other position.
    function test_riskyInventoryFromBufferFillsIsMarkedIntoNav() public {
        _deploy(WAD);
        _activate();

        // Simulate a fill: the vault paid out 100k USDC and took in 50 WETH.
        vm.prank(address(vault));
        quote.transfer(address(0xfee), 100_000e6);
        risky.mint(address(vault), 50e18); // 50 * 2000 = 100k USDC

        assertEq(vault.nav(), V0, "inventory marked at the oracle price");
    }

    // ------------------------------------------------------------ derived terms

    /// @notice Senior's terms are priced off realised demand, not configured ahead of it.
    function test_splitIsDerivedFromRealisedJuniorShare() public {
        _activate();
        (,,, uint256 feeSplitWad,,) = vault.terms();
        // j = 30%, lambda = 0.7  ->  s = 0.7 * (1 - 0.6) / (1 - 0.3) = 40%
        assertApproxEqAbs(feeSplitWad, 0.4e18, 2, "split derived at activation");
    }

    /// @notice At j >= 50% no split leaves junior better off than simply LPing, so no valid terms
    ///         exist and the epoch cannot activate. The wall is arithmetic, not a hardcoded guard.
    function test_activationRejectedWhenNoValidSplitExists() public {
        quote.mint(alice, 400_000e6);
        quote.mint(bob, 600_000e6);
        vm.startPrank(alice);
        quote.approve(address(vault), 400_000e6);
        vault.depositSenior(400_000e6);
        vm.stopPrank();
        vm.startPrank(bob);
        quote.approve(address(vault), 600_000e6);
        vault.depositJunior(600_000e6);
        vm.stopPrank();

        vm.warp(subEnd);
        vm.expectRevert(abi.encodeWithSelector(TrancheVault.NoValidSplit.selector, 0.6e18));
        vault.activate();
    }

    /// @notice A losing epoch pays senior principal priority and no coupon.
    function test_losingEpochPaysSeniorNoCoupon() public {
        _activate();
        position.setValue((V0 * 90) / 100); // -10%

        vm.warp(subEnd + T);
        vault.beginSettlement();
        vault.settle();

        assertEq(vault.seniorClaimAtSettlement(), S0, "principal only");
        assertEq(vault.seniorPot(), S0, "senior whole but unpaid");
        assertEq(vault.juniorPot(), (V0 * 90) / 100 - S0, "junior absorbs the whole loss");
    }

    // ------------------------------------------------------------ range authority

    function test_rebalanceRecordsWhatItCost() public {
        _activate();
        position.setRebalanceLoss(1_000e6);

        vm.prank(curator);
        vault.rebalance("");

        assertEq(position.rebalanceCalls(), 1);
        assertEq(vault.rebalanceCost(), 1_000e6, "cost measured, not hidden");
        assertEq(vault.rebalanceCount(), 1);
    }

    /// @notice The range freezes in distress. Exactly when a curator is most tempted to re-centre
    ///         is when re-centring does the most damage.
    function test_rebalanceBlockedInDistress() public {
        _activate();
        position.setValue(800_000e6); // b = (800k - 700k) / 700k = 14.3%, below the 20% floor

        assertLt(vault.coverageWad(), int256(0.2e18));
        vm.expectRevert();
        vm.prank(curator);
        vault.rebalance("");
    }

    function test_rebalanceRespectsCooldown() public {
        _activate();
        vm.prank(curator);
        vault.rebalance("");

        vm.expectRevert();
        vm.prank(curator);
        vault.rebalance("");

        vm.warp(block.timestamp + 6 hours);
        vm.prank(curator);
        vault.rebalance("");
        assertEq(vault.rebalanceCount(), 2);
    }

    function test_onlyCuratorMayRebalance() public {
        _activate();
        vm.expectRevert(TrancheVault.NotCurator.selector);
        vm.prank(alice);
        vault.rebalance("");
    }

    // ------------------------------------------------------------ quoting policy

    function test_inventoryCeilingIsSizedAgainstPrincipal() public {
        _activate();
        // maxInventoryWad = 30% of V0
        assertEq(vault.maxRiskyValue(), (V0 * 30) / 100);
    }

    function test_riskQuoteWidensAndStopsBiddingAsCoverageFalls() public {
        _activate();
        assertTrue(vault.riskQuote().bidAllowed, "healthy vault bids");
        uint256 healthySpread = vault.riskQuote().spreadWad;

        position.setValue(750_000e6); // coverage down to ~7%
        assertGt(vault.riskQuote().spreadWad, healthySpread, "spread widens as the buffer thins");

        position.setValue(690_000e6); // senior already under water
        assertFalse(vault.riskQuote().bidAllowed, "stops acquiring the risky asset");
        assertTrue(vault.riskQuote().askAllowed, "still sells");
    }

    // ------------------------------------------------------------ guards

    function test_degenerateEpochsRejected() public {
        // Junior only.
        quote.mint(bob, J0);
        vm.startPrank(bob);
        quote.approve(address(vault), J0);
        vault.depositJunior(J0);
        vm.stopPrank();
        vm.warp(subEnd);
        vm.expectRevert(TrancheVault.DegenerateEpoch.selector);
        vault.activate();
    }

    function test_juniorShareOutOfBoundsRejected() public {
        // j = 1% is below the 5% floor.
        quote.mint(alice, 990_000e6);
        quote.mint(bob, 10_000e6);
        vm.startPrank(alice);
        quote.approve(address(vault), 990_000e6);
        vault.depositSenior(990_000e6);
        vm.stopPrank();
        vm.startPrank(bob);
        quote.approve(address(vault), 10_000e6);
        vault.depositJunior(10_000e6);
        vm.stopPrank();

        vm.warp(subEnd);
        vm.expectRevert(abi.encodeWithSelector(TrancheVault.JuniorShareOutOfBounds.selector, 0.01e18));
        vault.activate();
    }

    function test_noEntryOrExitDuringActivePhase() public {
        _activate();
        quote.mint(alice, 1e6);
        vm.startPrank(alice);
        quote.approve(address(vault), 1e6);
        vm.expectRevert(TrancheVault.WrongPhase.selector);
        vault.depositSenior(1e6);
        vm.expectRevert(TrancheVault.WrongPhase.selector);
        vault.redeemSenior(1e6);
        vm.stopPrank();
    }

    function test_settleBlockedWhileRiskyInventoryOutstanding() public {
        _activate();
        position.setValue(V0);
        risky.mint(address(vault), 1e18);

        vm.warp(subEnd + T);
        vault.beginSettlement();
        vm.expectRevert(abi.encodeWithSelector(TrancheVault.RiskyInventoryOutstanding.selector, 1e18));
        vault.settle();
    }

    function test_settlementBlockedBeforeEpochEnd() public {
        _activate();
        vm.warp(subEnd + T - 1);
        vm.expectRevert(TrancheVault.EpochNotOver.selector);
        vault.beginSettlement();
    }

    function test_cancelRefundsDepositorsIfNeverActivated() public {
        _subscribe();
        vm.warp(subEnd + 1 days);
        vault.cancel();

        vm.prank(alice);
        assertEq(vault.redeemSenior(S0), S0, "senior refunded in full");
        vm.prank(bob);
        assertEq(vault.redeemJunior(J0), J0, "junior refunded in full");
    }

    function test_cancelBlockedDuringGrace() public {
        _subscribe();
        vm.warp(subEnd);
        vm.expectRevert(TrancheVault.GraceNotElapsed.selector);
        vault.cancel();
    }

    function test_couponAboveMaxRejectedAtDeploy() public {
        TrancheVault.Config memory cfg;
        cfg.couponWad = 0.02e18;
        cfg.maxCouponWad = 0.015e18;
        vm.expectRevert(TrancheVault.CouponAboveMax.selector);
        new TrancheVault(quote, risky, oracle, curator, cfg);
    }

    function test_donationLiftsCoverageWithoutMintingClaims() public {
        _activate();
        int256 before = vault.coverageWad();

        quote.mint(bob, 50_000e6);
        vm.startPrank(bob);
        quote.approve(address(vault), 50_000e6);
        vault.donate(50_000e6);
        vm.stopPrank();

        assertGt(vault.coverageWad(), before, "cure lifts coverage");
        assertEq(vault.junior().totalSupply(), J0, "no new claims minted");
    }
}
