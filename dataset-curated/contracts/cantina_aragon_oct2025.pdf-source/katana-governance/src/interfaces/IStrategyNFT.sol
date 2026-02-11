// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IStrategy } from "./IStrategy.sol";

interface IStrategyNFT is IStrategy {
    error MasterTokenAlreadySet();
    error MasterTokenNotSet();

    /// @notice Emitted when an existing token is deposited by merging to master token
    /// @param tokenId The token ID that was merged into the master token
    /// @param masterTokenId The master token that received the merge
    event TokenIdDeposited(uint256 indexed tokenId, uint256 indexed masterTokenId);

    /// @notice Emitted when the strategy receives and sets its master token
    /// @param masterTokenId The master token ID that was set
    event MasterTokenReceived(uint256 indexed masterTokenId);

    /// @notice Handles deposit of existing token by merging to master token
    /// @param _tokenId The token ID to merge
    function depositTokenId(uint256 _tokenId) external;

    /// @notice Receives master token id from vault. Must be called
    ///         in the same tx after tokenId is transferred to strategy.
    function receiveMasterToken(uint256 _tokenId) external;
}
