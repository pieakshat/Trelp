// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {TrancheVault} from "../src/TrancheVault.sol";
import {IAquaRegistry} from "../src/interfaces/IAquaRegistry.sol";
import {IBufferStrategy} from "../src/interfaces/IBufferStrategy.sol";
import {IPositionVenue} from "../src/interfaces/IPositionVenue.sol";
import {IQuoteOracle} from "../src/interfaces/IQuoteOracle.sol";
import {ISpotSwapper} from "../src/interfaces/ISpotSwapper.sol";
import {IVaultPolicy} from "../src/interfaces/IVaultPolicy.sol";
import {RiskPolicy} from "../src/libraries/RiskPolicy.sol";
import {TrancheHook} from "../src/venues/TrancheHook.sol";
import {V4PositionVenue} from "../src/venues/V4PositionVenue.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {MockERC20, MockOracle, MockSpotSwapper} from "./mocks/Mocks.sol";

/// @notice Both venues in one deployment: a real v4 pool and the real Aqua registry, wired to one
///         vault, activated in a single transaction.
///
/// @dev Every other suite exercises one venue and mocks the other, because v4-core pins solc
///      `0.8.26` and Aqua/SwapVM pin `0.8.30` and no file can name both. This one takes the v4 side
///      concretely and reaches Aqua through `deployCode`, which carries bytecode rather than types.
///      `activate()` ships to Aqua and mints the v4 position in the same call, so it is the only
///      place the two can fail against each other.
contract DeployStackTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant S0 = 700_000e18;
    uint256 constant J0 = 300_000e18;
    uint256 constant SHIP_SHARE = 0.3e18;
    uint64 constant T = 30 days;
    int24 constant TICK_SPACING = 60;

    // Quote sorts first, so the pool price is risky-per-quote and spot sits well below tick zero.
    int24 constant START_TICK = -76_020;
    int24 constant TICK_LOWER = -79_020;
    int24 constant TICK_UPPER = -71_700;

    PoolManager manager;
    MockERC20 quote;
    MockERC20 risky;
    MockOracle oracle;
    MockSpotSwapper swapper;

    TrancheVault vault;
    TrancheHook hook;
    V4PositionVenue venue;
    PoolKey poolKey;

    address aqua;
    address router;
    address adjuster;
    address strategy;

    address curator = address(0xC0);
    address alice = address(0xA1);
    address bob = address(0xB0);
    uint64 subEnd;

    function setUp() public {
        vm.warp(1_000_000);
        subEnd = uint64(block.timestamp + 1 days);

        manager = new PoolManager(address(this));

        MockERC20 a = new MockERC20("Quote", "USDQ", 18);
        MockERC20 b = new MockERC20("Risky", "RSK", 18);
        (quote, risky) = address(a) < address(b) ? (a, b) : (b, a);

        oracle = new MockOracle();
        oracle.setPrice(address(risky), _quotePerRisky());
        swapper = new MockSpotSwapper(oracle, quote, risky);

        // The official Aqua contracts, by artifact. Their types would drag solc 0.8.30 into a file
        // that has already committed to 0.8.26 for the hook.
        aqua = deployCode("Aqua.sol:Aqua");
        router = deployCode(
            "AquaSwapVMRouter.sol:AquaSwapVMRouter",
            abi.encode(aqua, address(0), address(this), "SwapVM", "1.0.0")
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
        hook.setVenue(address(venue), poolKey);

        adjuster =
            deployCode("SolvencyAdjuster.sol:SolvencyAdjuster", abi.encode(address(vault), address(oracle)));
        strategy = deployCode(
            "BufferStrategy.sol:BufferStrategy",
            abi.encode(router, address(quote), address(risky), uint256(1e16), uint256(1e20), adjuster, uint24(30), uint64(1))
        );

        vm.prank(curator);
        vault.setVenues(
            IPositionVenue(address(venue)), IBufferStrategy(strategy), ISpotSwapper(address(swapper))
        );
    }

    /// @notice The deployment the script produces is fully wired.
    function test_stackIsWired() public view {
        assertEq(hook.venue(), address(venue), "hook knows its venue");
        assertEq(address(vault.positionVenue()), address(venue), "vault knows the position venue");
        assertEq(address(vault.bufferStrategy()), strategy, "vault knows the buffer");
        assertEq(address(vault.swapper()), address(swapper), "vault knows the swapper");
        assertFalse(hook.riskyIsCurrency0(), "quote sorts first, so risky is currency1");
    }

    /// @notice One transaction ships junior's slice to Aqua and mints the v4 position. This is the
    ///         only call where the two venues can fail against each other.
    function test_activateReachesBothVenues() public {
        _subscribe();
        vm.warp(subEnd);
        vault.activate();

        assertTrue(vault.bufferShipped(), "shipped to Aqua");
        assertEq(vault.shippedQuote(), (J0 * SHIP_SHARE) / WAD, "shipped junior's configured slice");
        assertTrue(vault.bufferStrategyHash() != bytes32(0), "Aqua returned a strategy hash");

        assertGt(venue.liquidity(), 0, "v4 position minted");
        assertGt(venue.valueInQuote(), 0, "position marks");

        // The shipped capital never left, so it is still inside NAV rather than beside it.
        assertGe(vault.quote().balanceOf(address(vault)), vault.shippedQuote(), "buffer still held");
    }

    /// @notice Both venues read one policy, so the vault must answer while both are live.
    function test_policyIsReadableWithBothVenuesLive() public {
        _subscribe();
        vm.warp(subEnd);
        vault.activate();

        RiskPolicy.Quote memory q = vault.riskQuote();
        assertTrue(q.bidAllowed, "healthy coverage still bids");
        assertGt(q.spreadWad, 0, "spread is quoted");
        assertGt(vault.nav(), 0, "nav marks across both venues");
    }

    /// @notice The breaker revokes the Aqua strategy while the v4 position stays untouched.
    function test_bufferCallLeavesThePositionAlone() public {
        _subscribe();
        vm.warp(subEnd);
        vault.activate();

        uint128 before = venue.liquidity();
        vm.prank(curator);
        vault.callBuffer();

        assertFalse(vault.bufferShipped(), "docked");
        assertEq(vault.shippedQuote(), 0, "nothing left shipped");
        assertEq(venue.liquidity(), before, "position untouched");
    }

    function _subscribe() internal {
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
    }

    function _quotePerRisky() internal pure returns (uint256) {
        uint160 sqrtP = TickMath.getSqrtPriceAtTick(START_TICK);
        uint256 priceX96 = (uint256(sqrtP) * uint256(sqrtP)) >> 96;
        return (1e18 << 96) / priceX96;
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
