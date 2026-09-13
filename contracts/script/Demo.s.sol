// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {TrancheVault} from "../src/TrancheVault.sol";
import {IAquaRegistry} from "../src/interfaces/IAquaRegistry.sol";
import {IBufferStrategy} from "../src/interfaces/IBufferStrategy.sol";
import {IPositionVenue} from "../src/interfaces/IPositionVenue.sol";
import {IQuoteOracle} from "../src/interfaces/IQuoteOracle.sol";
import {ISpotSwapper} from "../src/interfaces/ISpotSwapper.sol";
import {IVaultPolicy} from "../src/interfaces/IVaultPolicy.sol";
import {RiskPolicy} from "../src/libraries/RiskPolicy.sol";
import {IUniswapV3PoolObserver, UniswapV3TwapOracle} from "../src/oracles/UniswapV3TwapOracle.sol";
import {TrancheHook} from "../src/venues/TrancheHook.sol";
import {V4PositionVenue} from "../src/venues/V4PositionVenue.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";
import {MockV3Pool} from "../test/mocks/Mocks.sol";
import {OracleSwapper} from "./support/DemoSupport.sol";

interface IV3PoolSlot0 {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
}

/// @dev Scripts are ephemeral, so the hook is mined against this helper.
contract HookDeployer {
    function deploy(bytes32 salt, IPoolManager m, IVaultPolicy v, address admin_)
        external
        returns (address)
    {
        return address(new TrancheHook{salt: salt}(m, v, admin_));
    }
}

