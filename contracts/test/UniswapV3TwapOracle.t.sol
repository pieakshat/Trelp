// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IUniswapV3PoolObserver, UniswapV3TwapOracle} from "../src/oracles/UniswapV3TwapOracle.sol";
import {MockERC20, MockV3Pool} from "./mocks/Mocks.sol";

/// @notice The mark that coverage, the breaker, the buffer's spread and the settlement floor all
///         read. Its decimal handling is the thing `IQuoteOracle`'s unit contract exists to pin.
contract UniswapV3TwapOracleTest is Test {
    uint32 constant WINDOW = 30 minutes;

    /// @dev 1.0001^200311 ≈ 5e8 — WETH-wei per USDC-unit at roughly 2000 USDC/ETH. A pool's tick
    ///      is signed by token ordering, so the sign flips when WETH sorts first.
    int24 constant USDC_WETH_TICK = 200_311;

    MockERC20 usdc;
    MockERC20 weth;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
    }

    function _oracle(address quote_, address risky_) internal returns (UniswapV3TwapOracle, MockV3Pool) {
        MockV3Pool pool = new MockV3Pool(quote_, risky_);
        return (new UniswapV3TwapOracle(IUniswapV3PoolObserver(address(pool)), quote_, risky_, WINDOW), pool);
    }

    /// @dev CREATE addresses are unordered, so which token the pool calls `token0` is luck. The
    ///      tick describes token1 per token0, so it inverts with that ordering.
    function _usdcWethTick() internal view returns (int24) {
        return address(usdc) < address(weth) ? USDC_WETH_TICK : -USDC_WETH_TICK;
    }

    // ---------------------------------------------------------------- units

    /// @notice A tick already expresses the ratio in raw base units, so a 6-decimal quote and an
    ///         18-decimal risky asset come out right with no scaling anywhere in the contract.
    function test_returnsQuoteBaseUnitsAcrossMismatchedDecimals() public {
        (UniswapV3TwapOracle oracle, MockV3Pool pool) = _oracle(address(usdc), address(weth));
        pool.setMeanTick(_usdcWethTick(), WINDOW);

        uint256 value = oracle.valueInQuote(address(weth), 1e18);
        assertApproxEqRel(value, 2000e6, 0.01e18, "1 WETH marks near 2000 USDC, in USDC units");
        assertLt(value, 1e12, "and emphatically not 2000e18");
    }

    /// @notice Scaling is linear in the amount, so a fractional position marks proportionally.
    function test_valueIsLinearInAmount() public {
        (UniswapV3TwapOracle oracle, MockV3Pool pool) = _oracle(address(usdc), address(weth));
        pool.setMeanTick(_usdcWethTick(), WINDOW);

        uint256 whole = oracle.valueInQuote(address(weth), 1e18);
        assertApproxEqRel(oracle.valueInQuote(address(weth), 0.5e18), whole / 2, 1e12);
        assertApproxEqRel(oracle.valueInQuote(address(weth), 10e18), whole * 10, 1e12);
    }

    /// @notice Token ordering in the pool is incidental; the answer must not depend on it.
    function test_orderingDoesNotChangeTheAnswer() public {
        MockERC20 lo = new MockERC20("Low", "LO", 18);
        MockERC20 hi = new MockERC20("High", "HI", 18);
        (address a, address b) =
            address(lo) < address(hi) ? (address(lo), address(hi)) : (address(hi), address(lo));

        // risky as token0, then as token1, at the reciprocal tick — same price either way.
        (UniswapV3TwapOracle asToken0, MockV3Pool p0) = _oracle(b, a);
        p0.setMeanTick(6931, WINDOW); // ~2x
        (UniswapV3TwapOracle asToken1, MockV3Pool p1) = _oracle(a, b);
        p1.setMeanTick(-6931, WINDOW); // ~1/2, i.e. the same 2x the other way round

        assertApproxEqRel(
            asToken0.valueInQuote(a, 1e18), asToken1.valueInQuote(b, 1e18), 0.001e18, "symmetric"
        );
    }

    function test_quoteAssetValuesAsItself() public {
        (UniswapV3TwapOracle oracle,) = _oracle(address(usdc), address(weth));
        assertEq(oracle.valueInQuote(address(usdc), 1234e6), 1234e6, "identity, no pool read");
    }

    function test_rejectsATokenItDoesNotPrice() public {
        (UniswapV3TwapOracle oracle,) = _oracle(address(usdc), address(weth));
        MockERC20 other = new MockERC20("Other", "OTH", 18);
        vm.expectRevert(abi.encodeWithSelector(UniswapV3TwapOracle.UnsupportedToken.selector, address(other)));
        oracle.valueInQuote(address(other), 1e18);
    }

    // ---------------------------------------------------------------- averaging

    function test_meanTickIsTheAverageOverTheWindow() public {
        (UniswapV3TwapOracle oracle, MockV3Pool pool) = _oracle(address(usdc), address(weth));
        pool.setMeanTick(1000, WINDOW);
        assertEq(oracle.meanTick(), 1000);
    }

    /// @notice Truncation toward zero would read a negative mean one tick high, marking the risky
    ///         asset above its true average — the wrong direction for a solvency signal.
    function test_negativeMeanRoundsTowardNegativeInfinity() public {
        (UniswapV3TwapOracle oracle, MockV3Pool pool) = _oracle(address(usdc), address(weth));

        // -1 tick per second would be -WINDOW exactly; one short of that must round down, not up.
        pool.setCumulatives(0, -int56(uint56(WINDOW)) - 1);
        assertEq(oracle.meanTick(), -2, "rounds down");

        pool.setCumulatives(0, -int56(uint56(WINDOW)));
        assertEq(oracle.meanTick(), -1, "exact division is untouched");
    }

    function test_positiveMeanTruncatesNormally() public {
        (UniswapV3TwapOracle oracle, MockV3Pool pool) = _oracle(address(usdc), address(weth));
        pool.setCumulatives(0, int56(uint56(WINDOW)) + 1);
        assertEq(oracle.meanTick(), 1);
    }

    // ---------------------------------------------------------------- guards

    /// @notice A window the pool cannot answer must fail loudly rather than quietly shorten.
    function test_staleWindowReverts() public {
        (UniswapV3TwapOracle oracle, MockV3Pool pool) = _oracle(address(usdc), address(weth));
        pool.setMeanTick(_usdcWethTick(), WINDOW);
        pool.setStale(true);

        vm.expectRevert(bytes("OLD"));
        oracle.valueInQuote(address(weth), 1e18);
    }

    function test_rejectsAPoolOverTheWrongPair() public {
        MockERC20 other = new MockERC20("Other", "OTH", 18);
        MockV3Pool pool = new MockV3Pool(address(usdc), address(other));
        vm.expectRevert(UniswapV3TwapOracle.PairMismatch.selector);
        new UniswapV3TwapOracle(IUniswapV3PoolObserver(address(pool)), address(usdc), address(weth), WINDOW);
    }

    function test_rejectsAZeroWindow() public {
        MockV3Pool pool = new MockV3Pool(address(usdc), address(weth));
        vm.expectRevert(UniswapV3TwapOracle.ZeroWindow.selector);
        new UniswapV3TwapOracle(IUniswapV3PoolObserver(address(pool)), address(usdc), address(weth), 0);
    }

    /// @notice Whatever the pool reports, a bigger position never marks smaller.
    function testFuzz_valueIsMonotoneInAmount(int24 tick, uint256 a, uint256 b) public {
        tick = int24(bound(int256(tick), -400_000, 400_000));
        a = bound(a, 1, 1e24);
        b = bound(b, 1, 1e24);
        if (a > b) (a, b) = (b, a);

        (UniswapV3TwapOracle oracle, MockV3Pool pool) = _oracle(address(usdc), address(weth));
        pool.setMeanTick(tick, WINDOW);
        assertLe(oracle.valueInQuote(address(weth), a), oracle.valueInQuote(address(weth), b));
    }
}
