// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RiskPolicy} from "../libraries/RiskPolicy.sol";

/// @notice The vault's current quoting instruction, as both venues read it.
/// @dev One policy, two venues. The v4 hook applies it as a dynamic fee plus a directional halt;
///      the Aqua buffer applies it inside the VM through an `Extruction` target.
interface IVaultPolicy {
    function riskQuote() external view returns (RiskPolicy.Quote memory);
}
