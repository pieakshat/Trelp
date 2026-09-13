// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {ISpotSwapper} from "../interfaces/ISpotSwapper.sol";

/// @notice The slice of the Uniswap v3 router this swapper calls.
/// @dev Declared locally rather than imported, so v3-periphery stays out of the dependency tree
///      for one struct and one function.
interface IUniswapV3SwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

/// @title V3SpotSwapper
/// @notice Converts between the vault's two assets on a Uniswap v3 pool.
///
/// @dev Holds nothing between calls: it pulls the input, swaps, and the router pays the output
///      straight back to the caller. A balance stranded here would sit outside `nav()` and so be
///      invisible to the waterfall.
///
///      The pair is pinned at construction. Callers pass token addresses, and a swapper that
///      accepted any pair would route a mistyped argument into a pool nobody chose.
///
///      Routing through the same pool `UniswapV3TwapOracle` reads is deliberate. `liquidate()`
///      floors its proceeds against the oracle mark, and that floor only means something if the
///      mark and the fill come from one market rather than two unrelated ones.
contract V3SpotSwapper is ISpotSwapper {
    using SafeTransferLib for ERC20;

    error UnsupportedPair(address tokenIn, address tokenOut);
    error ZeroAmount();

    IUniswapV3SwapRouter public immutable router;
    address public immutable quote;
    address public immutable risky;

    /// @notice Fee tier of the pool to route through.
    uint24 public immutable feeTier;

    constructor(IUniswapV3SwapRouter router_, address quote_, address risky_, uint24 feeTier_) {
        router = router_;
        quote = quote_;
        risky = risky_;
        feeTier = feeTier_;
    }

    /// @inheritdoc ISpotSwapper
    /// @dev The deadline is this block. Callers already carry the price bound in `minOut`, and a
    ///      longer window would only widen the gap between the quote they checked and the fill.
    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external
        returns (uint256 amountOut)
    {
        bool supported =
            (tokenIn == quote && tokenOut == risky) || (tokenIn == risky && tokenOut == quote);
        if (!supported) revert UnsupportedPair(tokenIn, tokenOut);
        if (amountIn == 0) revert ZeroAmount();

        ERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        ERC20(tokenIn).safeApprove(address(router), amountIn);

        amountOut = router.exactInputSingle(
            IUniswapV3SwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: feeTier,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: 0
            })
        );

        // A full fill consumes the allowance; clear it in case the router took less.
        ERC20(tokenIn).safeApprove(address(router), 0);
    }
}
