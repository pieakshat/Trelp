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
/// @notice Anchors the junior buffer's bid to an oracle mark and prices it off vault solvency.
///
/// @dev Two jobs, and the first one is load bearing.
///
///      **Oracle anchoring.** A bare concentrated curve prices off its range alone, with no
///      relation to the market. Fills then land at arbitrary prices, and a policy that refuses
///      them is refusing trades of unknown sign — it can just as easily destroy value as protect
///      it. So the bid is bounded: never pay more than the oracle mark less the policy spread. The
///      curve still applies, and whichever side is tighter wins.
///
///      **Coverage awareness.** The spread in that bound comes from the vault's distress signal,
///      so the bid widens as the buffer thins and refuses outright once the policy stops bidding.
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
    IQuoteOracle public immutable oracle;

    /// @notice The asset the vault takes on inventory in. Receiving it is the risk-increasing side.
    address public immutable risky;

    constructor(IVaultPolicy vault_, IQuoteOracle oracle_, address risky_) {
        vault = vault_;
        oracle = oracle_;
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
        bool acquiringRisky = query.tokenIn == risky;
        if (acquiringRisky && !q.bidAllowed) revert BiddingHalted();

        if (query.isExactIn) {
            uint256 bounded = swap.amountOut - (swap.amountOut * q.spreadWad) / WAD;

            if (acquiringRisky) {
                // Cap what we pay at the oracle mark less the spread. Without this the curve's
                // price is unmoored from the market and the coverage policy has nothing coherent
                // to protect: refusing a mispriced fill is as likely to forgo a gain as avoid a
                // loss. Whichever of curve and oracle is tighter wins.
                uint256 mark = oracle.valueInQuote(risky, swap.amountIn);
                uint256 ceiling = mark - (mark * q.spreadWad) / WAD;
                if (ceiling < bounded) bounded = ceiling;
            }

            updated.amountOut = bounded;
        } else {
            // Exact-out carries the spread but not the oracle bound: `IQuoteOracle` values a token
            // amount and cannot invert, so there is no mark to bound against here. The buffer's
            // own flow is exact-in; this branch exists so the program is total.
            updated.amountIn = swap.amountIn + (swap.amountIn * q.spreadWad) / WAD;
        }

        // No taker arguments consumed, and the program counter is left alone.
        return (nextPC, 0, updated);
    }
}
