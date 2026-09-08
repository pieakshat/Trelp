// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Aqua} from "@1inch/aqua/src/Aqua.sol";
import {ISwapVM} from "@1inch/swap-vm/src/interfaces/ISwapVM.sol";
import {SwapVM} from "@1inch/swap-vm/src/SwapVM.sol";
import {AquaSwapVMRouter} from "@1inch/swap-vm/src/routers/AquaSwapVMRouter.sol";
import {TakerTraitsLib} from "@1inch/swap-vm/src/libs/TakerTraits.sol";
import {MockTaker} from "@1inch/swap-vm/test/mocks/MockTaker.sol";

import {TrancheVault} from "../src/TrancheVault.sol";
import {BufferStrategy} from "../src/aqua/BufferStrategy.sol";
import {SolvencyAdjuster} from "../src/aqua/SolvencyAdjuster.sol";
import {IVaultPolicy} from "../src/interfaces/IVaultPolicy.sol";
import {IAquaRegistry} from "../src/interfaces/IAquaRegistry.sol";
import {IBufferStrategy} from "../src/interfaces/IBufferStrategy.sol";
import {IPositionVenue} from "../src/interfaces/IPositionVenue.sol";
import {IQuoteOracle} from "../src/interfaces/IQuoteOracle.sol";
import {RiskPolicy} from "../src/libraries/RiskPolicy.sol";
import {ISpotSwapper} from "../src/interfaces/ISpotSwapper.sol";
import {MockERC20, MockOracle, MockPositionVenue, MockSpotSwapper} from "./mocks/Mocks.sol";

