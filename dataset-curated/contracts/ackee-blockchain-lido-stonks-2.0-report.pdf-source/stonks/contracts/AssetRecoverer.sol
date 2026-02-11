// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Ownable} from "./Ownable.sol";

/**
 * @title AssetRecoverer
 * @dev Abstract contract providing mechanisms for recovering various asset types (ETH, ERC20, ERC721, ERC1155) from a contract.
 * This contract is designed to allow asset recovery by an authorized agent or a manager.
 * @notice Assets can be sent only to the agent address.
 */
abstract contract AssetRecoverer is Ownable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    // ==================== Events ====================

    event EtherRecovered(address indexed recipient, uint256 amount);
    event ERC20Recovered(address indexed token, address indexed recipient, uint256 amount);
    event ERC721Recovered(address indexed token, uint256 tokenId, address indexed recipient);
    event ERC1155Recovered(
        address indexed token,
        uint256 tokenId,
        address indexed recipient,
        uint256 amount
    );

    // ==================== Constructor ====================

    /**
     * @dev Sets the initial agent address.
     * @param agent_ The address of the Lido DAO treasury.
     */
    constructor(address agent_) Ownable(agent_) {}

    // ==================== External Functions ====================

    /**
     * @dev Allows the agent or manager to recover Ether held by the contract.
     * @notice Implements CEI pattern: Checks (authorization) -> Effects (events) -> Interactions (transfer)
     * Emits an EtherRecovered event upon success.
     */
    function recoverEther() external onlyAgentOrManager {
        uint256 amount = address(this).balance;

        emit EtherRecovered(AGENT, amount);

        payable(AGENT).sendValue(amount);
    }

    /**
     * @dev Allows the agent or manager to recover ERC721 tokens held by the contract.
     * @param token_ The address of the ERC721 token to recover.
     * @param tokenId_ The token ID of the ERC721 token to recover.
     * Emits an ERC721Recovered event upon success.
     */
    function recoverERC721(address token_, uint256 tokenId_) external onlyAgentOrManager {
        emit ERC721Recovered(token_, tokenId_, AGENT);

        IERC721(token_).safeTransferFrom(address(this), AGENT, tokenId_);
    }

    /**
     * @dev Allows the agent or manager to recover ERC1155 tokens held by the contract.
     * @param token_ The address of the ERC1155 token to recover.
     * @param tokenId_ The token ID of the ERC1155 token to recover.
     * Emits an ERC1155Recovered event upon success.
     */
    function recoverERC1155(address token_, uint256 tokenId_) external onlyAgentOrManager {
        uint256 amount = IERC1155(token_).balanceOf(address(this), tokenId_);

        emit ERC1155Recovered(token_, tokenId_, AGENT, amount);

        IERC1155(token_).safeTransferFrom(address(this), AGENT, tokenId_, amount, "");
    }

    // ==================== Public Functions ====================

    /**
     * @dev Allows the agent or manager to recover ERC20 tokens held by the contract.
     * @param token_ The address of the ERC20 token to recover.
     * @param amount_ The amount of the ERC20 token to recover.
     * Emits an ERC20Recovered event upon success.
     */
    function recoverERC20(address token_, uint256 amount_) public virtual onlyAgentOrManager {
        emit ERC20Recovered(token_, AGENT, amount_);

        IERC20(token_).safeTransfer(AGENT, amount_);
    }
}
