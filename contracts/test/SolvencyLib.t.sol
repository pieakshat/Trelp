// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {SolvencyLib} from "../src/libraries/SolvencyLib.sol";

/// @notice Pins the worked example from the build plan (§2.6) to the implementation, so the pitch
///         numbers and the settlement code cannot drift apart.
contract SolvencyLibTest is Test {
    uint256 constant WAD = 1e18;

    // 1,000,000 USDC deployed, j = 30%, c = 1%/epoch, s = 40% of fees, 30 day epoch.
    uint256 constant V0 = 1_000_000e6;
    uint256 constant J0 = 300_000e6;
    uint256 constant S0 = 700_000e6;
    uint256 constant COUPON = 0.01e18;
    uint256 constant SPLIT = 0.4e18;
    uint64 constant T = 30 days;

    function _terms() internal pure returns (SolvencyLib.Terms memory) {
        return SolvencyLib.Terms({
            seniorPrincipal: S0,
            juniorPrincipal: J0,
            couponWad: COUPON,
            feeSplitWad: SPLIT,
            start: 1_000_000,
            duration: T
        });
    }

    function test_juniorShareAndInitialCoverage() public pure {
        SolvencyLib.Terms memory t = _terms();
        assertEq(SolvencyLib.totalPrincipal(t), V0);
        assertEq(SolvencyLib.juniorShareWad(t), 0.3e18, "j = 30%");
        // b0 = j / (1 - j) = 0.4285...
        assertApproxEqAbs(SolvencyLib.initialCoverageWad(t), 0.428571428571428571e18, 2, "b0 = 0.43");
    }

    function test_seniorClaimAccruesLinearlyAndClamps() public pure {
        SolvencyLib.Terms memory t = _terms();
        assertEq(SolvencyLib.accruedSeniorClaim(t, t.start), S0, "no accrual at t0");
        assertEq(SolvencyLib.accruedSeniorClaim(t, t.start - 1), S0, "no accrual before t0");
        // Half the epoch earns half the coupon.
        assertEq(SolvencyLib.accruedSeniorClaim(t, t.start + T / 2), S0 + (S0 * COUPON) / WAD / 2);
        assertEq(SolvencyLib.accruedSeniorClaim(t, t.start + T), S0 + (S0 * COUPON) / WAD, "full coupon");
        assertEq(
            SolvencyLib.accruedSeniorClaim(t, t.start + T * 10),
            S0 + (S0 * COUPON) / WAD,
            "clamped past epoch end"
        );
    }

    /// @notice The plan's normal month: f = 12%, the fixed rate binds, senior earns exactly 1%.
    function test_workedExample_flatPrice_juniorEarns37Point7Percent() public pure {
        SolvencyLib.Terms memory t = _terms();
        uint256 fees = (V0 * 12) / 100; // f = 12%

        uint256 claim = SolvencyLib.finalSeniorClaim(t, fees);
        assertEq(claim, S0 + (S0 * COUPON) / WAD, "fixed coupon binds, not the split");

        uint256 nav = V0 + fees; // flat price, k = 1
        (uint256 seniorPayout, uint256 juniorPayout) = SolvencyLib.waterfall(nav, claim);

        assertEq(seniorPayout, claim, "senior whole");
        // Junior return = juniorPayout / J0 - 1, expected +37.67%
        uint256 juniorReturnWad = (juniorPayout * WAD) / J0 - WAD;
        assertApproxEqRel(juniorReturnWad, 0.3766666e18, 1e12, "junior +37.7%");
        // and the unlevered LP would have made only f = 12%.
        assertApproxEqRel((nav * WAD) / V0 - WAD, 0.12e18, 1e12, "unlevered LP +12%");
    }

    /// @notice The plan's quiet month: the split clause caps the coupon the pool cannot pay, so
    ///         junior is not asked to fund senior's rate out of principal.
    function test_splitClauseProtectsJuniorInAQuietEpoch() public pure {
        SolvencyLib.Terms memory t = _terms();
        uint256 fees = (V0 * 1) / 100; // f = 1%

        uint256 claim = SolvencyLib.finalSeniorClaim(t, fees);
        uint256 splitCoupon = (fees * SPLIT) / WAD;
        assertEq(claim, S0 + splitCoupon, "split binds");
        assertLt(claim - S0, (S0 * COUPON) / WAD, "senior earns less than the fixed rate");
    }

    /// @notice Senior is capped at its claim; junior takes the entire residual, including recovery.
    function test_waterfall_juniorTakesResidualAndFirstLoss() public pure {
        SolvencyLib.Terms memory t = _terms();
        uint256 claim = SolvencyLib.finalSeniorClaim(t, (V0 * 12) / 100);

        // Blowout: everything above the senior claim belongs to junior.
        (uint256 sUp, uint256 jUp) = SolvencyLib.waterfall(2 * V0, claim);
        assertEq(sUp, claim, "senior does not participate in upside");
        assertEq(jUp, 2 * V0 - claim);

        // Crash below the claim: junior wiped, senior impaired.
        (uint256 sDown, uint256 jDown) = SolvencyLib.waterfall(V0 / 2, claim);
        assertEq(sDown, V0 / 2, "senior takes what is left");
        assertEq(jDown, 0, "junior wiped");

        // Exactly at the claim is the survival boundary.
        (uint256 sAt, uint256 jAt) = SolvencyLib.waterfall(claim, claim);
        assertEq(sAt, claim);
        assertEq(jAt, 0);
    }

    function test_coverageGoesNegativeWhenSeniorIsImpaired() public pure {
        // b = (NAV - claim) / claim
        assertEq(SolvencyLib.coverageWad(1430, 1000), 0.43e18);
        assertEq(SolvencyLib.coverageWad(1000, 1000), 0);
        assertEq(SolvencyLib.coverageWad(900, 1000), -0.1e18, "buffer exhausted");
        assertEq(SolvencyLib.buffer(900, 1000), -100);
    }

    /// @notice Whatever the fee path, senior never receives more than the fixed coupon.
    function testFuzz_seniorCouponNeverExceedsFixedRate(uint256 fees) public pure {
        fees = bound(fees, 0, 1e30);
        SolvencyLib.Terms memory t = _terms();
        uint256 coupon = SolvencyLib.finalSeniorClaim(t, fees) - S0;
        assertLe(coupon, (S0 * COUPON) / WAD);
    }

    /// @notice The waterfall is conservative and total: it never pays out more than NAV.
    function testFuzz_waterfallConservesValue(uint256 nav, uint256 claim) public pure {
        nav = bound(nav, 0, 1e36);
        claim = bound(claim, 1, 1e36);
        (uint256 s, uint256 j) = SolvencyLib.waterfall(nav, claim);
        assertEq(s + j, nav, "no value created or destroyed");
        assertLe(s, claim, "senior capped at its claim");
    }
}
