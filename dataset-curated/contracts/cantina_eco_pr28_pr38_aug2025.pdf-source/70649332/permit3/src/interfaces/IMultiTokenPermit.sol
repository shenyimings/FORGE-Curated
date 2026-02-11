// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMultiTokenPermit
 * @notice Interface for multi-token support (ERC20, ERC721, ERC1155) in the Permit3 system
 * @dev Extends the existing permit system to handle NFTs and semi-fungible tokens
 */
interface IMultiTokenPermit {
    /**
     * @notice Error thrown when array lengths don't match in batch operations
     * @dev Used when tokenIds.length != amounts.length in ERC1155 batch transfers
     */
    error InvalidArrayLength();

    /**
     * @notice Emitted when a multi-token permit is executed for NFTs with specific token IDs
     * @dev Used when tokenKey is a hash of token address and token ID
     * @param owner Token owner address
     * @param tokenKey Token identifier hash (keccak256(token, tokenId))
     * @param spender Spender address
     * @param amount Approved amount
     * @param expiration Expiration timestamp
     * @param timestamp Permit execution timestamp
     */
    event PermitMultiToken(
        address indexed owner,
        bytes32 indexed tokenKey,
        address indexed spender,
        uint160 amount,
        uint48 expiration,
        uint48 timestamp
    );

    /**
     * @notice Enum representing different token standards
     * @param ERC20 Standard fungible tokens with divisible amounts
     * @param ERC721 Non-fungible tokens with unique token IDs
     * @param ERC1155 Semi-fungible tokens with both ID and amount
     */
    enum TokenStandard {
        ERC20,
        ERC721,
        ERC1155
    }

    /**
     * @notice Transfer details for ERC721 tokens
     * @param from Token owner
     * @param to Token recipient
     * @param tokenId The specific NFT token ID
     * @param token The ERC721 contract address
     */
    struct ERC721TransferDetails {
        address from;
        address to;
        uint256 tokenId;
        address token;
    }

    /**
     * @notice Unified transfer details for any token type
     * @param from Token owner
     * @param to Transfer recipient
     * @param token Token contract address
     * @param tokenId Token ID (used for ERC721 and ERC1155, ignored for ERC20)
     * @param amount Transfer amount (used for ERC20 and ERC1155, must be 1 for ERC721)
     */
    struct MultiTokenTransfer {
        address from;
        address to;
        address token;
        uint256 tokenId;
        uint160 amount;
    }

    /**
     * @notice Batch ERC1155 transfer details
     * @param from Token owner
     * @param to Token recipient
     * @param tokenIds Array of ERC1155 token IDs
     * @param amounts Array of amounts corresponding to each token ID
     * @param token The ERC1155 contract address
     */
    struct ERC1155BatchTransferDetails {
        address from;
        address to;
        uint256[] tokenIds;
        uint160[] amounts;
        address token;
    }

    /**
     * @notice Multi-token transfer instruction with explicit token type
     * @param tokenType The type of token (ERC20, ERC721, or ERC1155)
     * @param transfer The unified transfer details struct
     */
    struct TokenTypeTransfer {
        TokenStandard tokenType;
        MultiTokenTransfer transfer;
    }

    /**
     * @notice Query multi-token allowance for a specific token ID
     * @param owner Token owner
     * @param token Token contract address
     * @param spender Approved spender
     * @param tokenId Token ID (0 for ERC20, specific ID for NFT/ERC1155, type(uint256).max for collection-wide
     * wildcard)
     * @return amount Approved amount (max uint160 for unlimited)
     * @return expiration Timestamp when approval expires (0 for no expiration)
     * @return timestamp Timestamp when approval was set
     */
    function allowance(
        address owner,
        address token,
        address spender,
        uint256 tokenId
    ) external view returns (uint160 amount, uint48 expiration, uint48 timestamp);

    /**
     * @notice Approve a spender for a specific token or collection
     * @param token Token contract address
     * @param spender Address to approve
     * @param tokenId Token ID (0 for ERC20, specific ID for NFT/ERC1155, type(uint256).max for collection wildcard)
     * @param amount Amount to approve (ignored for ERC721, used for ERC20/ERC1155)
     * @param expiration Timestamp when approval expires (0 for no expiration)
     */
    function approve(address token, address spender, uint256 tokenId, uint160 amount, uint48 expiration) external;

    /**
     * @notice Execute approved ERC721 token transfer
     * @param from Token owner
     * @param to Transfer recipient
     * @param token ERC721 token address
     * @param tokenId The NFT token ID
     */
    function transferFrom(address from, address to, address token, uint256 tokenId) external;

    /**
     * @notice Execute approved ERC1155 token transfer
     * @param from Token owner
     * @param to Transfer recipient
     * @param token ERC1155 token address
     * @param tokenId The ERC1155 token ID
     * @param amount Transfer amount
     */
    function transferFrom(address from, address to, address token, uint256 tokenId, uint160 amount) external;

    /**
     * @notice Execute approved ERC721 batch transfer
     * @param transfers Array of ERC721 transfer instructions
     */
    function transferFrom(
        ERC721TransferDetails[] calldata transfers
    ) external;

    /**
     * @notice Execute approved ERC1155 batch transfer with multiple token types
     * @param transfers Array of multi-token transfer instructions
     */
    function transferFrom(
        MultiTokenTransfer[] calldata transfers
    ) external;

    /**
     * @notice Execute approved ERC1155 batch transfer for multiple token IDs
     * @param transfer Batch transfer details for multiple token IDs
     */
    function batchTransferFrom(
        ERC1155BatchTransferDetails calldata transfer
    ) external;

    /**
     * @notice Execute multiple token transfers of any type in a single transaction
     * @param transfers Array of multi-token transfer instructions
     */
    function batchTransferFrom(
        TokenTypeTransfer[] calldata transfers
    ) external;
}
