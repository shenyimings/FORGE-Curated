// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

/// @title IRollup
/// @notice The interface for Rollup_ols.sol.
interface IRollup {
    event BlobDataHash(bytes32 indexed batchDataHash);
    /// @notice Emitted when a new batch is committed.
    /// @param batchIndex The index of the batch.
    /// @param batchHash The hash of the batch.
    event CommitBatch(uint256 indexed batchIndex, bytes32 indexed batchHash);

    /// @notice revert a pending batch.
    /// @param batchIndex The index of the batch.
    event RevertBatch(uint256 indexed batchIndex);

    /// @notice Emitted when a batch is verified.
    /// @param proveType The prove type of verified.
    /// @param batchIndex The index of the batch.
    /// @param batchHash The hash of the batch
    /// @param stateRoot The state root on layer 2 after this batch.
    /// @param l2MsgRoot The merkle root on layer2 after this batch.
    event VerifyBatch(uint8 proveType, uint256 indexed batchIndex, bytes32 indexed batchHash, bytes32 stateRoot, bytes32 l2MsgRoot);
    
    /// @notice get l2MsgRoot of batchIndex
    /// @param _batchIndex. the index of l2MsgRoot;
    function getL2MsgRoot(uint256 _batchIndex) external view returns (bytes32);

    /// @notice Commit a batch of layer-2 transactions on layer 1.
    /// @param _version The version of current batch.
    /// @param _batchIndex The batch index will be committed.
    /// @param _totalL1MessagePopped The total l1 msg count consumed after this batch.
    function commitBatch(
        uint8 _version,
        uint256 _batchIndex,
        uint256 _totalL1MessagePopped
    ) external;


    /// @notice Verify next committed batch on layer 1.
    ///
    /// @param _prove_type The verify proof type (0-zk, 1-tee).
    /// @param _batchHeader The header of current batch, see the comments of `BatchHeaderV0Codec`.
    /// @param _postStateRoot The state root after current batch.
    /// @param _l2MsgRoot The withdraw trie root after current batch.
    /// @param _proof The proof for current batch.
    function verifyBatch(
        uint8 _prove_type, 
        bytes calldata _batchHeader,
        bytes32 _postStateRoot,
        bytes32 _l2MsgRoot,
        bytes calldata _proof        
    ) external;

    /// @notice Revert latest commit and verified batch to newbatchindex(<= latest_commit_index && <= latest_verified_index )
    ///
    /// @param _newLastBatchIndex The latest batch will not be reverted.
    function revertBatches(uint256 _newLastBatchIndex) external;
}