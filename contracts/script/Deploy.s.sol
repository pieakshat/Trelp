// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
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
import {V3SpotSwapper, IUniswapV3SwapRouter} from "../src/swappers/V3SpotSwapper.sol";
import {TrancheHook} from "../src/venues/TrancheHook.sol";
import {V4PositionVenue} from "../src/venues/V4PositionVenue.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";

/// @notice Deploys one epoch: oracle, swapper, vault, pool, hook, position venue, Aqua buffer.
///
/// @dev The Aqua contracts are loaded by artifact rather than imported. `TrancheHook` reaches
///      v4-core's `Hooks`, which pins solc 0.8.26, while SwapVM pins 0.8.30, so no single file can
///      name both. `deployCode` crosses that boundary because it carries bytecode, not types.
///
///      Ordering is forced twice over. The hook's address encodes its own permissions, so it is
///      mined against constructor arguments that include the vault, which therefore exists first.
///      The venue needs a `PoolKey` naming the hook, so the hook learns its venue afterwards.
///
///      Run:
///        forge script script/Deploy.s.sol:Deploy --rpc-url $RPC --broadcast
contract Deploy is Script {
    /// @dev Forge routes salted creates through this proxy under `--broadcast`, so the hook must be
    ///      mined against it and not against the sender.
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    uint160 constant HOOK_FLAGS = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);

    // External venues.
    IPoolManager poolManager;
    address aquaRegistry;
    address swapVmRouter;
    address v3OraclePool;
    address v3SwapRouter;

    address quote;
    address risky;
    address deployer;
    address curator;

    // Deployed.
    UniswapV3TwapOracle oracle;
    V3SpotSwapper swapper;
    TrancheVault vault;
    TrancheHook hook;
    V4PositionVenue venue;
    address adjuster;
    address strategy;
    PoolKey poolKey;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(pk);

        poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        aquaRegistry = vm.envAddress("AQUA_REGISTRY");
        swapVmRouter = vm.envAddress("SWAPVM_ROUTER");
        v3OraclePool = vm.envAddress("V3_ORACLE_POOL");
        v3SwapRouter = vm.envAddress("V3_SWAP_ROUTER");
        quote = vm.envAddress("QUOTE");
        risky = vm.envAddress("RISKY");
        curator = vm.envOr("CURATOR", deployer);

        vm.startBroadcast(pk);
        _deployPricing();
        _deployVault();
        _deployPoolAndHook();
        _deployVenue();
        _deployBuffer();
        _wire();
        vm.stopBroadcast();

        _report();
    }

    function _deployPricing() internal {
        oracle = new UniswapV3TwapOracle(
            IUniswapV3PoolObserver(v3OraclePool),
            quote,
            risky,
            uint32(vm.envOr("TWAP_WINDOW", uint256(30 minutes)))
        );
        swapper = new V3SpotSwapper(
            IUniswapV3SwapRouter(v3SwapRouter),
            quote,
            risky,
            uint24(vm.envOr("V3_FEE_TIER", uint256(3000)))
        );
    }

    function _deployVault() internal {
        vault = new TrancheVault(
            ERC20(quote),
            ERC20(risky),
            IQuoteOracle(address(oracle)),
            IAquaRegistry(aquaRegistry),
            curator,
            _config()
        );
    }

    /// @dev The pool is ours rather than an existing one: the hook gates liquidity to the vault's
    ///      venue, which only holds on a pool initialised with this hook in its key. It must also
    ///      carry the dynamic fee flag, or the hook's fee override is ignored.
    function _deployPoolAndHook() internal {
        bytes memory args = abi.encode(poolManager, IVaultPolicy(address(vault)), deployer);
        (address expected, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, HOOK_FLAGS, type(TrancheHook).creationCode, args);

        hook = new TrancheHook{salt: salt}(poolManager, IVaultPolicy(address(vault)), deployer);
        require(address(hook) == expected, "hook address mismatch");

        (address c0, address c1) = quote < risky ? (quote, risky) : (risky, quote);
        poolKey = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(vm.envOr("TICK_SPACING", int256(60))),
            hooks: IHooks(address(hook))
        });

        poolManager.initialize(poolKey, TickMath.getSqrtPriceAtTick(int24(vm.envInt("START_TICK"))));
    }

    function _deployVenue() internal {
        venue = new V4PositionVenue(
            poolManager,
            poolKey,
            address(vault),
            ERC20(quote),
            ERC20(risky),
            IQuoteOracle(address(oracle)),
            ISpotSwapper(address(swapper)),
            int24(vm.envInt("TICK_LOWER")),
            int24(vm.envInt("TICK_UPPER")),
            vm.envOr("FLOOR_MARGIN_WAD", uint256(0.05e18))
        );
        hook.setVenue(address(venue), poolKey);
    }

    /// @dev Artifact names, not types. See the note on this contract for why.
    function _deployBuffer() internal {
        adjuster = deployCode(
            "SolvencyAdjuster.sol:SolvencyAdjuster", abi.encode(address(vault), address(oracle))
        );
        strategy = deployCode(
            "BufferStrategy.sol:BufferStrategy",
            abi.encode(
                swapVmRouter,
                quote,
                risky,
                vm.envUint("BUFFER_SQRT_MIN"),
                vm.envUint("BUFFER_SQRT_MAX"),
                adjuster,
                uint24(vm.envOr("BUFFER_FEE_BPS", uint256(0))),
                uint64(vm.envOr("BUFFER_SALT", uint256(1)))
            )
        );
    }

    /// @dev `setVenues` is curator-gated. A deployment that hands the role to someone else stops
    ///      here and leaves them the one call.
    function _wire() internal {
        if (curator != deployer) return;
        vault.setVenues(
            IPositionVenue(address(venue)),
            IBufferStrategy(strategy),
            ISpotSwapper(address(swapper))
        );
    }

    function _config() internal view returns (TrancheVault.Config memory) {
        return TrancheVault.Config({
            couponWad: vm.envOr("COUPON_WAD", uint256(0.01e18)),
            lambdaWad: vm.envOr("LAMBDA_WAD", uint256(0.7e18)),
            maxCouponWad: vm.envOr("MAX_COUPON_WAD", uint256(0.015e18)),
            minJuniorShareWad: 0.05e18,
            maxJuniorShareWad: 0.6e18,
            bufferShipShareWad: vm.envOr("BUFFER_SHIP_SHARE_WAD", uint256(0.3e18)),
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
            subscriptionEnd: uint64(block.timestamp + vm.envOr("SUBSCRIPTION_SECONDS", uint256(1 days))),
            epochDuration: uint64(vm.envOr("EPOCH_SECONDS", uint256(30 days))),
            activationGrace: 1 days,
            unwindWindow: 1 days,
            rebalanceCooldown: 6 hours
        });
    }

    function _report() internal view {
        console2.log("vault           ", address(vault));
        console2.log("  senior        ", address(vault.senior()));
        console2.log("  junior        ", address(vault.junior()));
        console2.log("oracle          ", address(oracle));
        console2.log("swapper         ", address(swapper));
        console2.log("hook            ", address(hook));
        console2.log("positionVenue   ", address(venue));
        console2.log("solvencyAdjuster", adjuster);
        console2.log("bufferStrategy  ", strategy);
        console2.log("curator         ", curator);
        if (curator != deployer) {
            console2.log("NOTE: curator must call setVenues(positionVenue, bufferStrategy, swapper)");
        }
    }
}
