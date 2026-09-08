// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice The venue that holds the LP position (the Uniswap v4 leg).
/// @dev Kept behind an interface so the vault's epoch and waterfall logic is unit-testable without
///      a fork, and so the v4 range/hook work can land independently.
interface IPositionVenue {
    /// @notice Deploy quote already transferred to this venue into the LP position.
    function deploy(uint256 quoteAmount) external;

    /// @notice Current mark-to-market value of the position, in quote base units.
    function valueInQuote() external view returns (uint256);

    /// @notice Cumulative fee income earned over the epoch, in quote base units.
    /// @dev MUST survive `unwind()`, since the settlement split clause reads it afterwards.
    function feesInQuote() external view returns (uint256);

    /// @notice Burn the position, convert to quote, and return it to the vault.
    /// @return quoteReturned Quote base units actually delivered to the vault.
    function unwind() external returns (uint256 quoteReturned);
}
