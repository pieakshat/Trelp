// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Supplies the encoded Aqua strategy the junior buffer quotes on.
/// @dev Not a venue: it never holds capital and never calls Aqua. Aqua keys the maker off
///      `msg.sender`, so the vault ships for itself, which is what keeps the buffer inside the
///      vault's own balance.
///
///      The strategy bytes are opaque here because building them imports SwapVM's instruction
///      libraries — static linking under the Degensoft licence. Implementations therefore live
///      under `src/aqua/` with that licence, leaving the vault MIT.
interface IBufferStrategy {
    /// @notice Everything the vault needs to ship a buffer of `quoteAmount`.
    /// @return app The Aqua app to ship to — for SwapVM programs this is the router itself.
    /// @return strategy ABI-encoded strategy; its keccak is the Aqua strategy hash.
    /// @return tokens Tokens the strategy quotes, in the order Aqua records them.
    /// @return amounts Virtual balance for each token. No tokens move when these are recorded.
    function shipParams(uint256 quoteAmount)
        external
        view
        returns (address app, bytes memory strategy, address[] memory tokens, uint256[] memory amounts);
}
