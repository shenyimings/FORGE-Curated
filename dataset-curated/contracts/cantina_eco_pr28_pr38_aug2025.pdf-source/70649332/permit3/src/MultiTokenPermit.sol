// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { IMultiTokenPermit } from "./interfaces/IMultiTokenPermit.sol";

import { PermitBase } from "./PermitBase.sol";

/**
 * @title MultiTokenPermit
 * @notice Multi-token support (ERC20, ERC721, ERC1155) for the Permit3 system
 * @dev Extends PermitBase with NFT and semi-fungible token functionality
 */
abstract contract MultiTokenPermit is PermitBase, IMultiTokenPermit {
    /**
     * @dev Internal helper to get the storage key for a token/tokenId pair
     * @param token Token contract address
     * @param tokenId Token ID (0 for ERC20, specific ID for NFT, type(uint256).max for collection-wide)
     * @return Storage key for allowance mapping
     */
    function _getTokenKey(address token, uint256 tokenId) internal pure returns (bytes32) {
        if (tokenId == type(uint256).max) {
            // ERC20 or collection-wide approval - convert address to bytes32
            return bytes32(uint256(uint160(token)));
        } else {
            // Specific token ID - hash token and tokenId together
            return keccak256(abi.encodePacked(token, tokenId));
        }
    }

    /**
     * @notice Query multi-token allowance for a specific token ID
     * @param owner Token owner
     * @param token Token contract address
     * @param spender Approved spender
     * @param tokenId Token ID (0 for ERC20, type(uint256).max for NFT collection-wide approval allowing any token in
     * collection)
     * @return amount Approved amount (max uint160 for unlimited)
     * @return expiration Timestamp when approval expires (0 for no expiration)
     * @return timestamp Timestamp when approval was set
     */
    function allowance(
        address owner,
        address token,
        address spender,
        uint256 tokenId
    ) external view override returns (uint160 amount, uint48 expiration, uint48 timestamp) {
        bytes32 tokenKey = _getTokenKey(token, tokenId);
        Allowance memory allowed = allowances[owner][tokenKey][spender];
        return (allowed.amount, allowed.expiration, allowed.timestamp);
    }

    /**
     * @notice Approve a spender for a specific token or collection
     * @param token Token contract address
     * @param spender Address to approve
     * @param tokenId Token ID (0 for ERC20, specific ID for NFT, type(uint256).max for NFT collection-wide approval)
     * @param amount Amount to approve (ignored for ERC721, used for ERC20/ERC1155)
     * @param expiration Timestamp when approval expires (0 for no expiration)
     */
    function approve(
        address token,
        address spender,
        uint256 tokenId,
        uint160 amount,
        uint48 expiration
    ) external override {
        bytes32 tokenKey = _getTokenKey(token, tokenId);

        // Use the same validation as PermitBase
        _validateApproval(msg.sender, tokenKey, token, spender, expiration);

        // Update the allowance
        allowances[msg.sender][tokenKey][spender] =
            Allowance({ amount: amount, expiration: expiration, timestamp: uint48(block.timestamp) });

        // Emit standard approval event from IPermit interface - emit original token address
        emit Approval(msg.sender, token, spender, amount, expiration);
    }

    /**
     * @notice Execute approved ERC721 token transfer
     * @dev Uses a dual-allowance system: first checks for specific token ID approval,
     *      then falls back to collection-wide approval (set with tokenId = type(uint256).max).
     *      This allows users to either approve individual NFTs or entire collections.
     * @param from Token owner address
     * @param to Transfer recipient address
     * @param token ERC721 contract address
     * @param tokenId The unique NFT token ID to transfer
     */
    function transferFrom(address from, address to, address token, uint256 tokenId) public override {
        // Get the encoded identifier for this specific token ID
        bytes32 encodedId = _getTokenKey(token, tokenId);

        // First, try to update allowance for the specific token ID
        (, bytes memory revertDataPerId) = _updateAllowance(from, encodedId, msg.sender, 1);

        if (revertDataPerId.length > 0) {
            // Fallback: if no specific token approval exists, check for collection-wide approval
            // Collection-wide approval is set by calling approve() with tokenId = type(uint256).max
            bytes32 collectionKey = bytes32(uint256(uint160(token)));

            if (encodedId == collectionKey) {
                // Special case: tokenId = max is the same wild card approval
                _revert(revertDataPerId);
            }

            (, bytes memory revertDataWildcard) = _updateAllowance(from, collectionKey, msg.sender, 1);

            _handleAllowanceError(revertDataPerId, revertDataWildcard);
        }
        IERC721(token).safeTransferFrom(from, to, tokenId);
    }

    /**
     * @notice Execute approved ERC1155 token transfer
     * @dev Uses a dual-allowance system: first checks for specific token ID approval,
     *      then falls back to collection-wide approval (set with tokenId = type(uint256).max).
     *      This allows users to either approve individual token types or entire collections.
     * @param from Token owner address
     * @param to Transfer recipient address
     * @param token ERC1155 contract address
     * @param tokenId The specific ERC1155 token ID to transfer
     * @param amount Number of tokens to transfer
     */
    function transferFrom(address from, address to, address token, uint256 tokenId, uint160 amount) public override {
        // Get the encoded identifier for this specific token ID
        bytes32 encodedId = _getTokenKey(token, tokenId);

        // First, try to update allowance for the specific token ID
        (, bytes memory revertDataPerId) = _updateAllowance(from, encodedId, msg.sender, amount);

        if (revertDataPerId.length > 0) {
            // Fallback: if no specific token approval exists, check for collection-wide approval
            // Collection-wide approval is set by calling approve() with tokenId = type(uint256).max
            bytes32 collectionKey = bytes32(uint256(uint160(token)));

            if (encodedId == collectionKey) {
                // Special case: tokenId = max is the same wild card approval
                _revert(revertDataPerId);
            }

            (, bytes memory revertDataWildcard) = _updateAllowance(from, collectionKey, msg.sender, amount);

            _handleAllowanceError(revertDataPerId, revertDataWildcard);
        }

        // Execute the ERC1155 transfer
        IERC1155(token).safeTransferFrom(from, to, tokenId, amount, "");
    }

    /**
     * @notice Execute multiple approved ERC721 transfers in a single transaction
     * @dev Each transfer uses the dual-allowance system independently
     * @param transfers Array of ERC721 transfer instructions
     */
    function transferFrom(
        ERC721TransferDetails[] calldata transfers
    ) external override {
        uint256 transfersLength = transfers.length;
        if (transfersLength == 0) {
            revert EmptyArray();
        }

        for (uint256 i = 0; i < transfersLength; i++) {
            transferFrom(transfers[i].from, transfers[i].to, transfers[i].token, transfers[i].tokenId);
        }
    }

    /**
     * @notice Execute multiple approved ERC1155 transfers in a single transaction
     * @dev Each transfer uses the dual-allowance system independently
     * @param transfers Array of multi-token transfer instructions
     */
    function transferFrom(
        MultiTokenTransfer[] calldata transfers
    ) external override {
        uint256 transfersLength = transfers.length;
        if (transfersLength == 0) {
            revert EmptyArray();
        }

        for (uint256 i = 0; i < transfersLength; i++) {
            transferFrom(
                transfers[i].from, transfers[i].to, transfers[i].token, transfers[i].tokenId, transfers[i].amount
            );
        }
    }

    /**
     * @notice Execute approved ERC1155 batch transfer for multiple token IDs to a single recipient
     * @dev Processes each token ID individually through the dual-allowance system
     * @param transfer Batch transfer details containing arrays of token IDs and amounts
     */
    function batchTransferFrom(
        ERC1155BatchTransferDetails calldata transfer
    ) external override {
        uint256 tokenIdsLength = transfer.tokenIds.length;
        if (tokenIdsLength == 0) {
            revert EmptyArray();
        }
        if (tokenIdsLength != transfer.amounts.length) {
            revert InvalidArrayLength();
        }

        // Execute batch by processing each token ID individually to leverage dual-allowance logic
        for (uint256 i = 0; i < tokenIdsLength; i++) {
            transferFrom(transfer.from, transfer.to, transfer.token, transfer.tokenIds[i], transfer.amounts[i]);
        }
    }

    /**
     * @notice Execute multiple token transfers of any type in a single transaction
     * @dev Routes each transfer to the appropriate function based on explicit token type.
     *      Note: This function uses explicit TokenStandard enum instead of tokenId conventions
     *      (tokenId=0 for ERC20) to provide unambiguous routing for mixed-type batches.
     * @param transfers Array of multi-token transfer instructions with explicit token types
     */
    function batchTransferFrom(
        TokenTypeTransfer[] calldata transfers
    ) external override {
        uint256 transfersLength = transfers.length;
        if (transfersLength == 0) {
            revert EmptyArray();
        }

        for (uint256 i = 0; i < transfersLength; i++) {
            TokenTypeTransfer calldata typeTransfer = transfers[i];
            MultiTokenTransfer calldata transfer = typeTransfer.transfer;

            if (typeTransfer.tokenType == TokenStandard.ERC20) {
                // ERC20: Use amount field, tokenId is ignored
                PermitBase.transferFrom(transfer.from, transfer.to, transfer.amount, transfer.token);
            } else if (typeTransfer.tokenType == TokenStandard.ERC721) {
                // ERC721: Use tokenId field, amount should be 1 (but not enforced)
                transferFrom(transfer.from, transfer.to, transfer.token, transfer.tokenId);
            } else if (typeTransfer.tokenType == TokenStandard.ERC1155) {
                // ERC1155: Use both tokenId and amount
                transferFrom(transfer.from, transfer.to, transfer.token, transfer.tokenId, transfer.amount);
            }
        }
    }

    /**
     * @dev Internal helper to handle allowance errors with priority logic
     * @param revertDataPerId Revert data from specific token ID allowance check
     * @param revertDataWildcard Revert data from collection-wide allowance check
     */
    function _handleAllowanceError(bytes memory revertDataPerId, bytes memory revertDataWildcard) internal pure {
        if (revertDataPerId.length == 0 || revertDataWildcard.length == 0) {
            // If any allowance succeeded, no error to handle
            return;
        }

        bytes4 perIdSelector = bytes4(revertDataPerId);

        // Priority error handling: show collection-wide error for insufficient allowance,
        // otherwise show the more specific per-token error
        if (perIdSelector == InsufficientAllowance.selector) {
            _revert(revertDataWildcard);
        } else {
            _revert(revertDataPerId);
        }
    }
}
