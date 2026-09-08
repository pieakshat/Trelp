// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice The subset of 1inch Aqua the vault calls.
/// @dev Declared locally rather than imported. Aqua is source-available under
///      `LicenseRef-Degensoft-Aqua-Source-1.1`, whose §3.1 copyleft reaches anything that links
///      against it, while §3.3 exempts code that merely calls it through its ABI. Keeping the vault
///      to a hand-written interface puts it unambiguously on the §3.3 side and lets it stay MIT.
///      The contract actually called is the official deployed Aqua.
interface IAquaRegistry {
    /// @notice Register a strategy and allocate virtual balances to it.
    /// @dev The maker is `msg.sender`, which is why the vault ships for itself: a helper contract
    ///      could only ship capital it holds, and the whole point is that the capital stays here.
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
