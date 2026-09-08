// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";

/// @title RangeMath
/// @notice Position composition for a concentrated range, and the floor the range covenant uses.
/// @dev v4-periphery ships `getLiquidityForAmounts` but not its inverse, so the composition side is
///      reconstructed here from v4-core's `SqrtPriceMath`. Pure, so the covenant that governs the
///      curator's range authority is testable without a fork.
library RangeMath {
    /// @notice Amounts of currency0 and currency1 backing `liquidity` at the given price.
    function amountsForLiquidity(
        uint160 sqrtPriceX96,
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtLowerX96 > sqrtUpperX96) (sqrtLowerX96, sqrtUpperX96) = (sqrtUpperX96, sqrtLowerX96);

        if (sqrtPriceX96 <= sqrtLowerX96) {
            // At or below the floor the position is entirely currency0.
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtLowerX96, sqrtUpperX96, liquidity, false);
        } else if (sqrtPriceX96 < sqrtUpperX96) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtUpperX96, liquidity, false);
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLowerX96, sqrtPriceX96, liquidity, false);
        } else {
            // At or above the ceiling the position is entirely currency1.
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLowerX96, sqrtUpperX96, liquidity, false);
        }
    }

    /// @notice Composition at the range's own lower bound: 100% currency0, no currency1.
    /// @dev This is the number the range covenant is written against. Below the lower bound the
    ///      position holds only the risky asset and its value falls linearly with price -- there is
    ///      no square-root cushion left, so senior's protection has to be intact at the floor, not
    ///      merely at spot.
    function amountsAtFloor(uint160 sqrtLowerX96, uint160 sqrtUpperX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        return amountsForLiquidity(sqrtLowerX96, sqrtLowerX96, sqrtUpperX96, liquidity);
    }
}
