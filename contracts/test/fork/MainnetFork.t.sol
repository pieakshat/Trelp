// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TrancheVault} from "../../src/TrancheVault.sol";
import {IAquaRegistry} from "../../src/interfaces/IAquaRegistry.sol";
import {IBufferStrategy} from "../../src/interfaces/IBufferStrategy.sol";
import {IPositionVenue} from "../../src/interfaces/IPositionVenue.sol";
import {IQuoteOracle} from "../../src/interfaces/IQuoteOracle.sol";
import {ISpotSwapper} from "../../src/interfaces/ISpotSwapper.sol";
import {IVaultPolicy} from "../../src/interfaces/IVaultPolicy.sol";
import {RiskPolicy} from "../../src/libraries/RiskPolicy.sol";
import {IUniswapV3PoolObserver, UniswapV3TwapOracle} from "../../src/oracles/UniswapV3TwapOracle.sol";
import {IUniswapV3SwapRouter, V3SpotSwapper} from "../../src/swappers/V3SpotSwapper.sol";
import {TrancheHook} from "../../src/venues/TrancheHook.sol";
import {V4PositionVenue} from "../../src/venues/V4PositionVenue.sol";
import {HookMiner} from "../utils/HookMiner.sol";

interface IV3PoolSlot0 {
    function slot0()
        external
        view
        returns (uint160, int24 tick, uint16, uint16, uint16, uint8, bool);
}

