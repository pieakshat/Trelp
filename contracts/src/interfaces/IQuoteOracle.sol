// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Values a token amount in the vault's quote asset.
///
/// @dev Units. `amount` is in `token`'s own base units; the return is in the **quote asset's** base
///      units. For a USDC-quoted vault holding WETH, `valueInQuote(WETH, 1e18)` returns about
///      `2000e6`, not `2000e18`.
///
///      An implementation has to reconcile three independent decimal scales — the price feed's,
///      `token`'s, and the quote asset's — and may assume none of them.
///
///      Getting this wrong is silent and total. `nav()` adds the result straight onto a quote
///      balance, so a mis-scaled return misprices the vault by orders of magnitude: coverage stops
///      meaning anything and the breaker never fires. Nothing on-chain can catch it either, since
///      without knowing the expected price there is no way to tell a correct answer from one that
///      is off by 1e12.
///
///      Must also be TWAP-backed in a real deployment: the coverage signal drives the breaker, and
///      a spot-readable mark lets a single-block move force the call.
interface IQuoteOracle {
    /// @param token  the asset being valued
    /// @param amount quantity of `token`, in `token`'s base units
    /// @return value the same quantity expressed in the quote asset's base units
    function valueInQuote(address token, uint256 amount) external view returns (uint256 value);
}
