// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:changes 2026-09-08 — Trelp: new file. An `Extruction` target that prices the buffer off
///                 the vault's solvency. No SwapVM or Aqua source is modified.

import {IStaticExtruction} from "@1inch/swap-vm/src/instructions/Extruction.sol";
import {SwapQuery, SwapRegisters} from "@1inch/swap-vm/src/libs/VM.sol";

import {IQuoteOracle} from "../interfaces/IQuoteOracle.sol";
import {IVaultPolicy} from "../interfaces/IVaultPolicy.sol";
import {RiskPolicy} from "../libraries/RiskPolicy.sol";

/// @title SolvencyAdjuster
/// @notice Anchors the buffer's bid to an oracle mark and prices it off vault solvency.
///
/// @dev Runs as an `Extruction` target placed after the curve, so it works against the official
///      deployed SwapVM with no redeployment.
///
///      Anchoring is load bearing. A concentrated curve prices off its range alone, unrelated to
///      the market, so a coverage policy refusing those fills would be refusing trades of unknown
///      sign. Bounding the bid at the oracle mark less the policy spread gives the policy something
///      coherent to protect; curve and bound both apply, and the tighter one wins.
///
///      One `view` function serves both `IExtruction` and `IStaticExtruction`: they share a
///      selector and differ only in mutability. `view` is also required in substance — an
///      extruction that wrote storage would make quoting (a staticcall) diverge from execution.
///
///      Reading `riskQuote()` reaches NAV and the position venue's mark. That terminates only
///      because a venue's mark never reads the policy back.
contract SolvencyAdjuster is IStaticExtruction {
    error BiddingHalted();

    uint256 internal constant WAD = 1e18;

    IVaultPolicy public immutable vault;
    IQuoteOracle public immutable oracle;

    /// @notice The asset the vault takes on inventory in. Receiving it is the risk-increasing side.
    /// @dev Read from the vault rather than passed in, so the gate cannot end up applying to the
    ///      wrong side of the trade.
    address public immutable risky;

    constructor(IVaultPolicy vault_, IQuoteOracle oracle_) {
        vault = vault_;
        oracle = oracle_;
        risky = vault_.risky();
    }

    /// @inheritdoc IStaticExtruction
    function extruction(
        bool,
        uint256 nextPC,
        SwapQuery calldata query,
        SwapRegisters calldata swap,
        bytes calldata,
        bytes calldata
    ) external view returns (uint256, uint256 choppedLength, SwapRegisters memory updated) {
        RiskPolicy.Quote memory q = vault.riskQuote();
        updated = swap;

        // `tokenIn` is what the maker receives, so the vault acquires risky exactly when the
        // taker pays it in. That is the side the policy gates.
        bool acquiringRisky = query.tokenIn == risky;
        if (acquiringRisky && !q.bidAllowed) revert BiddingHalted();

        if (query.isExactIn) {
            uint256 bounded = swap.amountOut - (swap.amountOut * q.spreadWad) / WAD;

            if (acquiringRisky) {
                // Cap what we pay at the mark less the spread. Without it the curve's price is
                // unmoored from the market and refusing a fill is as likely to forgo a gain as
                // avoid a loss. The tighter of curve and bound wins.
                uint256 mark = oracle.valueInQuote(risky, swap.amountIn);
                uint256 ceiling = mark - (mark * q.spreadWad) / WAD;
                if (ceiling < bounded) bounded = ceiling;
            }

            updated.amountOut = bounded;
        } else {
            // Exact-out carries the spread but not the bound: `IQuoteOracle` cannot invert, so
            // there is no mark to bound against. The buffer's own flow is exact-in.
            updated.amountIn = swap.amountIn + (swap.amountIn * q.spreadWad) / WAD;
        }

        // No taker arguments consumed; the program counter is untouched.
        return (nextPC, 0, updated);
    }
}
