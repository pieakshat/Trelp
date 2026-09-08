// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Values a token amount in the vault's quote asset.
/// @dev Must be TWAP-backed in a real deployment: the coverage signal drives the breaker, and a
///      spot-readable mark lets a single-block move force the call.
interface IQuoteOracle {
    function valueInQuote(address token, uint256 amount) external view returns (uint256);
}
