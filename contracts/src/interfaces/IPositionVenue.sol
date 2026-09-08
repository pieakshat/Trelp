// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice The venue that holds the LP position (the Uniswap v4 leg).
/// @dev Behind an interface so the vault's epoch and waterfall logic is unit-testable without a
///      fork.
interface IPositionVenue {
    /// @notice Deploy quote already transferred to this venue into the LP position.
    function deploy(uint256 quoteAmount) external;

    /// @notice Current mark-to-market value of the position, in quote base units.
    function valueInQuote() external view returns (uint256);

    /// @notice Move the position to a new range.
    /// @dev The venue rejects any range whose value at its exposed bound no longer covers the
    ///      senior claim with margin; only the venue knows the range. The vault enforces the policy
    ///      half — coverage floor, cooldown, and the cost of the move.
    function rebalance(bytes calldata venueData) external;

    /// @notice Burn the position, convert to quote, and return it to the vault.
    /// @return quoteReturned Quote base units actually delivered to the vault.
    function unwind() external returns (uint256 quoteReturned);
}
