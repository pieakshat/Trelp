// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {Aqua} from "@1inch/aqua/src/Aqua.sol";
import {ISwapVM} from "@1inch/swap-vm/src/interfaces/ISwapVM.sol";
import {SwapVM} from "@1inch/swap-vm/src/SwapVM.sol";
import {AquaSwapVMRouter} from "@1inch/swap-vm/src/routers/AquaSwapVMRouter.sol";
import {TakerTraitsLib} from "@1inch/swap-vm/src/libs/TakerTraits.sol";
import {MockTaker} from "@1inch/swap-vm/test/mocks/MockTaker.sol";

import {TrancheVault} from "../src/TrancheVault.sol";
import {BufferStrategy} from "../src/aqua/BufferStrategy.sol";
import {SolvencyAdjuster} from "../src/aqua/SolvencyAdjuster.sol";
import {IAquaRegistry} from "../src/interfaces/IAquaRegistry.sol";
import {IBufferStrategy} from "../src/interfaces/IBufferStrategy.sol";
import {IPositionVenue} from "../src/interfaces/IPositionVenue.sol";
import {IQuoteOracle} from "../src/interfaces/IQuoteOracle.sol";
import {IVaultPolicy} from "../src/interfaces/IVaultPolicy.sol";
import {RiskPolicy} from "../src/libraries/RiskPolicy.sol";
import {ISpotSwapper} from "../src/interfaces/ISpotSwapper.sol";
import {MockERC20, MockOracle, MockPositionVenue, MockSpotSwapper} from "./mocks/Mocks.sol";

