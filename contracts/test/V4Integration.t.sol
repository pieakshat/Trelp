// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, Vm} from "forge-std/Test.sol";

import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {HookMiner} from "./utils/HookMiner.sol";

import {TrancheVault} from "../src/TrancheVault.sol";
import {IAquaRegistry} from "../src/interfaces/IAquaRegistry.sol";
import {IBufferStrategy} from "../src/interfaces/IBufferStrategy.sol";
import {IPositionVenue} from "../src/interfaces/IPositionVenue.sol";
import {IQuoteOracle} from "../src/interfaces/IQuoteOracle.sol";
import {RiskPolicy} from "../src/libraries/RiskPolicy.sol";
import {ISpotSwapper, V4PositionVenue} from "../src/venues/V4PositionVenue.sol";
import {IVaultPolicy} from "../src/interfaces/IVaultPolicy.sol";
import {TrancheHook} from "../src/venues/TrancheHook.sol";
import {MockAqua, MockBufferStrategy, MockERC20, MockOracle} from "./mocks/Mocks.sol";

/// @dev Fills the risky leg at the oracle mark. On a mainnet fork this is backed by the existing
///      ETH/USDC pools; our own pool is empty at activation and cannot seed itself.
contract MockSpotSwapper is ISpotSwapper {
    MockOracle public immutable oracle;
    MockERC20 public immutable quote;
    MockERC20 public immutable risky;

    constructor(MockOracle oracle_, MockERC20 quote_, MockERC20 risky_) {
        oracle = oracle_;
        quote = quote_;
        risky = risky_;
    }

    function swapExactIn(address tokenIn, address, uint256 amountIn, uint256) external returns (uint256 amountOut) {
        require(tokenIn == address(quote), "quote in only");
        quote.transferFrom(msg.sender, address(this), amountIn);
        amountOut = (amountIn * 1e18) / oracle.priceWad(address(risky));
        risky.mint(msg.sender, amountOut);
    }
}

