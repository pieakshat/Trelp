// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RiskPolicy} from "../src/libraries/RiskPolicy.sol";

/// @notice The breaker, tested as a curve. Paths 3 and 4 of the demo differ only in whether these
///         numbers are applied, so this is where the protection is actually specified.
contract RiskPolicyTest is Test {
    uint256 constant WAD = 1e18;
    int256 constant B0 = 0.428571428571428571e18; // j = 30% -> b0 = j / (1 - j)

    function _params() internal pure returns (RiskPolicy.Params memory) {
        return RiskPolicy.Params({
            baseSpreadWad: 0.0005e18,
            alphaWad: 2e18,
            kappaWad: 0.5e18,
            targetCoverageWad: B0,
            bidCutoffWad: 0.9e18,
            maxInventoryWad: 0.3e18
        });
    }

    function test_distressIsZeroAtOrAboveTarget() public pure {
        assertEq(RiskPolicy.distressWad(B0, B0), 0);
        assertEq(RiskPolicy.distressWad(B0 * 2, B0), 0, "over-covered is not distressed");
    }

    function test_distressSaturatesOnceBufferIsGone() public pure {
        assertEq(RiskPolicy.distressWad(0, B0), WAD, "buffer exactly exhausted");
        assertEq(RiskPolicy.distressWad(-0.1e18, B0), WAD, "senior already impaired");
    }

    function test_distressIsLinearBetween() public pure {
        assertApproxEqAbs(RiskPolicy.distressWad(B0 / 2, B0), 0.5e18, 2, "half the buffer gone");
        assertApproxEqAbs(RiskPolicy.distressWad(B0 / 4, B0), 0.75e18, 2);
    }

    function test_spreadWidensWithDistress() public pure {
        RiskPolicy.Params memory p = _params();
        uint256 healthy = RiskPolicy.evaluate(p, B0, 0, 1e12).spreadWad;
        uint256 half = RiskPolicy.evaluate(p, B0 / 2, 0, 1e12).spreadWad;
        uint256 gone = RiskPolicy.evaluate(p, 0, 0, 1e12).spreadWad;

        assertEq(healthy, p.baseSpreadWad, "base spread at full coverage");
        // alpha = 2, d = 0.5 -> spread = base * (1 + 1) = 2x base
        assertApproxEqAbs(half, 2 * p.baseSpreadWad, 2, "doubled at half distress");
        assertApproxEqAbs(gone, 3 * p.baseSpreadWad, 2, "tripled once the buffer is gone");
        assertGt(gone, half);
        assertGt(half, healthy);
    }

    /// @notice Stage 2 of the original three-stage breaker, as a region of the curve: past the
    ///         cutoff the vault stops acquiring the risky asset and quotes sell-only.
    function test_bidStopsPastTheCutoff() public pure {
        RiskPolicy.Params memory p = _params();
        assertTrue(RiskPolicy.evaluate(p, B0, 0, 1e12).bidAllowed, "healthy: bidding");
        assertTrue(RiskPolicy.evaluate(p, B0 / 2, 0, 1e12).bidAllowed, "mild distress: still bidding");

        RiskPolicy.Quote memory q = RiskPolicy.evaluate(p, 0, 0, 1e12);
        assertFalse(q.bidAllowed, "saturated distress: no bid");
        assertTrue(q.askAllowed, "selling always allowed -- it reduces risk");
    }

    /// @notice The structural control. A deviation band caps extraction per fill; this caps it per
    ///         epoch, so an adversary cannot simply loop the band.
    function test_inventoryCapStopsBiddingEvenWhenHealthy() public pure {
        RiskPolicy.Params memory p = _params();
        uint256 principal = 1e12;

        assertTrue(RiskPolicy.evaluate(p, B0, (principal * 29) / 100, principal).bidAllowed, "under the cap");
        assertFalse(RiskPolicy.evaluate(p, B0, (principal * 30) / 100, principal).bidAllowed, "at the cap");
        assertFalse(RiskPolicy.evaluate(p, B0, (principal * 50) / 100, principal).bidAllowed, "over the cap");
    }

    function test_skewLeansAgainstInventory() public pure {
        RiskPolicy.Params memory p = _params();
        uint256 principal = 1e12;
        int256 noInventory = RiskPolicy.evaluate(p, B0 / 2, 0, principal).skewWad;
        int256 someInventory = RiskPolicy.evaluate(p, B0 / 2, principal / 5, principal).skewWad;

        assertEq(noInventory, 0, "nothing to lean against");
        assertGt(someInventory, 0, "skew away from the side we are accumulating");
    }

    function test_noSkewOrWideningWhenFullyCovered() public pure {
        RiskPolicy.Params memory p = _params();
        RiskPolicy.Quote memory q = RiskPolicy.evaluate(p, B0, 1e11, 1e12);
        assertEq(q.skewWad, 0, "inventory alone does not skew -- only distress does");
        assertEq(q.spreadWad, p.baseSpreadWad);
    }

    function testFuzz_spreadIsMonotoneInDistress(int256 worse, int256 better) public pure {
        worse = bound(worse, 1, B0);
        better = bound(better, 1, B0);
        if (worse > better) (worse, better) = (better, worse);
        RiskPolicy.Params memory p = _params();
        assertGe(
            RiskPolicy.evaluate(p, worse, 0, 1e12).spreadWad,
            RiskPolicy.evaluate(p, better, 0, 1e12).spreadWad
        );
    }
}