/// @notice The five demo paths. Same vault, same parameters, five price and flow scenarios.
///
/// @dev Runs on the Aqua leg with a mock position venue. That is deliberate: these paths are about
///      the waterfall and the solvency policy, not about pool mechanics, and mixing in a v4 type
///      would be impossible anyway — v4-core pins solc `0.8.26` and Aqua/SwapVM pin `0.8.30`.
///
///      The position is marked from the price the way a full-range LP actually behaves, `√k`, so
///      the drawdown numbers mean what the term sheet says they mean.
contract DemoPathsTest is Test {
    using FixedPointMathLib for uint256;

    uint256 constant WAD = 1e18;
    uint256 constant V0 = 1_000_000e18;
    uint256 constant S0 = 700_000e18;
    uint256 constant J0 = 300_000e18;
    uint256 constant START_PRICE = 2000e18;
    uint64 constant T = 30 days;

    Aqua aqua;
    SwapVM router;
    MockTaker taker;
    MockERC20 quote;
    MockERC20 risky;
    MockOracle oracle;

    MockPositionVenue position;
    TrancheVault vault;
    BufferStrategy strategy;
    SolvencyAdjuster adjuster;
    MockSpotSwapper swapper;

    address curator = address(0xC0);
    address alice = address(0xA1);
    address bob = address(0xB0);
    uint64 subEnd;
    uint256 deployedToPosition;

    struct Outcome {
        uint256 nav;
        uint256 seniorPayout;
        uint256 juniorPayout;
        int256 seniorReturnWad;
        int256 juniorReturnWad;
        uint256 riskyConverted;
    }

    function setUp() public {
        vm.warp(1_000_000);
        subEnd = uint64(block.timestamp + 1 days);

        aqua = new Aqua();
        router = new AquaSwapVMRouter(address(aqua), address(0), address(this), "SwapVM", "1.0.0");
        taker = new MockTaker(aqua, router, address(this));

        MockERC20 a = new MockERC20("Quote", "USDQ", 18);
        MockERC20 b = new MockERC20("Risky", "RSK", 18);
        (quote, risky) = address(a) < address(b) ? (a, b) : (b, a);

        oracle = new MockOracle();
        oracle.setPrice(address(risky), START_PRICE);
        swapper = new MockSpotSwapper(oracle, quote, risky);
    }

    // ---------------------------------------------------------------- harness

    function _build(bool policyOn, uint256 bufferShareWad, uint64 salt) internal {
        subEnd = uint64(block.timestamp + 1 days);
        TrancheVault.Config memory cfg = TrancheVault.Config({
            couponWad: 0.01e18,
            lambdaWad: 0.7e18,
            maxCouponWad: 0.015e18,
            minJuniorShareWad: 0.05e18,
            maxJuniorShareWad: 0.6e18,
            bufferShipShareWad: bufferShareWad,
            bufferCallCoverageWad: 0.1e18,
            minRebalanceCoverageWad: 0.2e18,
            liquidationSlippageWad: 0.01e18,
            risk: RiskPolicy.Params({
                baseSpreadWad: 0.003e18,
                alphaWad: 2e18,
                kappaWad: 0.5e18,
                targetCoverageWad: 0.428571428571428571e18,
                bidCutoffWad: 0.9e18,
                maxInventoryWad: 0.6e18
            }),
            subscriptionEnd: subEnd,
            epochDuration: T,
            activationGrace: 1 days,
            unwindWindow: 1 days,
            rebalanceCooldown: 6 hours
        });

        vault = new TrancheVault(
            quote, risky, IQuoteOracle(address(oracle)), IAquaRegistry(address(aqua)), curator, cfg
        );
        position = new MockPositionVenue(quote, address(vault));
        adjuster = new SolvencyAdjuster(IVaultPolicy(address(vault)), IQuoteOracle(address(oracle)));

        // Path 4 is this one line: the same vault with no coverage-aware pricing on the buffer.
        strategy = new BufferStrategy(
            address(router),
            address(quote),
            address(risky),
            1e16,
            1e20,
            policyOn ? address(adjuster) : address(0),
            30,
            salt
        );

        vm.prank(curator);
        vault.setVenues(
            IPositionVenue(address(position)),
            IBufferStrategy(address(strategy)),
            ISpotSwapper(address(swapper))
        );

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
        deployedToPosition = position.valueInQuote();
    }

    function _order() internal returns (ISwapVM.Order memory order) {
        // Read first: `vm.prank` applies to the next call, and passing `vault.shippedQuote()`
        // inline would consume it, leaving the test contract as the maker and producing a
        // strategy hash Aqua has never seen.
        uint256 shipped = vault.shippedQuote();
        vm.prank(address(vault));
        (, bytes memory encoded,,) = strategy.shipParams(shipped);
        order = abi.decode(encoded, (ISwapVM.Order));
        require(keccak256(encoded) == vault.bufferStrategyHash(), "rebuilt order must match the shipped one");
    }

    function _takerData() internal view returns (bytes memory) {
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(taker),
                isExactIn: true,
                shouldUnwrapWeth: false,
                hasPreTransferInCallback: true,
                hasPreTransferOutCallback: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: false,
                isAToB: address(risky) < address(quote),
                allowPartialFill: true,
                threshold: "",
                to: address(0),
                deadline: 0,
                preTransferInHookData: "",
                postTransferInHookData: "",
                preTransferOutHookData: "",
                postTransferOutHookData: "",
                preTransferInCallbackData: "",
                preTransferOutCallbackData: "",
                instructionsArgs: "",
                signature: ""
            })
        );
    }

    /// @dev Mark the position the way a full-range LP behaves: value scales with `√k`.
    function _setPrice(uint256 kWad) internal {
        oracle.setPrice(address(risky), (START_PRICE * kWad) / WAD);
        position.setValue((deployedToPosition * (kWad * WAD).sqrt()) / WAD);
    }

    /// @dev One taker hitting the buffer's bid. Returns false when the policy refused the fill.
    function _sellIntoBuffer(ISwapVM.Order memory order, uint256 amount) internal returns (bool) {
        risky.mint(address(taker), amount);
        try taker.swap(order, amount, _takerData()) {
            return true;
        } catch {
            return false; // the policy declined this fill
        }
    }

    function _settle() internal returns (Outcome memory o) {
        vm.warp(subEnd + T);
        o.riskyConverted = risky.balanceOf(address(vault));

        vault.beginSettlement();
        uint256 bal = risky.balanceOf(address(vault));
        if (bal != 0) vault.liquidate(bal);
        vault.settle();

        o.nav = vault.navAtSettlement();
        o.seniorPayout = vault.seniorPot();
        o.juniorPayout = vault.juniorPot();
        o.seniorReturnWad = int256((o.seniorPayout * WAD) / S0) - int256(WAD);
        o.juniorReturnWad = int256((o.juniorPayout * WAD) / J0) - int256(WAD);
    }

    function _report(string memory label, Outcome memory o) internal {
        emit log("");
        emit log(label);
        emit log_named_decimal_uint("  NAV at settlement", o.nav, 18);
        emit log_named_decimal_uint("  senior payout   ", o.seniorPayout, 18);
        emit log_named_decimal_uint("  junior payout   ", o.juniorPayout, 18);
        emit log_named_decimal_int("  senior return   ", o.seniorReturnWad, 16);
        emit log_named_decimal_int("  junior return   ", o.juniorReturnWad, 16);
        emit log_named_decimal_uint("  risky converted ", o.riskyConverted, 18);
    }

    // ---------------------------------------------------------------- the five paths

    /// @notice PATH 1 — flat price, normal volume. The leverage working.
    function test_path1_flatPriceNormalVolume() public {
        _build(true, 0, 1);
        position.setValue(deployedToPosition + (V0 * 12) / 100); // f = 12%

        Outcome memory o = _settle();
        _report("PATH 1  flat price, f = 12%", o);

        assertApproxEqRel(uint256(o.seniorReturnWad), 0.01e18, 1e15, "senior +1%");
        assertApproxEqRel(uint256(o.juniorReturnWad), 0.3766e18, 1e15, "junior +37.7%");
        emit log_named_decimal_uint("  unlevered LP would be", 0.12e18, 16);
    }

    /// @notice PATH 2 — slow grind down. The mechanism working: spread widens as `b` falls.
    function test_path2_slowGrindDown() public {
        _build(true, WAD, 2);
        emit log("");
        emit log("=== PATH 2  slow grind to -40%, spread vs coverage");

        uint256[5] memory ks = [uint256(1e18), 0.9e18, 0.8e18, 0.7e18, 0.6e18];
        uint256 firstSpread;
        uint256 lastSpread;
        for (uint256 i; i < ks.length; ++i) {
            _setPrice(ks[i]);
            RiskPolicy.Quote memory q = vault.riskQuote();
            emit log_named_decimal_uint("  k     ", ks[i], 16);
            emit log_named_decimal_int("  b     ", vault.coverageWad(), 16);
            emit log_named_decimal_uint("  spread", q.spreadWad, 16);
            if (i == 0) firstSpread = q.spreadWad;
            lastSpread = q.spreadWad;
        }
        assertGt(lastSpread, firstSpread, "spread widened as the buffer thinned");

        Outcome memory o = _settle();
        _report("PATH 2  settled at -40%", o);
        assertGt(o.seniorPayout, 0);
    }

    /// @notice PATHS 3 and 4 — the same crash, with and without coverage-aware pricing.
    /// @dev Run side by side, this pairing is the entire pitch. The only difference is whether the
    ///      buffer's bid is priced off the vault's coverage. Without it the vault keeps buying the
    ///      falling asset all the way down; with it the bid widens and then refuses.
    ///
    ///      NOTE ON THE ABSOLUTE NUMBERS. The buffer is not yet oracle-anchored — its curve prices
    ///      off the concentrated range alone, so fills land at prices unrelated to the mark and
    ///      conversion is far lossier than the term sheet assumes. `OraclePriceAdjuster` closes
    ///      that. Until it does, the honest claim is the *difference* between these two runs, not
    ///      the level of either.
    function test_path3and4_crashWithAndWithoutPolicy() public {
        (Outcome memory withPolicy, uint256 fillsOn) = _crash(true, 3);
        _report("PATH 3  -60% crash, policy ON", withPolicy);
        emit log_named_uint("  fills accepted (of 5)", fillsOn);

        (Outcome memory without, uint256 fillsOff) = _crash(false, 4);
        _report("PATH 4  -60% crash, policy OFF", without);
        emit log_named_uint("  fills accepted (of 5)", fillsOff);

        emit log("");
        emit log("=== 3 vs 4  the pitch");
        emit log_named_decimal_int("  senior WITH policy   ", withPolicy.seniorReturnWad, 16);
        emit log_named_decimal_int("  senior WITHOUT policy", without.seniorReturnWad, 16);

        assertLt(fillsOn, fillsOff, "the policy refused fills the unguarded buffer accepted");
        assertLt(withPolicy.riskyConverted, without.riskyConverted, "and converted less capital");
        assertGt(withPolicy.seniorPayout, without.seniorPayout, "so senior ends up better off");
    }

    function _crash(bool policyOn, uint64 salt) internal returns (Outcome memory, uint256 filled) {
        _build(policyOn, WAD, salt);
        ISwapVM.Order memory order = _order();

        uint256[5] memory ks = [uint256(0.9e18), 0.8e18, 0.7e18, 0.5e18, 0.4e18];
        for (uint256 i; i < ks.length; ++i) {
            _setPrice(ks[i]);
            if (_sellIntoBuffer(order, 20e18)) filled++;
        }
        return (_settle(), filled);
    }

    /// @notice PATH 5 — the frontier. Same crash, three buffer placements.
    /// @dev What senior protection costs in junior return, priced rather than asserted. Split into
    ///      three tests rather than a loop so each placement gets a clean vault and clean clock.
    function _frontier(string memory label, uint256 shareWad, uint64 salt) internal {
        _build(true, shareWad, salt);
        _setPrice(0.4e18);
        Outcome memory o = _settle();
        emit log("");
        emit log(label);
        emit log_named_decimal_int("     senior", o.seniorReturnWad, 16);
        emit log_named_decimal_int("     junior", o.juniorReturnWad, 16);
        emit log_named_decimal_uint("     NAV   ", o.nav, 18);
    }

    function test_path5a_bufferFullyInThePool() public {
        _frontier("PATH 5a  0% out (buffer sits in the pool)", 0, 20);
    }

    function test_path5b_bufferHalfOut() public {
        _frontier("PATH 5b  50% out", WAD / 2, 21);
    }

    function test_path5c_bufferFullyOut() public {
        _frontier("PATH 5c  100% out (all callable)", WAD, 22);
    }
}
