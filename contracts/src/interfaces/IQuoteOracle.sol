// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Values a token amount in the vault's quote asset.
/// @dev MUST be TWAP-backed in any real deployment. The coverage signal drives the breaker, and a
///      spot-readable oracle lets a single-block manipulation force a liquidation (plan §11).
interface IQuoteOracle {
    function valueInQuote(address token, uint256 amount) external view returns (uint256);
}
