// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:changes 2026-09-08 — Trelp: new file. Composes stock SwapVM instructions into a
///                 single-sided buffer program. No SwapVM or Aqua source is modified.

import {ISwapVM} from "@1inch/swap-vm/src/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "@1inch/swap-vm/src/libs/MakerTraits.sol";
import {Salt} from "@1inch/swap-vm/src/instructions/Controls.sol";
import {FeeFlatIn} from "@1inch/swap-vm/src/instructions/FeeFlat.sol";
import {Extruction} from "@1inch/swap-vm/src/instructions/Extruction.sol";
import {XYCConcentrateSwap} from "@1inch/swap-vm/src/instructions/XYCConcentrate.sol";

import {IBufferStrategy} from "../interfaces/IBufferStrategy.sol";

/// @title BufferStrategy
/// @notice The junior buffer's Aqua program: a single-sided concentrated bid, funded only by quote.
///
/// @dev The buffer's job is to be available, not to earn. A two-sided maker would hold inventory
///      in the risky asset, correlated with the drawdown the buffer exists to absorb; a standing
///      bid converts only when someone hits it at a discount.
///
///      Aqua-backed programs are 2D AMM strategies, so that bid is expressed as a concentrated
///      range below spot — the AMM spelling of a limit-order ladder. It works with a zero risky
///      balance because `XYCConcentrateSwap` derives virtual reserves from the price bounds, and
///      clamps payout to the real balance:
///
///        • a taker selling risky is filled from our real quote balance → the bid works
///        • a taker trying to buy risky clamps to zero                  → nothing to give
///
///      So the vault ships quote alone and needs no risky seed.
///
///      `Extruction` hands the swap registers to `SolvencyAdjuster`, which anchors the bid to the
///      oracle and widens it with distress. Omitting that term disables coverage-aware pricing.
contract BufferStrategy is IBufferStrategy {
    error TokensNotSorted();

    /// @notice The Aqua app. For SwapVM programs this is the router itself, not a contract we write.
    address public immutable router;

    address public immutable quote;
    address public immutable risky;

    /// @notice Sorted pair, as SwapVM requires.
    address public immutable tokenA;
    address public immutable tokenB;

    /// @notice Bid range, as sqrt prices in 1e18. Both bounds sit below spot, so the position is
    ///         entirely quote until price falls into it.
    uint256 public immutable sqrtPriceMin;
    uint256 public immutable sqrtPriceMax;

    /// @notice Extruction target that prices the bid off vault solvency. Zero disables it.
    address public immutable adjuster;

    /// @notice Maker fee on the way in, basis points.
    uint24 public immutable feeBps;

    /// @dev Aqua rejects a re-ship of the same hash, so a buffer re-opened on the same terms
    ///      needs a fresh salt.
    uint64 public immutable salt;

    constructor(
        address router_,
        address quote_,
        address risky_,
        uint256 sqrtPriceMin_,
        uint256 sqrtPriceMax_,
        address adjuster_,
        uint24 feeBps_,
        uint64 salt_
    ) {
        router = router_;
        quote = quote_;
        risky = risky_;
        (tokenA, tokenB) = quote_ < risky_ ? (quote_, risky_) : (risky_, quote_);
        if (tokenA >= tokenB) revert TokensNotSorted();
        adjuster = adjuster_;
        sqrtPriceMin = sqrtPriceMin_;
        sqrtPriceMax = sqrtPriceMax_;
        feeBps = feeBps_;
        salt = salt_;
    }

    /// @inheritdoc IBufferStrategy
    function shipParams(uint256 quoteAmount)
        external
        view
        returns (address app, bytes memory strategy, address[] memory tokens, uint256[] memory amounts)
    {
        bytes memory program = bytes.concat(
            feeBps > 0 ? FeeFlatIn.build(feeBps) : bytes(""),
            XYCConcentrateSwap.build(sqrtPriceMin, sqrtPriceMax),
            adjuster != address(0) ? Extruction.build(adjuster, "") : bytes(""),
            Salt.build(salt)
        );

        ISwapVM.Order memory order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: msg.sender, // Aqua keys the maker off msg.sender
                receiver: address(0),
                tokenA: tokenA,
                tokenB: tokenB,
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                hasPreTransferInHook: false,
                hasPostTransferInHook: false,
                hasPreTransferOutHook: false,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(0),
                postTransferInData: "",
                preTransferOutTarget: address(0),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: program
            })
        );

        tokens = new address[](2);
        amounts = new uint256[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        // Quote only: the risky side opens empty and can be filled into, never drawn from.
        if (tokenA == quote) {
            amounts[0] = quoteAmount;
        } else {
            amounts[1] = quoteAmount;
        }

        return (router, abi.encode(order), tokens, amounts);
    }
}
