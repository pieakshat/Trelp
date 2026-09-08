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
import {XYCConcentrateSwap} from "@1inch/swap-vm/src/instructions/XYCConcentrate.sol";

import {IBufferStrategy} from "../interfaces/IBufferStrategy.sol";

/// @title BufferStrategy
/// @notice The junior buffer's Aqua program: a single-sided concentrated bid, funded only by quote.
///
/// @dev WHY THIS SHAPE. The buffer's job is to *be there*, not to earn. A two-sided market maker
///      holds inventory in the risky asset — correlated with the exact drawdown the buffer exists
///      to absorb — which would recreate the problem one level out. What we want is a standing bid
///      that converts only when someone hits it at a discount.
///
///      Aqua-backed SwapVM programs are 2D AMM strategies; the 1D limit-order family uses
///      `StaticBalances` and is not Aqua-backed. So the bid is expressed as a *concentrated range
///      placed below spot*, which is the AMM spelling of a limit-order ladder.
///
///      That works with **zero risky balance**, which is the non-obvious part.
///      `XYCConcentrateSwap` adds virtual reserves derived from the price bounds on top of the real
///      Aqua balances, so the curve stays well defined with one side empty. And its partial-fill
///      clamp caps `amountOut` at the real balance. Together:
///
///        • a taker selling risky to us is filled from our real quote balance   → the bid works
///        • a taker trying to buy risky from us clamps to zero                  → nothing to give
///
///      So the vault ships quote alone and never needs a risky seed to open the buffer.
///
///      DAY 4. `OraclePriceAdjuster` pins the quote to a Chainlink mark, and `Extruction` calls the
///      vault's `riskQuote()` so the bid widens and shuts off as coverage thins. Both are stock
///      instructions, so neither needs a modified SwapVM.
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

    /// @notice Maker fee on the way in, basis points.
    uint24 public immutable feeBps;

    /// @dev Distinguishes otherwise identical strategies. Aqua rejects a re-ship of the same hash,
    ///      so a vault re-opening a buffer on the same terms needs a fresh salt.
    uint64 public immutable salt;

    constructor(
        address router_,
        address quote_,
        address risky_,
        uint256 sqrtPriceMin_,
        uint256 sqrtPriceMax_,
        uint24 feeBps_,
        uint64 salt_
    ) {
        router = router_;
        quote = quote_;
        risky = risky_;
        (tokenA, tokenB) = quote_ < risky_ ? (quote_, risky_) : (risky_, quote_);
        if (tokenA >= tokenB) revert TokensNotSorted();
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
            Salt.build(salt)
        );

        ISwapVM.Order memory order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: msg.sender, // the vault ships for itself; Aqua keys the maker off msg.sender
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
        // Quote only. The risky side opens empty and can only be filled into, never drawn from.
        if (tokenA == quote) {
            amounts[0] = quoteAmount;
        } else {
            amounts[1] = quoteAmount;
        }

        return (router, abi.encode(order), tokens, amounts);
    }
}
