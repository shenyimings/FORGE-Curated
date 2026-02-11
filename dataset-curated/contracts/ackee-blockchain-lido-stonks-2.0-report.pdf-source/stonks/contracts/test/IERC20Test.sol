// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Test ERC20 token contract.
 */
contract ERC_20 is ERC20 {
    // ==================== Constructor ====================

    /**
     * @notice Initializes the ERC20 token and mints initial supply to deployer.
     */
    constructor() ERC20("ERC_20", "STUB") {
        _mint(msg.sender, 1000000 ether);
    }
}