/// @notice The whole stack against mainnet: real USDC and WETH, a real v3 pool for the mark and the
///         swaps, and the real v4 PoolManager.
///
/// @dev Opt in with `MAINNET_RPC_URL`; the suite stays hermetic without it.
///
///      This is the first time the vault runs with a quote asset that is not 18 decimals. USDC has
///      6, so any place a raw amount is compared against a WAD, or a price is assumed to carry 18
///      decimals, fails here and nowhere else.
///
///      Aqua is deployed onto the fork rather than read from it. There is no recorded mainnet
///      deployment: the SwapVM ignition parameters still carry a zero address for it.
contract MainnetForkTest is Test {
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant V3_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // USDC/WETH, 5 bps
    address constant V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant V4_POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    uint24 constant V3_FEE = 500;
    int24 constant TICK_SPACING = 60;
    uint32 constant TWAP_WINDOW = 30 minutes;

    // USDC is the quote, so principals carry 6 decimals.
    uint256 constant S0 = 700_000e6;
    uint256 constant J0 = 300_000e6;
    uint256 constant SHIP_SHARE = 0.3e18;
    uint64 constant T = 30 days;

    IPoolManager manager = IPoolManager(V4_POOL_MANAGER);
    ERC20 quote = ERC20(USDC);
    ERC20 risky = ERC20(WETH);

    UniswapV3TwapOracle oracle;
    V3SpotSwapper swapper;
    TrancheVault vault;
    TrancheHook hook;
    V4PositionVenue venue;
    PoolKey poolKey;
    address aqua;
    address router;
    address adjuster;
    address strategy;

    int24 startTick;
    address curator = address(0xC0);
    address alice = address(0xA1);
    address bob = address(0xB0);
    uint64 subEnd;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);

        subEnd = uint64(block.timestamp + 1 days);

        oracle = new UniswapV3TwapOracle(IUniswapV3PoolObserver(V3_POOL), USDC, WETH, TWAP_WINDOW);
        swapper = new V3SpotSwapper(IUniswapV3SwapRouter(V3_ROUTER), USDC, WETH, V3_FEE);

        aqua = deployCode("Aqua.sol:Aqua");
        router = deployCode(
            "AquaSwapVMRouter.sol:AquaSwapVMRouter",
            abi.encode(aqua, WETH, address(this), "SwapVM", "1.0.0")
        );

        vault = new TrancheVault(
            quote, risky, IQuoteOracle(address(oracle)), IAquaRegistry(aqua), curator, _config()
        );

        uint160 flags = Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG;
        bytes memory args = abi.encode(manager, IVaultPolicy(address(vault)), address(this));
        (address expected, bytes32 salt) =
            HookMiner.find(address(this), flags, type(TrancheHook).creationCode, args);
        hook = new TrancheHook{salt: salt}(manager, IVaultPolicy(address(vault)), address(this));
        assertEq(address(hook), expected, "mined address");

        // Start our pool at the price the reference pool is actually trading, so the oracle mark and
        // the position agree on day zero.
        (, startTick,,,,,) = IV3PoolSlot0(V3_POOL).slot0();
        int24 center = (startTick / TICK_SPACING) * TICK_SPACING;

        poolKey = PoolKey({
            currency0: Currency.wrap(USDC),
            currency1: Currency.wrap(WETH),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        manager.initialize(poolKey, TickMath.getSqrtPriceAtTick(center));

        venue = new V4PositionVenue(
            manager,
            poolKey,
            address(vault),
            quote,
            risky,
            IQuoteOracle(address(oracle)),
            ISpotSwapper(address(swapper)),
            center - 3000,
            center + 4320,
            0.05e18
        );
        hook.setVenue(address(venue), poolKey);

        adjuster =
            deployCode("SolvencyAdjuster.sol:SolvencyAdjuster", abi.encode(address(vault), address(oracle)));
        strategy = deployCode(
            "BufferStrategy.sol:BufferStrategy",
            abi.encode(router, USDC, WETH, uint256(1e16), uint256(1e20), adjuster, uint24(30), uint64(1))
        );

        vm.prank(curator);
        vault.setVenues(
            IPositionVenue(address(venue)), IBufferStrategy(strategy), ISpotSwapper(address(swapper))
        );
    }

    /// @notice A 6-decimal quote against an 18-decimal risky asset must come back in quote units.
    function test_oracleMarksInQuoteUnits() public view {
        uint256 oneEth = oracle.valueInQuote(WETH, 1e18);
        assertGt(oneEth, 100e6, "an ETH is worth more than 100 USDC");
        assertLt(oneEth, 100_000e6, "and less than 100k, so the scale is USDC not wei");
        console2.log("1 WETH in USDC units", oneEth);
    }

    /// @notice Activation seeds through a real v3 swap and mints into the real PoolManager.
    function test_activatesAgainstMainnet() public {
        _subscribe();
        vm.warp(subEnd);
        vault.activate();

        assertTrue(vault.bufferShipped(), "shipped to Aqua");
        assertEq(vault.shippedQuote(), (J0 * SHIP_SHARE) / 1e18, "junior's configured slice");
        assertGt(venue.liquidity(), 0, "v4 position minted");

        // Seeding buys the risky leg on v3, so some value is given up. NAV should still land close
        // to the capital raised rather than an order of magnitude away, which is what a decimals
        // mistake would look like.
        uint256 nav = vault.nav();
        assertGt(nav, (S0 + J0) * 90 / 100, "nav within 10% of capital raised");
        assertLt(nav, (S0 + J0) * 110 / 100, "and not inflated");
        console2.log("capital raised ", S0 + J0);
        console2.log("nav after seed ", nav);
        console2.log("seeding cost  ", (S0 + J0) - nav);
    }

    /// @notice Coverage and the quoting policy have to be readable with a 6-decimal quote.
    function test_policyReadsOnMainnet() public {
        _subscribe();
        vm.warp(subEnd);
        vault.activate();

        assertGt(vault.coverageWad(), 0, "junior covers senior at the start");
        RiskPolicy.Quote memory q = vault.riskQuote();
        assertTrue(q.bidAllowed, "healthy coverage bids");
        assertGt(q.spreadWad, 0, "spread quoted");
    }

    function _subscribe() internal {
        deal(USDC, alice, S0);
        deal(USDC, bob, J0);
        vm.startPrank(alice);
        quote.approve(address(vault), S0);
        vault.depositSenior(S0);
        vm.stopPrank();
        vm.startPrank(bob);
        quote.approve(address(vault), J0);
        vault.depositJunior(J0);
        vm.stopPrank();
    }

    function _config() internal view returns (TrancheVault.Config memory) {
        return TrancheVault.Config({
            couponWad: 0.01e18,
            lambdaWad: 0.7e18,
            maxCouponWad: 0.015e18,
            minJuniorShareWad: 0.05e18,
            maxJuniorShareWad: 0.6e18,
            bufferShipShareWad: SHIP_SHARE,
            bufferCallCoverageWad: 0.1e18,
            minRebalanceCoverageWad: 0.2e18,
            liquidationSlippageWad: 0.01e18,
            risk: RiskPolicy.Params({
                baseSpreadWad: 0.003e18,
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
}
