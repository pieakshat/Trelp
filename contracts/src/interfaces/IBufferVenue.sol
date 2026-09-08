// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice The venue the junior buffer quotes on (the 1inch Aqua leg).
/// @dev Models Aqua's ACTUAL semantics, which differ from the build plan's assumption in a way that
///      matters for accounting:
///
///      Aqua never takes custody. `ship()` writes a virtual balance into the Aqua registry
///      (`balances[maker][app][strategyHash][token]`); the tokens stay in the maker's wallet — here,
///      in the vault. Takers `pull()` from and `push()` to that wallet at fill time.
///
///      Consequences the vault relies on:
///      1. Shipped capital is STILL in `quote.balanceOf(vault)`. It must not be added to NAV a
///         second time as a separate venue balance, or the buffer is double-counted.
///      2. The "call" (plan §8) is `dock()`, which is a permission revocation, not a withdrawal.
///         It is genuinely one transaction and cannot fail for liquidity reasons.
///      3. `dock()` must close ALL tokens in the strategy (Aqua reverts otherwise), so the call is
///         all-or-nothing per strategy. A partial buffer call needs two shipped strategies.
///      4. Strategies are immutable once shipped. A spread or skew that depends on live coverage
///         cannot be a strategy parameter; it must be read from the vault by the app at swap time.
interface IBufferVenue {
    /// @notice Ship a strategy allocating `quoteAmount` of the vault's balance as virtual liquidity.
    function ship(uint256 quoteAmount) external;

    /// @notice Revoke the shipped strategy. This is the §8 call.
    function dock() external;

    /// @notice Quote base units currently shipped. Reporting only — NOT a NAV term (see note 1).
    function shippedQuote() external view returns (uint256);

    /// @notice Whether a strategy is currently shipped and quotable.
    function isShipped() external view returns (bool);
}
