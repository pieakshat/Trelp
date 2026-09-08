// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/main/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:changes 2026-09-08 — Trelp: new file. An `Extruction` target that prices the buffer off
///                 the vault's solvency. No SwapVM or Aqua source is modified.

import {IStaticExtruction} from "@1inch/swap-vm/src/instructions/Extruction.sol";
import {SwapQuery, SwapRegisters} from "@1inch/swap-vm/src/libs/VM.sol";

import {IVaultPolicy} from "../interfaces/IVaultPolicy.sol";
import {RiskPolicy} from "../libraries/RiskPolicy.sol";

/// @title SolvencyAdjuster
/// @notice Makes the junior buffer price itself off the vault's coverage, from inside the VM.
///
/// @dev This is the coverage-aware half of the breaker on the Aqua leg. Placed after the curve
///      instruction, it takes the amounts the curve produced and moves them in the maker's favour
///      in proportion to distress — so the buffer's bid widens as the buffer thins, and stops
///      entirely once the policy says so.
///
///      NO MODIFIED SwapVM. `Extruction` is a stock opcode that delegates the swap registers to a
///      maker-chosen contract, so this runs against the official deployed VM. Promoting the same
///      logic to a custom opcode in one of the reserved enum slots is a scoring upgrade, not a
///      dependency.
///
///      WHY ONE `view` FUNCTION SATISFIES BOTH INTERFACES. The VM calls `IStaticExtruction` when
///      quoting and `IExtruction` when swapping. The two declare the same signature and differ only
///      in mutability, which is not part of the selector — so a single `view` implementation serves
///      both call paths. That is the right shape anyway: the docs warn that an extruction which
///      writes storage makes `quote()` and `swap()` diverge, because quoting is a staticcall.
///      Being `view` makes that failure unrepresentable rather than merely avoided.
///
///      THE READ LOOP. This reads `vault.riskQuote()`, which reads NAV, which reads the position
///      venue's mark. That terminates only because a venue's mark never reads the policy back.
contract SolvencyAdjuster is IStaticExtruction {
    error BiddingHalted();

    uint256 internal constant WAD = 1e18;

    IVaultPolicy public immutable vault;

    /// @notice The asset the vault takes on inventory in. Receiving it is the risk-increasing side.
    address public immutable risky;

    constructor(IVaultPolicy vault_, address risky_) {
        vault = vault_;
        risky = risky_;
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

        // `tokenIn` is what the maker receives, so the vault is acquiring the risky asset exactly
        // when the taker is paying it in. That is the side the policy gates.
        if (query.tokenIn == risky && !q.bidAllowed) revert BiddingHalted();

        // Widen in the maker's favour: pay out less, or charge more in.
        if (query.isExactIn) {
            updated.amountOut = swap.amountOut - (swap.amountOut * q.spreadWad) / WAD;
        } else {
            updated.amountIn = swap.amountIn + (swap.amountIn * q.spreadWad) / WAD;
        }

        // No taker arguments consumed, and the program counter is left alone.
        return (nextPC, 0, updated);
    }
}
