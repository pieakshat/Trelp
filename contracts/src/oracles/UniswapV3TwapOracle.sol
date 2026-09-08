// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {IQuoteOracle} from "../interfaces/IQuoteOracle.sol";

/// @notice The slice of a Uniswap v3 pool this oracle reads.
interface IUniswapV3PoolObserver {
    /// @dev Reverts with `OLD` if the requested window predates the pool's stored observations,
    ///      which is the staleness guard: a window longer than the pool can answer fails loudly
    ///      rather than silently shortening.
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);

    function token0() external view returns (address);
    function token1() external view returns (address);
}

/// @title UniswapV3TwapOracle
/// @notice Time-averaged mark for the vault's risky asset, read from an established v3 pool.
///
/// @dev The mark drives coverage, which drives the breaker, the buffer's spread and the floor on
///      settlement sales. A spot-readable price would let one block's trade move all of them, so
///      the price is averaged over `window` seconds: moving it requires holding the pool away from
///      the market for the whole window, against arbitrage, rather than for a single transaction.
///
///      The reference pool is deliberately *not* the vault's own v4 pool. That pool is thin, gated
///      to a single LP, and priced by the very policy this oracle feeds — quoting off it would let
///      the vault mark its own book.
///
///      Decimals need no special handling here, which is the main reason to prefer a pool tick over
///      a price feed. A tick already expresses token1 per token0 in *raw base units*, so passing an
///      amount in the risky asset's own units yields a value in the quote asset's own units, and
///      `IQuoteOracle`'s unit contract is satisfied by construction. There is no feed scale, token
///      scale and quote scale to reconcile, and so no way to get that reconciliation wrong.
contract UniswapV3TwapOracle is IQuoteOracle {
    error UnsupportedToken(address token);
    error ZeroWindow();
    error PairMismatch();

    IUniswapV3PoolObserver public immutable pool;
    address public immutable quote;
    address public immutable risky;

    /// @notice Averaging window, in seconds.
    uint32 public immutable window;

    bool internal immutable riskyIsToken0;

    constructor(IUniswapV3PoolObserver pool_, address quote_, address risky_, uint32 window_) {
        if (window_ == 0) revert ZeroWindow();

        address t0 = pool_.token0();
        address t1 = pool_.token1();
        if (!((t0 == quote_ && t1 == risky_) || (t0 == risky_ && t1 == quote_))) revert PairMismatch();

        pool = pool_;
        quote = quote_;
        risky = risky_;
        window = window_;
        riskyIsToken0 = (t0 == risky_);
    }

    /// @inheritdoc IQuoteOracle
    function valueInQuote(address token, uint256 amount) external view returns (uint256 value) {
        if (token == quote) return amount;
        if (token != risky) revert UnsupportedToken(token);
        if (amount == 0) return 0;
        return _quoteAtTick(meanTick(), amount);
    }

    /// @notice The arithmetic mean tick over the window.
    function meanTick() public view returns (int24 tick) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = window;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives,) = pool.observe(secondsAgos);
        int56 delta = tickCumulatives[1] - tickCumulatives[0];

        tick = int24(delta / int56(uint56(window)));
        // Solidity truncates toward zero; the tick scale needs rounding toward negative infinity,
        // or a negative mean reads one tick high and marks the risky asset above the true average.
        if (delta < 0 && delta % int56(uint56(window)) != 0) tick--;
    }

    /// @dev Squaring `sqrtPriceX96` overflows once it exceeds 2^128, so the wide branch drops the
    ///      ratio to X128 first. Both branches keep full precision through `FullMath.mulDiv`.
    function _quoteAtTick(int24 tick, uint256 amount) internal view returns (uint256) {
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);

        if (sqrtPriceX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            return riskyIsToken0
                ? FullMath.mulDiv(ratioX192, amount, 1 << 192)
                : FullMath.mulDiv(1 << 192, amount, ratioX192);
        }

        uint256 ratioX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);
        return riskyIsToken0
            ? FullMath.mulDiv(ratioX128, amount, 1 << 128)
            : FullMath.mulDiv(1 << 128, amount, ratioX128);
    }
}
