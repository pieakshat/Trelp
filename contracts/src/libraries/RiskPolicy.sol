// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title RiskPolicy
/// @notice Turns the vault's solvency state into quoting instructions.
///
/// @dev This is the breaker. The original plan modelled it as three stages -- widen and skew, flip
///      the range above spot, then a keeper market-sell -- because a Uniswap v4 position cannot
///      express any of them directly. Priced as a function instead, all three are regions of one
///      curve in the distress signal `d`, plus a revocation the vault owns:
///
///          d = 0            quote normally
///          0 < d < cutoff   widen the spread, skew away from the side we are accumulating
///          d >= cutoff      stop bidding entirely; sell-only
///          inventory cap    stop bidding regardless of d
///
///      Pure and venue-agnostic, so the same policy drives the v4 hook's dynamic fee and the Aqua
///      buffer's quote, and paths 3 and 4 of the demo differ by one boolean.
///
///      INVARIANT: nothing here may read a venue's mark. NAV feeds coverage feeds this, so a venue
///      that priced off the policy would close a read loop.
library RiskPolicy {
    uint256 internal constant WAD = 1e18;

    error NonPositiveTarget();

    /// @param baseSpreadWad    s0, the spread quoted at full coverage
    /// @param alphaWad         widening coefficient: spread = s0 * (1 + alpha * d)
    /// @param kappaWad         skew coefficient applied to inventory imbalance
    /// @param targetCoverageWad b_target, normally b0 = j / (1 - j)
    /// @param bidCutoffWad     the `d` at which the vault stops acquiring the risky asset
    /// @param maxInventoryWad  hard ceiling on risky inventory as a fraction of principal
    struct Params {
        uint256 baseSpreadWad;
        uint256 alphaWad;
        uint256 kappaWad;
        int256 targetCoverageWad;
        uint256 bidCutoffWad;
        uint256 maxInventoryWad;
    }

    /// @param spreadWad   half-spread to quote around the oracle mid
    /// @param skewWad     signed shift of the quoted mid, positive when leaning away from inventory
    /// @param bidAllowed  may the vault acquire more of the risky asset
    /// @param askAllowed  may the vault sell the risky asset (always true: selling reduces risk)
    struct Quote {
        uint256 spreadWad;
        int256 skewWad;
        bool bidAllowed;
        bool askAllowed;
    }

    /// @notice d = clamp(0, 1, 1 - b / b_target). Saturates at 1 once the buffer is exhausted.
    function distressWad(int256 coverageWad, int256 targetCoverageWad) internal pure returns (uint256) {
        if (targetCoverageWad <= 0) revert NonPositiveTarget();
        if (coverageWad <= 0) return WAD;
        if (coverageWad >= targetCoverageWad) return 0;
        return WAD - (uint256(coverageWad) * WAD) / uint256(targetCoverageWad);
    }

    /// @notice Inventory as a fraction of principal, the imbalance the skew leans against.
    function inventoryRatioWad(uint256 riskyValue, uint256 principal) internal pure returns (uint256) {
        if (principal == 0) return 0;
        return (riskyValue * WAD) / principal;
    }

    /// @notice The full quoting instruction for the current state.
    /// @param riskyValue Quote-denominated value of risky inventory the vault is holding
    /// @param principal  V0, the capital deployed at the start of the epoch
    function evaluate(Params memory p, int256 coverageWad, uint256 riskyValue, uint256 principal)
        internal
        pure
        returns (Quote memory q)
    {
        uint256 d = distressWad(coverageWad, p.targetCoverageWad);
        uint256 inv = inventoryRatioWad(riskyValue, principal);

        // Widen: give up fee income to cut adverse selection as the buffer thins.
        q.spreadWad = p.baseSpreadWad + (p.baseSpreadWad * p.alphaWad * d) / (WAD * WAD);

        // Skew: push the quoted mid away from the side we are accumulating.
        q.skewWad = int256((p.kappaWad * d * inv) / (WAD * WAD));

        // Two independent reasons to stop bidding. The inventory cap is the structural one: an
        // oracle band caps what an adversary extracts per fill, not per epoch, so the ceiling on
        // convertible capital is what actually bounds total loss.
        q.bidAllowed = d < p.bidCutoffWad && inv < p.maxInventoryWad;
        q.askAllowed = true;
    }
}
