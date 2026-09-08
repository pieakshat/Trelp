// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @notice A transferable claim on one tranche of a vault epoch.
/// @dev Claims are ERC-20 because secondary trading is the only exit during the active phase
///      (plan §4). Mint and burn are vault-only.
contract TrancheToken is ERC20 {
    error NotVault();

    address public immutable vault;

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address vault_)
        ERC20(name_, symbol_, decimals_)
    {
        vault = vault_;
    }

    function mint(address to, uint256 amount) external onlyVault {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyVault {
        _burn(from, amount);
    }
}
