// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";

/// @title RangeMath
/// @notice Position composition for a concentrated range, and the floor the range covenant uses.
/// @dev Both directions live here rather than pulling in v4-periphery, which ships
///      `getLiquidityForAmounts` but not its inverse and resolves v4-core to a nested copy —
///      importing it alongside our own makes solc load every core interface twice. Pure, so the
///      covenant governing the curator's range authority is testable without a fork.
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

    /// @notice Composition at whichever bound leaves the position holding only the risky asset.
    /// @dev A pool price is currency1 per currency0, so the risky asset getting cheaper moves the
    ///      price down only when risky is currency0; when it is currency1 the same move pushes the
    ///      price up. The exposed bound is therefore the lower tick in the first case and the upper
    ///      tick in the second.
    ///
    ///      Past that bound the position is fully converted, so composition stops changing and
    ///      value tracks price one-for-one — no square-root cushion left. Senior's protection has
    ///      to be intact there, not merely at spot.
    function amountsAtRiskyBound(
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint128 liquidity,
        bool riskyIsCurrency0
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtAtBound = riskyIsCurrency0 ? sqrtLowerX96 : sqrtUpperX96;
        return amountsForLiquidity(sqrtAtBound, sqrtLowerX96, sqrtUpperX96, liquidity);
    }

    /// @notice Liquidity supported by the given amounts at the given price.
    function getLiquidityForAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtLowerX96 > sqrtUpperX96) (sqrtLowerX96, sqrtUpperX96) = (sqrtUpperX96, sqrtLowerX96);

        if (sqrtPriceX96 <= sqrtLowerX96) {
            liquidity = _forAmount0(sqrtLowerX96, sqrtUpperX96, amount0);
        } else if (sqrtPriceX96 < sqrtUpperX96) {
            uint128 l0 = _forAmount0(sqrtPriceX96, sqrtUpperX96, amount0);
            uint128 l1 = _forAmount1(sqrtLowerX96, sqrtPriceX96, amount1);
            liquidity = l0 < l1 ? l0 : l1;
        } else {
            liquidity = _forAmount1(sqrtLowerX96, sqrtUpperX96, amount1);
        }
    }

    function _forAmount0(uint160 sqrtAX96, uint160 sqrtBX96, uint256 amount0) private pure returns (uint128) {
        if (sqrtAX96 > sqrtBX96) (sqrtAX96, sqrtBX96) = (sqrtBX96, sqrtAX96);
        uint256 intermediate = FullMath.mulDiv(sqrtAX96, sqrtBX96, FixedPoint96.Q96);
        return uint128(FullMath.mulDiv(amount0, intermediate, sqrtBX96 - sqrtAX96));
    }

    function _forAmount1(uint160 sqrtAX96, uint160 sqrtBX96, uint256 amount1) private pure returns (uint128) {
        if (sqrtAX96 > sqrtBX96) (sqrtAX96, sqrtBX96) = (sqrtBX96, sqrtAX96);
        return uint128(FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtBX96 - sqrtAX96));
    }
}
