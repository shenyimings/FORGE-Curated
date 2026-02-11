// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title PRL Token
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice PRL token contract.
contract PRL is ERC20Permit {
    constructor(uint256 totalSupply)
        ERC20("Parallel Governance Token", "PRL")
        ERC20Permit("Parallel Governance Token")
    {
        _mint(msg.sender, totalSupply);
    }
}