/// @notice The Day 3 gate: the vault ships the junior buffer to the **official** Aqua registry and
///         SwapVM router, a taker fills against it with real onchain token transfers, and the call
///         revokes it in one transaction.
///
/// @dev Deliberately imports no Uniswap v4 type. v4-core pins solc `0.8.26` and Aqua/SwapVM pin
///      `0.8.30`, so no single file can name both venues concretely. A combined end-to-end run has
///      to reach the v4 venue through `deployCode` against its artifact.
contract AquaBufferTest is Test {
    uint256 constant WAD = 1e18;
    uint256 constant V0 = 1_000_000e18;
    uint256 constant S0 = 700_000e18;
    uint256 constant J0 = 300_000e18;
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

    function setUp() public {
        vm.warp(1_000_000);
        subEnd = uint64(block.timestamp + 1 days);

        // Official contracts, deployed unmodified.
        aqua = new Aqua();
        router = new AquaSwapVMRouter(address(aqua), address(0), address(this), "SwapVM", "1.0.0");
        taker = new MockTaker(aqua, router, address(this));

        MockERC20 a = new MockERC20("Quote", "USDQ", 18);
        MockERC20 b = new MockERC20("Risky", "RSK", 18);
        (quote, risky) = address(a) < address(b) ? (a, b) : (b, a);

        oracle = new MockOracle();
        oracle.setPrice(address(risky), 2000e18);

        vault = new TrancheVault(
            quote, risky, IQuoteOracle(address(oracle)), IAquaRegistry(address(aqua)), curator, _config()
        );
        position = new MockPositionVenue(quote, address(vault));

        // A wide band around spot: enough that the demo fills, tight enough to be a real curve.
        adjuster = new SolvencyAdjuster(IVaultPolicy(address(vault)), IQuoteOracle(address(oracle)));
        strategy = new BufferStrategy(
            address(router), address(quote), address(risky), 1e16, 1e20, address(adjuster), 30, 1
        );

        swapper = new MockSpotSwapper(oracle, quote, risky);
        vm.prank(curator);
        vault.setVenues(
            IPositionVenue(address(position)),
            IBufferStrategy(address(strategy)),
            ISpotSwapper(address(swapper))
        );
    }

    function _config() internal view returns (TrancheVault.Config memory) {
        return TrancheVault.Config({
            couponWad: 0.01e18,
            lambdaWad: 0.7e18,
            maxCouponWad: 0.015e18,
            minJuniorShareWad: 0.05e18,
            maxJuniorShareWad: 0.6e18,
            bufferShipShareWad: WAD, // ship the whole junior buffer
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

    /// @dev Rebuilds the order exactly as the vault shipped it, so the hash matches.
    function _order() internal returns (ISwapVM.Order memory order) {
        vm.prank(address(vault));
        (, bytes memory encoded,,) = strategy.shipParams(J0);
        order = abi.decode(encoded, (ISwapVM.Order));
    }

    function _takerData(bool isAToB) internal view returns (bytes memory) {
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
                isAToB: isAToB,
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

    // ---------------------------------------------------------------- the gate

    /// @notice Shipping is a permission, not a transfer. This is the property the whole §8 argument
    ///         rests on: the buffer stays inside the vault and is therefore already in `nav()`.
    function test_shippingMovesNoTokensAndDoesNotDoubleCountNav() public {
        uint256 navBefore;
        _activate();
        navBefore = vault.nav();

        assertTrue(vault.bufferShipped(), "strategy shipped");
        assertEq(vault.shippedQuote(), J0, "junior buffer allocated");
        assertEq(quote.balanceOf(address(vault)), J0, "capital never left the vault");
        assertEq(quote.balanceOf(address(aqua)), 0, "Aqua holds nothing, ever");

        (uint256 recorded,) = aqua.rawBalances(address(vault), address(router), vault.bufferStrategyHash(), address(quote));
        assertEq(recorded, J0, "Aqua recorded the virtual balance");

        assertEq(navBefore, V0, "NAV counts the buffer once, from the vault's own balance");
    }

    /// @notice A real fill: the taker sells the risky asset to the buffer and Aqua pulls quote out
    ///         of the vault's wallet. Onchain token transfers through the official contracts.
    function test_takerFillsAgainstTheBufferWithRealTransfers() public {
        _activate();
        ISwapVM.Order memory order = _order();

        uint256 sell = 10e18;
        risky.mint(address(taker), sell);

        uint256 vaultQuoteBefore = quote.balanceOf(address(vault));
        uint256 takerQuoteBefore = quote.balanceOf(address(taker));

        bool isAToB = address(risky) < address(quote); // selling risky: is risky tokenA?
        (uint256 amountIn, uint256 amountOut) = taker.swap(order, sell, _takerData(isAToB));

        assertEq(amountIn, sell, "taker sold the risky asset");
        assertGt(amountOut, 0, "buffer paid quote for it");

        assertEq(risky.balanceOf(address(vault)), sell, "vault took the risky inventory");
        assertEq(quote.balanceOf(address(vault)), vaultQuoteBefore - amountOut, "vault paid quote");
        assertEq(quote.balanceOf(address(taker)), takerQuoteBefore + amountOut, "taker was paid");
        assertEq(quote.balanceOf(address(aqua)), 0, "Aqua still holds nothing");
    }

    /// @notice The buffer only bids. Nobody can buy the risky asset out of it, because the risky
    ///         side opens empty and `XYCConcentrateSwap` clamps payout to the real balance.
    function test_bufferCannotBeDrainedOfTheRiskyAssetItDoesNotHold() public {
        _activate();
        ISwapVM.Order memory order = _order();

        quote.mint(address(taker), 10_000e18);
        bool isAToB = address(quote) < address(risky);
        vm.expectRevert();
        taker.swap(order, 10_000e18, _takerData(isAToB));
    }

    /// @notice The call. One transaction, no capital movement, and the strategy stops quoting.
    function test_callBufferRevokesTheStrategyInOneTransaction() public {
        _activate();
        ISwapVM.Order memory order = _order();

        // Drive coverage under the threshold so the call is permissionless.
        // 300k buffer sits in the vault, so the position must fall below 470k for b < 10%
        position.setValue(450_000e18);
        assertLt(vault.coverageWad(), int256(0.1e18));

        uint256 navBefore = vault.nav();
        uint256 vaultQuoteBefore = quote.balanceOf(address(vault));

        vm.prank(alice);
        vault.callBuffer();

        assertFalse(vault.bufferShipped(), "docked");
        assertEq(vault.shippedQuote(), 0);
        assertEq(quote.balanceOf(address(vault)), vaultQuoteBefore, "docking moves no capital");
        assertEq(vault.nav(), navBefore, "so NAV is unchanged");

        (uint256 recorded,) = aqua.rawBalances(address(vault), address(router), vault.bufferStrategyHash(), address(quote));
        assertEq(recorded, 0, "Aqua balance cleared");

        // And the buffer stops quoting.
        risky.mint(address(taker), 1e18);
        vm.expectRevert();
        taker.swap(order, 1e18, _takerData(address(risky) < address(quote)));
    }

    /// @notice Settlement docks the buffer on its way out.
    function test_settlementDocksTheBuffer() public {
        _activate();
        vm.warp(subEnd + T);
        vault.beginSettlement();
        assertFalse(vault.bufferShipped(), "docked at settlement");
    }

    // ---------------------------------------------------------------- the Extruction target

    /// @dev Quotes through the VM's static path, so coverage is the only thing that changes
    ///      between measurements. This is also the path that would break first if the adjuster
    ///      were not `view`.
    function _quoteSellRisky(ISwapVM.Order memory order, uint256 sell) internal view returns (uint256 out) {
        (, out,) = ISwapVM(address(router)).quote(order, sell, _takerData(address(risky) < address(quote)));
    }

    /// @notice The buffer prices itself off the vault's solvency, from inside the VM.
    function test_bufferWidensItsBidAsCoverageThins() public {
        _activate();
        ISwapVM.Order memory order = _order();
        uint256 sell = 10e18;

        uint256 healthy = _quoteSellRisky(order, sell);

        position.setValue(500_000e18); // b falls to ~14%, distress ~0.67
        uint256 stressed = _quoteSellRisky(order, sell);

        assertGt(healthy, 0, "quotes at full coverage");
        assertLt(stressed, healthy, "pays less for the same risky as the buffer thins");
    }

    /// @notice Once the policy stops bidding, the buffer refuses the risk-increasing side outright.
    function test_bufferStopsBiddingWhenThePolicySaturates() public {
        _activate();
        ISwapVM.Order memory order = _order();

        position.setValue(400_000e18); // NAV == senior claim, buffer exhausted
        assertFalse(vault.riskQuote().bidAllowed, "policy has stopped bidding");

        risky.mint(address(taker), 1e18);
        vm.expectRevert(SolvencyAdjuster.BiddingHalted.selector);
        taker.swap(order, 1e18, _takerData(address(risky) < address(quote)));
    }

    /// @notice Quote and swap must agree, which is why the adjuster is `view`. An extruction that
    ///         wrote storage would make the staticcall path diverge from the executing one.
    function test_quoteAndSwapAgree() public {
        _activate();
        ISwapVM.Order memory order = _order();
        uint256 sell = 5e18;

        uint256 quoted = _quoteSellRisky(order, sell);
        risky.mint(address(taker), sell);
        (, uint256 executed) = taker.swap(order, sell, _takerData(address(risky) < address(quote)));

        assertEq(executed, quoted, "static and executing paths return the same amount");
    }
}
