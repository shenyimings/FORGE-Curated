// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/**
 * @title Test ERC1155 token contract.
 */
contract NFT_1155 is ERC1155 {
    // ==================== Constructor ====================

    /**
     * @notice Initializes the ERC1155 token and mints initial tokens.
     * @param uri Token URI.
     * @param tokenHolder Address to receive initial tokens.
     */
    constructor(string memory uri, address tokenHolder) ERC1155(uri) {
        _mint(tokenHolder, 0, 10, "");
        _mint(tokenHolder, 1, 1000, "");
        _mint(tokenHolder, 2, 1000, "");
    }
}
