// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RiskPolicy} from "../libraries/RiskPolicy.sol";

/// @notice The vault's current quoting instruction, as both venues read it.
/// @dev One policy, two venues. The v4 hook applies it as a dynamic fee plus a directional halt;
///      the Aqua buffer applies it inside the VM through an `Extruction` target.
interface IVaultPolicy {
    function riskQuote() external view returns (RiskPolicy.Quote memory);

    /// @notice The accounting unit. Senior deposits it and is repaid in it.
    function quote() external view returns (address);

    /// @notice The asset the vault takes inventory in. Acquiring it is the risk-increasing side.
    /// @dev Venues derive their own asset ordering from this rather than being told, so a
    ///      deployment argument cannot silently invert a directional control.
    function risky() external view returns (address);
}
