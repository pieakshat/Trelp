// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title SolvencyLib
/// @notice Canonical tranche accounting for a single epoch: senior accrual, coverage, waterfall.
/// @dev Every number the protocol settles on and the front end projects MUST come from here, so
///      that onchain settlement and offchain scenario analysis cannot drift apart.
///
///      Conventions:
///      - amounts are quote-token base units (e.g. USDC 1e6)
///      - rates and ratios are WAD (1e18)
///      - `couponWad` is the coupon for the WHOLE epoch, not an annualised rate
library SolvencyLib {
    uint256 internal constant WAD = 1e18;

    error ZeroSeniorPrincipal();
    error ZeroDuration();
    error ValueOverflow();

    /// @param seniorPrincipal S0, senior capital raised during subscription
    /// @param juniorPrincipal J0, junior capital raised during subscription
    /// @param couponWad       c, senior coupon over the epoch
    /// @param feeSplitWad     s, senior's share of realised fee income (the §3.2 split clause)
    /// @param start           t0, the moment capital was deployed
    /// @param duration        T, epoch length in seconds
    struct Terms {
        uint256 seniorPrincipal;
        uint256 juniorPrincipal;
        uint256 couponWad;
        uint256 feeSplitWad;
        uint64 start;
        uint64 duration;
    }

    /// @notice V0 = S0 + J0, the capital deployed at the start of the epoch.
    function totalPrincipal(Terms memory t) internal pure returns (uint256) {
        return t.seniorPrincipal + t.juniorPrincipal;
    }

    /// @notice j = J0 / V0, the subordination ratio. This is the risk price.
    function juniorShareWad(Terms memory t) internal pure returns (uint256) {
        uint256 v0 = totalPrincipal(t);
        if (v0 == 0) revert ZeroSeniorPrincipal();
        return (t.juniorPrincipal * WAD) / v0;
    }

    /// @notice b0 = J0 / S0 = j / (1 - j), coverage at the moment of deployment.
    function initialCoverageWad(Terms memory t) internal pure returns (uint256) {
        if (t.seniorPrincipal == 0) revert ZeroSeniorPrincipal();
        return (t.juniorPrincipal * WAD) / t.seniorPrincipal;
    }

    /// @notice S_claim(t) = S0 * (1 + c * (t - t0) / T), linear accrual, clamped to the epoch.
    /// @dev Used only for the live coverage signal. The claim that actually settles is
    ///      `finalSeniorClaim`, which is fee-dependent and may be lower.
    function accruedSeniorClaim(Terms memory t, uint256 timestamp) internal pure returns (uint256) {
        if (t.duration == 0) revert ZeroDuration();
        uint256 elapsed = timestamp <= t.start ? 0 : timestamp - t.start;
        if (elapsed > t.duration) elapsed = t.duration;
        uint256 accrued = (t.seniorPrincipal * t.couponWad * elapsed) / (WAD * t.duration);
        return t.seniorPrincipal + accrued;
    }

    /// @notice The senior claim that settles: S0 + min(S0 * c, s * F).
    /// @dev This is the §3.3 hybrid. The `min` is the split clause: in a quiet epoch the pool
    ///      cannot pay the coupon, and junior is not asked to fund it out of principal.
    ///
    ///      NOTE ON THE `max_rate` CAP IN THE PLAN: a cap above the fixed rate can never bind,
    ///      because min(S0*c, s*F) <= S0*c by construction. The fixed rate IS the cap on senior
    ///      upside. `maxCouponWad` is therefore enforced by TrancheVault as a bound on the
    ///      curator's choice of `c`, not as a third term in this payout.
    /// @param feesAccrued F, realised fee income over the epoch, in quote base units
    function finalSeniorClaim(Terms memory t, uint256 feesAccrued) internal pure returns (uint256) {
        uint256 fixedCoupon = (t.seniorPrincipal * t.couponWad) / WAD;
        uint256 splitCoupon = (feesAccrued * t.feeSplitWad) / WAD;
        return t.seniorPrincipal + (fixedCoupon < splitCoupon ? fixedCoupon : splitCoupon);
    }

    /// @notice B(t) = NAV(t) - S_claim(t). Signed: the buffer can be exhausted and go negative.
    function buffer(uint256 nav, uint256 seniorClaim) internal pure returns (int256) {
        return _toInt(nav) - _toInt(seniorClaim);
    }

    /// @notice b(t) = B(t) / S_claim(t), the coverage ratio the breaker watches.
    function coverageWad(uint256 nav, uint256 seniorClaim) internal pure returns (int256) {
        if (seniorClaim == 0) revert ZeroSeniorPrincipal();
        return (buffer(nav, seniorClaim) * int256(WAD)) / _toInt(seniorClaim);
    }

    /// @notice The settlement waterfall. Senior is paid first and capped at its claim; junior
    ///         takes the entire residual, including any recovery above the senior claim.
    function waterfall(uint256 nav, uint256 seniorClaim)
        internal
        pure
        returns (uint256 seniorPayout, uint256 juniorPayout)
    {
        seniorPayout = nav < seniorClaim ? nav : seniorClaim;
        juniorPayout = nav - seniorPayout;
    }

    function _toInt(uint256 x) private pure returns (int256) {
        if (x > uint256(type(int256).max)) revert ValueOverflow();
        return int256(x);
    }
}