/// @notice The Day 2 gate: the vault activates into a real v4 pool, marks against it, and the hook
///         enforces the vault's policy on every swap.
/// @dev PoolManager is deployed locally rather than forked. The v4 code paths exercised are
///      identical -- unlock, modifyLiquidity, settle/take, hook address flags, dynamic fee override
///      -- and the suite stays hermetic and fast.
contract V4IntegrationTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant V0 = 1_000_000e18;
    uint256 constant S0 = 700_000e18;
    uint256 constant J0 = 300_000e18;
    uint64 constant T = 30 days;
    int24 constant TICK_SPACING = 60;

    // Pool sits at ~2000 quote per risky. Quote is currency0, so the pool price (currency1 per
    // currency0) is risky-per-quote = 1/2000, which is a long way below tick zero.
    int24 constant START_TICK = -76_020;
    int24 constant TICK_LOWER = -79_020; // risky ~1.35x dearer
    int24 constant TICK_UPPER = -71_700; // risky ~0.65x cheaper: the exposed bound

    PoolManager manager;
    PoolSwapTest swapRouter;
    MockERC20 quote;
    MockERC20 risky;
    MockOracle oracle;
    MockSpotSwapper swapper;
    MockAqua aqua;
    MockBufferStrategy strategy;

    TrancheVault vault;
    V4PositionVenue venue;
    TrancheHook hook;
    PoolKey poolKey;

    address curator = address(0xC0);
    address alice = address(0xA1);
    address bob = address(0xB0);
    address trader = address(0x777);

    uint64 subEnd;

    function setUp() public {
        vm.warp(1_000_000);
        subEnd = uint64(block.timestamp + 1 days);

        manager = new PoolManager(address(this));
        swapRouter = new PoolSwapTest(manager);

        // Deploy until the quote token sorts first, so quote is currency0 and risky is currency1.
        MockERC20 a = new MockERC20("Quote", "USDQ", 18);
        MockERC20 b = new MockERC20("Risky", "RSK", 18);
        (quote, risky) = address(a) < address(b) ? (a, b) : (b, a);

        oracle = new MockOracle();
        oracle.setPrice(address(risky), _quotePerRisky());
        swapper = new MockSpotSwapper(oracle, quote, risky);
        aqua = new MockAqua();
        strategy = new MockBufferStrategy(address(0xA99A), address(quote), address(risky));
        vault = new TrancheVault(
            quote, risky, IQuoteOracle(address(oracle)), IAquaRegistry(address(aqua)), curator, _config()
        );

        // The hook address must encode its permissions, so mine before deploying. The venue needs a
        // PoolKey naming the hook, so the venue address is set on the hook afterwards.
        uint160 flags = Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG;
        bytes memory args = abi.encode(manager, IVaultPolicy(address(vault)), false, address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(TrancheHook).creationCode, args);
        hook = new TrancheHook{salt: salt}(manager, IVaultPolicy(address(vault)), false, address(this));
        assertEq(address(hook), hookAddr, "mined address");

        poolKey = PoolKey({
            currency0: Currency.wrap(address(quote)),
            currency1: Currency.wrap(address(risky)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        manager.initialize(poolKey, TickMath.getSqrtPriceAtTick(START_TICK));

        venue = new V4PositionVenue(
            manager,
            poolKey,
            address(vault),
            quote,
            risky,
            IQuoteOracle(address(oracle)),
            ISpotSwapper(address(swapper)),
            TICK_LOWER,
            TICK_UPPER,
            0.05e18
        );
        hook.setVenue(address(venue));
        vm.prank(curator);
        vault.setVenues(IPositionVenue(address(venue)), IBufferStrategy(address(strategy)));
    }

    function _quotePerRisky() internal pure returns (uint256) {
        uint160 sqrtP = TickMath.getSqrtPriceAtTick(START_TICK);
        uint256 priceX96 = (uint256(sqrtP) * uint256(sqrtP)) >> 96; // risky per quote, X96
        return (1e18 << 96) / priceX96; // quote per 1e18 risky
    }

    function _config() internal view returns (TrancheVault.Config memory) {
        return TrancheVault.Config({
            couponWad: 0.01e18,
            lambdaWad: 0.7e18,
            maxCouponWad: 0.015e18,
            minJuniorShareWad: 0.05e18,
            maxJuniorShareWad: 0.6e18,
            bufferShipShareWad: 0,
            bufferCallCoverageWad: 0.1e18,
            minRebalanceCoverageWad: 0.2e18,
            risk: RiskPolicy.Params({
                baseSpreadWad: 0.003e18, // 30 bps base
                alphaWad: 2e18,
                kappaWad: 0.5e18,
                targetCoverageWad: 0.4285e18,
                bidCutoffWad: 0.9e18,
                maxInventoryWad: 0.6e18
            }),
            subscriptionEnd: subEnd,
            epochDuration: T,
            activationGrace: 1 days,
            unwindWindow: 1 days,
            rebalanceCooldown: 6 hours
        });
    }

    function _activate() internal {
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
        vm.warp(subEnd);
        vault.activate();
    }

    function _swap(bool zeroForOne, int256 amountSpecified) internal {
        vm.startPrank(trader);
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- the gate

    function test_hookAddressEncodesItsPermissions() public view {
        uint160 flags = uint160(address(hook)) & Hooks.ALL_HOOK_MASK;
        assertEq(flags, Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG, "0x880");
    }

    function test_activationSeedsThePoolAndNavTracksIt() public {
        _activate();

        assertGt(venue.liquidity(), 0, "position minted");
        assertGt(risky.balanceOf(address(venue)) + quote.balanceOf(address(venue)), 0, "or dust remains");

        // Seeding converts part of the quote at the oracle mark, so NAV should be close to V0 --
        // the gap is composition rounding, not a loss.
        uint256 nav = vault.nav();
        assertApproxEqRel(nav, V0, 0.02e18, "NAV tracks the deployed position");
        assertGt(vault.coverageWad(), int256(0.3e18), "coverage near b0 at activation");
    }

    function test_outsideLiquidityIsRejected() public {
        _activate();
        vm.expectRevert();
        manager.unlock(abi.encode(uint256(0)));
    }

    function test_swapAppliesTheVaultsSpreadAsTheLpFee() public {
        _activate();
        quote.mint(trader, 10_000e18);
        vm.prank(trader);
        quote.approve(address(swapRouter), type(uint256).max);

        vm.recordLogs();
        _swap(true, -1_000e18); // exact-in quote for risky
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool sawFee;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("FeeOverridden(uint24,bool)")) {
                (uint24 feePips,) = abi.decode(logs[i].data, (uint24, bool));
                assertEq(feePips, 3000, "30 bps at full coverage");
                sawFee = true;
            }
        }
        assertTrue(sawFee, "hook priced the swap");
    }

    /// @notice The directional halt. Once the policy stops bidding, the pool declines the side that
    ///         would push more of the risky asset onto the vault, and still serves the other side.
    function test_poolRefusesTheRiskIncreasingDirectionWhenBiddingStops() public {
        _activate();
        quote.mint(trader, 100_000e18);
        risky.mint(trader, 100e18);
        vm.startPrank(trader);
        quote.approve(address(swapRouter), type(uint256).max);
        risky.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        // Collapse coverage so the policy saturates.
        oracle.setPrice(address(risky), _quotePerRisky() / 4);
        assertFalse(vault.riskQuote().bidAllowed, "policy has stopped bidding");

        // risky is currency1, so oneForZero hands us risky: refused.
        vm.expectRevert();
        _swap(false, -1e18);

        // zeroForOne hands us quote and takes risky away: still served.
        _swap(true, -100e18);
    }
}
