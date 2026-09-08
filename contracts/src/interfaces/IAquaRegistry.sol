// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice The subset of 1inch Aqua the vault calls.
/// @dev Declared locally rather than imported. Aqua is source-available under the Degensoft
///      licence, whose copyleft reaches code that links against it but exempts code that merely
///      calls it through its ABI. A hand-written interface keeps the vault unambiguously on the
///      exempt side and MIT. The contract called is the official deployed Aqua.
interface IAquaRegistry {
    /// @notice Register a strategy and allocate virtual balances to it.
    /// @dev The maker is `msg.sender`, so the vault ships for itself — a helper contract could
    ///      only ship capital it holds.
    function ship(address app, bytes calldata strategy, address[] calldata tokens, uint256[] calldata amounts)
        external
        returns (bytes32 strategyHash);

    /// @notice Revoke a strategy. Must close every token in it.
    function dock(address app, bytes32 strategyHash, address[] calldata tokens) external;

    function rawBalances(address maker, address app, bytes32 strategyHash, address token)
        external
        view
        returns (uint248 balance, uint8 tokensCount);
}
