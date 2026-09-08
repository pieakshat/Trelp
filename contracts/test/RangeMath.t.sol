// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import {RangeMath} from "../src/libraries/RangeMath.sol";

/// @notice The range covenant rests on these numbers, so they are pinned without a fork.
contract RangeMathTest is Test {
    int24 constant LOWER = -1000; // ~ -9.5%
    int24 constant UPPER = 1000; // ~ +10.5%
    uint128 constant L = 1e18;

    uint160 sqrtLower;
    uint160 sqrtUpper;
    uint160 sqrtMid;

    function setUp() public {
        sqrtLower = TickMath.getSqrtPriceAtTick(LOWER);
        sqrtUpper = TickMath.getSqrtPriceAtTick(UPPER);
        sqrtMid = TickMath.getSqrtPriceAtTick(0);
    }

    function test_atOrBelowFloorPositionIsEntirelyCurrency0() public view {
        (uint256 a0, uint256 a1) = RangeMath.amountsForLiquidity(sqrtLower, sqrtLower, sqrtUpper, L);
        assertGt(a0, 0, "holds currency0");
        assertEq(a1, 0, "no currency1 left at the floor");
    }

    function test_atOrAboveCeilingPositionIsEntirelyCurrency1() public view {
        (uint256 a0, uint256 a1) = RangeMath.amountsForLiquidity(sqrtUpper, sqrtLower, sqrtUpper, L);
        assertEq(a0, 0, "fully converted out of currency0");
        assertGt(a1, 0, "holds currency1");
    }

    function test_insideTheRangeHoldsBoth() public view {
        (uint256 a0, uint256 a1) = RangeMath.amountsForLiquidity(sqrtMid, sqrtLower, sqrtUpper, L);
        assertGt(a0, 0);
        assertGt(a1, 0);
    }

    function test_floorHelperMatchesEvaluatingAtTheLowerBound() public view {
        (uint256 f0, uint256 f1) = RangeMath.amountsAtFloor(sqrtLower, sqrtUpper, L);
        (uint256 a0, uint256 a1) = RangeMath.amountsForLiquidity(sqrtLower, sqrtLower, sqrtUpper, L);
        assertEq(f0, a0);
        assertEq(f1, a1);
    }

    /// @notice Why the covenant is written against the floor rather than spot: below the lower
    ///         bound the token amount stops changing, so value moves one-for-one with price. There
    ///         is no square-root cushion left down there -- the loss goes linear and unbounded.
    function test_belowTheFloorCompositionIsFrozenSoValueGoesLinear() public view {
        (uint256 atFloor,) = RangeMath.amountsForLiquidity(sqrtLower, sqrtLower, sqrtUpper, L);
        (uint256 wayBelow,) = RangeMath.amountsForLiquidity(sqrtLower / 2, sqrtLower, sqrtUpper, L);
        (uint256 farBelow,) = RangeMath.amountsForLiquidity(sqrtLower / 8, sqrtLower, sqrtUpper, L);

        assertEq(wayBelow, atFloor, "no further conversion is possible");
        assertEq(farBelow, atFloor, "so the only thing still moving is the price");
    }

    /// @notice Inside the range the position rotates out of currency0 as price rises, which is the
    ///         square-root cushion doing its work.
    function testFuzz_currency0FallsMonotonicallyAsPriceRises(uint160 lo, uint160 hi) public view {
        lo = uint160(bound(lo, sqrtLower, sqrtUpper));
        hi = uint160(bound(hi, sqrtLower, sqrtUpper));
        if (lo > hi) (lo, hi) = (hi, lo);

        (uint256 a0Low,) = RangeMath.amountsForLiquidity(lo, sqrtLower, sqrtUpper, L);
        (uint256 a0High,) = RangeMath.amountsForLiquidity(hi, sqrtLower, sqrtUpper, L);
        assertGe(a0Low, a0High);
    }

    function testFuzz_currency1RisesMonotonicallyAsPriceRises(uint160 lo, uint160 hi) public view {
        lo = uint160(bound(lo, sqrtLower, sqrtUpper));
        hi = uint160(bound(hi, sqrtLower, sqrtUpper));
        if (lo > hi) (lo, hi) = (hi, lo);

        (, uint256 a1Low) = RangeMath.amountsForLiquidity(lo, sqrtLower, sqrtUpper, L);
        (, uint256 a1High) = RangeMath.amountsForLiquidity(hi, sqrtLower, sqrtUpper, L);
        assertLe(a1Low, a1High);
    }

    /// @notice A tighter range concentrates the same liquidity into less inventory, which is the
    ///         capital efficiency the fee story depends on.
    function test_tighterRangeNeedsLessCapitalForTheSameLiquidity() public view {
        uint160 tightLower = TickMath.getSqrtPriceAtTick(-200);
        uint160 tightUpper = TickMath.getSqrtPriceAtTick(200);

        (uint256 wide0, uint256 wide1) = RangeMath.amountsForLiquidity(sqrtMid, sqrtLower, sqrtUpper, L);
        (uint256 tight0, uint256 tight1) = RangeMath.amountsForLiquidity(sqrtMid, tightLower, tightUpper, L);

        assertLt(tight0, wide0, "less currency0 for the same depth");
        assertLt(tight1, wide1, "less currency1 for the same depth");
    }

    function test_argumentOrderDoesNotMatter() public view {
        (uint256 a0, uint256 a1) = RangeMath.amountsForLiquidity(sqrtMid, sqrtLower, sqrtUpper, L);
        (uint256 b0, uint256 b1) = RangeMath.amountsForLiquidity(sqrtMid, sqrtUpper, sqrtLower, L);
        assertEq(a0, b0);
        assertEq(a1, b1);
    }
}
