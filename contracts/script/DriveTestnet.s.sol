// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {TrancheVault} from "../src/TrancheVault.sol";
import {RiskPolicy} from "../src/libraries/RiskPolicy.sol";
import {UniswapV3TwapOracle} from "../src/oracles/UniswapV3TwapOracle.sol";
import {TrancheHook} from "../src/venues/TrancheHook.sol";
import {MockERC20, MockV3Pool} from "../test/mocks/Mocks.sol";

/// @notice Steps the live testnet vault through a falling market.
/// @dev STEP=fall1|fall2|fall3|fall4|call|settle|status
contract DriveTestnet is Script {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    int24 constant SPACING = 60;
    uint32 constant TWAP = 30 minutes;
    int24 constant BASE_TICK = 198_120;

    TrancheVault vault;
    TrancheHook hook;
    MockV3Pool markPool;
    UniswapV3TwapOracle oracle;
    MockERC20 usdc;
    MockERC20 weth;
    IPoolManager manager;
    PoolKey key;

    bool riskyIsC0;
    int24 center;

    function run() external {
        string memory j = vm.readFile("./deployments/base-sepolia.json");
        vault = TrancheVault(vm.parseJsonAddress(j, ".vault"));
        hook = TrancheHook(vm.parseJsonAddress(j, ".hook"));
        markPool = MockV3Pool(vm.parseJsonAddress(j, ".markPool"));
        oracle = UniswapV3TwapOracle(vm.parseJsonAddress(j, ".oracle"));
        usdc = MockERC20(vm.parseJsonAddress(j, ".usdc"));
        weth = MockERC20(vm.parseJsonAddress(j, ".weth"));
        manager = IPoolManager(vm.envAddress("POOL_MANAGER"));

        riskyIsC0 = hook.riskyIsCurrency0();
        center = riskyIsC0 ? -((BASE_TICK / SPACING) * SPACING) : (BASE_TICK / SPACING) * SPACING;

        (address c0, address c1) = riskyIsC0
            ? (address(weth), address(usdc))
            : (address(usdc), address(weth));
        key = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: SPACING,
            hooks: IHooks(address(hook))
        });

        string memory step = vm.envString("STEP");
        bytes32 s = keccak256(bytes(step));

        if (s == keccak256("fall1")) _fall(1054, "eth -10%");
        else if (s == keccak256("fall2")) _fall(2231, "eth -20%");
        else if (s == keccak256("fall3")) _fall(3857, "eth -32%");
        else if (s == keccak256("fall4")) _fall(5978, "eth -45%");
        else if (s == keccak256("call")) _call();
        else if (s == keccak256("settle")) _settle();
        else _row("status");
    }

    function _fall(int24 delta, string memory label) internal {
        int24 target = center + (riskyIsC0 ? -delta : delta);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        markPool.setMeanTick(target, TWAP);

        PoolSwapTest router = new PoolSwapTest(manager);
        weth.mint(msg.sender, 3_000e18);
        weth.approve(address(router), type(uint256).max);
        try router.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: riskyIsC0,
                amountSpecified: -int256(3_000e18),
                sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(target)
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        ) {} catch {
            console2.log("[hook refused the risk-increasing swap]");
        }
        vm.stopBroadcast();

        _row(label);
    }

    function _call() internal {
        vm.startBroadcast(vm.envUint("CURATOR_PRIVATE_KEY"));
        vault.callBuffer();
        vm.stopBroadcast();
        console2.log("[buffer called, Aqua strategy revoked]");
        _row("buffer called");
    }

    function _settle() internal {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        if (vault.phase() == TrancheVault.Phase.Active) vault.beginSettlement();
        uint256 held = weth.balanceOf(address(vault));
        if (held != 0) vault.liquidate(held);
        vault.settle();
        vm.stopBroadcast();

        console2.log("=== settled ===");
        console2.log("nav usdc          ", vault.navAtSettlement() / 1e6);
        console2.log("senior claim usdc ", vault.seniorClaimAtSettlement() / 1e6);
        console2.log("senior pot usdc   ", vault.seniorPot() / 1e6);
        console2.log("junior pot usdc   ", vault.juniorPot() / 1e6);
        console2.log("senior return bps ", _bps(vault.seniorPot(), 700_000e6));
        console2.log("junior return bps ", _bps(vault.juniorPot(), 300_000e6));
    }

    function _row(string memory label) internal view {
        RiskPolicy.Quote memory q = vault.riskQuote();
        (, int24 t,,) = manager.getSlot0(key.toId());
        console2.log(label);
        console2.log("  eth usdc     ", oracle.valueInQuote(address(weth), 1e18) / 1e6);
        console2.log("  nav usdc     ", vault.nav() / 1e6);
        console2.log("  coverage bps ", vault.coverageWad() / 1e14);
        console2.log("  spread bps   ", q.spreadWad / 1e14);
        console2.log("  bidAllowed   ", q.bidAllowed);
        console2.log("  pool tick    ", t);
    }

    function _bps(uint256 got, uint256 put) internal pure returns (int256) {
        return (int256(got) - int256(put)) * 10_000 / int256(put);
    }
}
