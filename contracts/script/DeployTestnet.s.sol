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
import {TrancheHook} from "../src/venues/TrancheHook.sol";
import {V4PositionVenue} from "../src/venues/V4PositionVenue.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";
import {MockERC20, MockV3Pool} from "../test/mocks/Mocks.sol";
import {OracleSwapper} from "./support/DemoSupport.sol";

/// @notice A live epoch on a public testnet, on a compressed clock so the whole lifecycle fits a demo.
///
/// @dev Tokens are minted here rather than bridged, and the mark is settable, because a testnet has
///      no deep pool to price against and no way to move one. Everything else is the real thing:
///      the v4 PoolManager, our pool and hook, the position, and Aqua.
contract DeployTestnet is Script {
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    int24 constant SPACING = 60;
    uint32 constant TWAP = 30 minutes;

    int24 constant START_TICK = 198_120;

    /// @dev A seed only. Real deposits during the window move `j`, and the split follows.
    uint256 s0;
    uint256 j0;

    MockERC20 usdc;
    MockERC20 weth;
    MockV3Pool markPool;
    UniswapV3TwapOracle oracle;
    OracleSwapper swapper;
    TrancheVault vault;
    TrancheHook hook;
    V4PositionVenue venue;
    PoolKey key;
    address aqua;
    address aquaRouter;
    address adjuster;
    address strategy;

    IPoolManager manager;
    address deployer;
    address curator;
    int24 center;

    function run() external {
        manager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        uint256 pk = vm.envUint("PRIVATE_KEY");
        uint256 ck = vm.envUint("CURATOR_PRIVATE_KEY");
        deployer = vm.addr(pk);
        curator = vm.addr(ck);
        s0 = vm.envOr("SEED_SENIOR", uint256(100_000e6));
        j0 = vm.envOr("SEED_JUNIOR", uint256(40_000e6));

        vm.startBroadcast(pk);
        _tokens();
        _pricing();
        _vault();
        _poolAndHook();
        _venue();
        _buffer();
        usdc.approve(address(vault), s0);
        vault.depositSenior(s0);
        vm.stopBroadcast();

        vm.startBroadcast(ck);
        vault.setVenues(
            IPositionVenue(address(venue)), IBufferStrategy(strategy), ISpotSwapper(address(swapper))
        );
        usdc.approve(address(vault), j0);
        vault.depositJunior(j0);
        vm.stopBroadcast();

        _write();
    }

    function _tokens() internal {
        usdc = new MockERC20("Trelp USD", "tUSDC", 6);
        weth = new MockERC20("Trelp Ether", "tWETH", 18);
        usdc.mint(deployer, s0);
        usdc.mint(curator, j0);
    }

    function _pricing() internal {
        // The tick is signed by token ordering, which CREATE does not let us choose.
        center = (START_TICK / SPACING) * SPACING;
        if (address(weth) < address(usdc)) center = -center;

        markPool = new MockV3Pool(address(usdc), address(weth));
        markPool.setMeanTick(center, TWAP);
        oracle = new UniswapV3TwapOracle(
            IUniswapV3PoolObserver(address(markPool)), address(usdc), address(weth), TWAP
        );

        swapper = new OracleSwapper(IQuoteOracle(address(oracle)), address(usdc), address(weth));
        usdc.mint(address(swapper), 20_000_000e6);
        weth.mint(address(swapper), 20_000e18);
    }

    function _vault() internal {
        aqua = deployCode("Aqua.sol:Aqua");
        aquaRouter = deployCode(
            "AquaSwapVMRouter.sol:AquaSwapVMRouter",
            abi.encode(aqua, address(weth), deployer, "SwapVM", "1.0.0")
        );
        vault = new TrancheVault(
            ERC20(address(usdc)),
            ERC20(address(weth)),
            IQuoteOracle(address(oracle)),
            IAquaRegistry(aqua),
            curator,
            _config()
        );
    }

    function _poolAndHook() internal {
        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);
        bytes memory args = abi.encode(manager, IVaultPolicy(address(vault)), deployer);
        (address expected, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(TrancheHook).creationCode, args);
        hook = new TrancheHook{salt: salt}(manager, IVaultPolicy(address(vault)), deployer);
        require(address(hook) == expected, "hook address");

        (address c0, address c1) = address(usdc) < address(weth)
            ? (address(usdc), address(weth))
            : (address(weth), address(usdc));
        key = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: SPACING,
            hooks: IHooks(address(hook))
        });
        manager.initialize(key, TickMath.getSqrtPriceAtTick(center));
    }

    /// @dev The exposed bound is the one the position converts to risky at, which flips with ordering.
    function _venue() internal {
        bool riskyIsC0 = address(weth) < address(usdc);
        int24 lower = riskyIsC0 ? center - 4320 : center - 3000;
        int24 upper = riskyIsC0 ? center + 3000 : center + 4320;

        venue = new V4PositionVenue(
            manager,
            key,
            address(vault),
            ERC20(address(usdc)),
            ERC20(address(weth)),
            IQuoteOracle(address(oracle)),
            ISpotSwapper(address(swapper)),
            lower,
            upper,
            0.05e18
        );
        hook.setVenue(address(venue), key);
    }

    function _buffer() internal {
        adjuster =
            deployCode("SolvencyAdjuster.sol:SolvencyAdjuster", abi.encode(address(vault), address(oracle)));
        strategy = deployCode(
            "BufferStrategy.sol:BufferStrategy",
            abi.encode(
                aquaRouter,
                address(usdc),
                address(weth),
                uint256(1e16),
                uint256(1e20),
                adjuster,
                uint24(30),
                uint64(block.timestamp)
            )
        );
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
            subscriptionEnd: uint64(block.timestamp + vm.envOr("SUBSCRIPTION_SECONDS", uint256(3 hours))),
            epochDuration: uint64(vm.envOr("EPOCH_SECONDS", uint256(2 hours))),
            activationGrace: 10 minutes,
            unwindWindow: 30 minutes,
            rebalanceCooldown: 5 minutes
        });
    }

    function _write() internal {
        string memory o = "deployment";
        vm.serializeAddress(o, "vault", address(vault));
        vm.serializeAddress(o, "senior", address(vault.senior()));
        vm.serializeAddress(o, "junior", address(vault.junior()));
        vm.serializeAddress(o, "usdc", address(usdc));
        vm.serializeAddress(o, "weth", address(weth));
        vm.serializeAddress(o, "oracle", address(oracle));
        vm.serializeAddress(o, "markPool", address(markPool));
        vm.serializeAddress(o, "swapper", address(swapper));
        vm.serializeAddress(o, "hook", address(hook));
        vm.serializeAddress(o, "positionVenue", address(venue));
        vm.serializeAddress(o, "bufferStrategy", strategy);
        vm.serializeAddress(o, "aqua", aqua);
        vm.serializeAddress(o, "curator", curator);
        string memory out = vm.serializeUint(o, "chainId", block.chainid);
        vm.writeJson(out, "./deployments/base-sepolia.json");

        console2.log("vault    ", address(vault));
        console2.log("usdc     ", address(usdc));
        console2.log("weth     ", address(weth));
        console2.log("hook     ", address(hook));
        console2.log("markPool ", address(markPool));
    }
}
