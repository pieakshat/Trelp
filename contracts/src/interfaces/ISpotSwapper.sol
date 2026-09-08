// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Converts between the vault's two assets at or near spot on an external venue.
/// @dev Used at both ends of an epoch: to buy the risky leg when seeding the LP position, and to
///      sell it back during settlement. Kept in its own file so the vault can reach it without
///      importing the v4 venue, which would pull v4-core into the vault's compilation chain.
interface ISpotSwapper {
    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external
        returns (uint256 amountOut);
}