/// @notice One epoch on a mainnet fork: real USDC and WETH, the real v4 PoolManager, real Aqua.
/// @dev The starting price is read from the live USDC/WETH v3 pool. The fall after that is
///      simulated rather than traded through v3, which would cross thousands of real ticks.
///      Simulation only; run against a fork RPC without --broadcast.
contract Demo is Script, StdCheats {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant V3_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address constant V4_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    int24 constant SPACING = 60;
    uint32 constant TWAP = 30 minutes;
    uint256 constant S0 = 700_000e6;
    uint256 constant J0 = 300_000e6;
    uint64 constant T = 30 days;

    IPoolManager manager = IPoolManager(V4_MANAGER);
    ERC20 quote = ERC20(USDC);
    ERC20 risky = ERC20(WETH);

    MockV3Pool markPool;
    UniswapV3TwapOracle oracle;
    OracleSwapper swapper;
    TrancheVault vault;
    TrancheHook hook;
    V4PositionVenue venue;
    PoolSwapTest v4Router;
    PoolKey key;
    address strategy;

    address curator = address(0xC0);
    address alice = address(0xA1);
    address bob = address(0xB0);
    address arb = address(0xEEE);
    address admin = address(0xAD);
    uint64 subEnd;
    int24 center;

    function run() external {
        _deploy();
        _subscribe();

        vm.warp(subEnd);
        vault.activate();
        _row("activated");

        _fall(1054, "eth -10%");
        _fall(2231, "eth -20%");
        _fall(3857, "eth -32%");
        _fall(5978, "eth -45%");

        _callBufferIfBreached();
        _settleAndReport();
    }

    function _deploy() internal {
        subEnd = uint64(block.timestamp + 1 days);

        (, int24 spot,,,,,) = IV3PoolSlot0(V3_POOL).slot0();
        center = (spot / SPACING) * SPACING;

        markPool = new MockV3Pool(USDC, WETH);
        markPool.setMeanTick(center, TWAP);
        oracle = new UniswapV3TwapOracle(IUniswapV3PoolObserver(address(markPool)), USDC, WETH, TWAP);

        swapper = new OracleSwapper(IQuoteOracle(address(oracle)), USDC, WETH);
        deal(USDC, address(swapper), 5_000_000e6);
        deal(WETH, address(swapper), 5_000e18);

        v4Router = new PoolSwapTest(manager);

        address aqua = deployCode("Aqua.sol:Aqua");
        address aquaRouter = deployCode(
            "AquaSwapVMRouter.sol:AquaSwapVMRouter", abi.encode(aqua, WETH, admin, "SwapVM", "1.0.0")
        );

        vault = new TrancheVault(
            quote, risky, IQuoteOracle(address(oracle)), IAquaRegistry(aqua), curator, _config()
        );

        HookDeployer deployer = new HookDeployer();
        uint160 flags = Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG;
        bytes memory args = abi.encode(manager, IVaultPolicy(address(vault)), admin);
        (, bytes32 salt) = HookMiner.find(address(deployer), flags, type(TrancheHook).creationCode, args);
        hook = TrancheHook(deployer.deploy(salt, manager, IVaultPolicy(address(vault)), admin));

        key = PoolKey({
            currency0: Currency.wrap(USDC),
            currency1: Currency.wrap(WETH),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: SPACING,
            hooks: IHooks(address(hook))
        });
        manager.initialize(key, TickMath.getSqrtPriceAtTick(center));

        venue = new V4PositionVenue(
            manager,
            key,
            address(vault),
            quote,
            risky,
            IQuoteOracle(address(oracle)),
            ISpotSwapper(address(swapper)),
            center - 3000,
            center + 4320,
            0.05e18
        );
        vm.prank(admin);
        hook.setVenue(address(venue), key);

        address adjuster =
            deployCode("SolvencyAdjuster.sol:SolvencyAdjuster", abi.encode(address(vault), address(oracle)));
        strategy = deployCode(
            "BufferStrategy.sol:BufferStrategy",
            abi.encode(aquaRouter, USDC, WETH, uint256(1e16), uint256(1e20), adjuster, uint24(30), uint64(1))
        );

        vm.prank(curator);
        vault.setVenues(
            IPositionVenue(address(venue)), IBufferStrategy(strategy), ISpotSwapper(address(swapper))
        );

        console2.log("=== Trelp, one epoch on a mainnet fork ===");
        console2.log("senior usdc", S0 / 1e6);
        console2.log("junior usdc", J0 / 1e6);
        console2.log("");
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

    /// @dev ETH cheaper means more WETH-wei per USDC-unit, so the tick rises.
    function _fall(int24 delta, string memory label) internal {
        int24 target = center + delta;
        markPool.setMeanTick(target, TWAP);
        vm.warp(block.timestamp + 2 days);
        _pushPool(target);
        _row(label);
    }

    function _pushPool(int24 target) internal {
        deal(WETH, arb, 2_000e18);
        vm.startPrank(arb);
        risky.approve(address(v4Router), type(uint256).max);
        try v4Router.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(2_000e18),
                sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(target)
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        ) {} catch {
            console2.log("  [hook refused the risk-increasing swap]");
        }
        vm.stopPrank();
    }

    function _callBufferIfBreached() internal {
        if (!vault.bufferShipped()) return;
        if (vault.coverageWad() >= 0.1e18) return;
        vault.callBuffer();
        console2.log("");
        console2.log("  [buffer called, Aqua strategy revoked]");
        _row("buffer called");
    }

    function _settleAndReport() internal {
        (,,,, uint64 start,) = vault.terms();
        vm.warp(uint256(start) + T + 1);
        vault.beginSettlement();

        uint256 held = risky.balanceOf(address(vault));
        if (held != 0) vault.liquidate(held);
        vault.settle();

        console2.log("");
        console2.log("=== settled ===");
        console2.log("nav usdc          ", vault.navAtSettlement() / 1e6);
        console2.log("senior claim usdc ", vault.seniorClaimAtSettlement() / 1e6);
        console2.log("senior pot usdc   ", vault.seniorPot() / 1e6);
        console2.log("junior pot usdc   ", vault.juniorPot() / 1e6);
        console2.log("senior return bps ", _retBps(vault.seniorPot(), S0));
        console2.log("junior return bps ", _retBps(vault.juniorPot(), J0));
    }

    function _row(string memory label) internal view {
        RiskPolicy.Quote memory q = vault.riskQuote();
        (, int24 v4t,,) = manager.getSlot0(key.toId());
        console2.log(label);
        console2.log("  eth usdc     ", oracle.valueInQuote(WETH, 1e18) / 1e6);
        console2.log("  nav usdc     ", vault.nav() / 1e6);
        console2.log("  coverage bps ", vault.coverageWad() / 1e14);
        console2.log("  spread bps   ", q.spreadWad / 1e14);
        console2.log("  bidAllowed   ", q.bidAllowed);
        console2.log("  pool tick    ", v4t);
    }

    function _retBps(uint256 got, uint256 put) internal pure returns (int256) {
        return (int256(got) - int256(put)) * 10_000 / int256(put);
    }

    function _config() internal view returns (TrancheVault.Config memory) {
        return TrancheVault.Config({
            couponWad: 0.01e18,
            lambdaWad: 0.7e18,
            maxCouponWad: 0.015e18,
            minJuniorShareWad: 0.05e18,
            maxJuniorShareWad: 0.6e18,
            bufferShipShareWad: 0.3e18,
            bufferCallCoverageWad: 0.1e18,
            minRebalanceCoverageWad: 0.2e18,
            liquidationSlippageWad: 0.02e18,
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
