// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

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
    /// @param feeSplitWad     s, senior's share of net epoch P&L. DERIVED from `j` at activation
    ///                        via `splitFromJuniorShare`, never configured directly.
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

    /// @notice The split `s` that keeps junior ahead of simply LPing the pool, at ANY fee yield.
    /// @dev Requiring junior's return to beat the unlevered pool return and taking the worst case
    ///      over all fee yields makes the fee term drop out entirely, leaving
    ///
    ///          s  <=  (1 - 2j) / (1 - j)
    ///
    ///      `lambdaWad` is the fraction of that envelope senior is actually given, and is the only
    ///      curator input. Returns 0 at j >= 50%, where no split can make junior worth doing --
    ///      so the 50% wall is arithmetic here rather than a hardcoded guard elsewhere.
    function splitFromJuniorShare(uint256 jWad, uint256 lambdaWad)
        internal
        pure
        returns (uint256)
    {
        if (jWad >= WAD / 2) return 0;
        return (lambdaWad * (WAD - 2 * jWad)) / (WAD - jWad);
    }

    /// @notice The senior claim that settles: S0 + min(S0 * c, s * max(0, NAV - V0)).
    /// @dev Anchored on NET epoch P&L, not gross fee income. Earning spread while being adversely
    ///      selected is not income, and a gross-fee split would overpay senior in exactly the
    ///      epochs where junior is absorbing the loss. It also means the vault needs no fee oracle
    ///      from the venue: NAV is sufficient.
    ///
    ///      The `min` is the split clause. In a losing epoch the gain is zero and senior receives
    ///      no coupon at all -- only principal priority, which is the correct behaviour.
    ///
    ///      NOTE ON THE `max_rate` CAP IN THE ORIGINAL PLAN: a cap above the fixed rate can never
    ///      bind, because min(S0*c, s*gain) <= S0*c by construction. The fixed rate IS the cap on
    ///      senior upside. `maxCouponWad` is enforced by TrancheVault as a bound on the curator's
    ///      choice of `c`, not as a third term here.
    /// @param nav Net asset value at settlement, in quote base units
    function finalSeniorClaim(Terms memory t, uint256 nav) internal pure returns (uint256) {
        uint256 v0 = totalPrincipal(t);
        uint256 gain = nav > v0 ? nav - v0 : 0;
        uint256 fixedCoupon = (t.seniorPrincipal * t.couponWad) / WAD;
        uint256 splitCoupon = (gain * t.feeSplitWad) / WAD;
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
