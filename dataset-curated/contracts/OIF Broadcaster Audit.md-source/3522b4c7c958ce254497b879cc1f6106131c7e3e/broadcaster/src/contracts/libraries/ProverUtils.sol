// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Lib_SecureMerkleTrie} from "@eth-optimism/contracts/libraries/trie/Lib_SecureMerkleTrie.sol";
import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";
import {Memory} from "@openzeppelin/contracts/utils/Memory.sol";

/// @notice Base contract for IBlockHashProver contracts. Contains helpers for verifying block headers and MPT proofs.
library ProverUtils {
    using Memory for bytes;
    using RLP for Memory.Slice;

    /// @dev The index of the state root in the RLP encoded block header.
    ///      For reference on the block structure, see:
    ///      https://github.com/ethereum/go-ethereum/blob/35dd84ce2999ecf5ca8ace50a4d1a6abc231c370/core/types/block.go#L75-L109
    uint256 internal constant STATE_ROOT_INDEX = 3;
    /// @dev The index of the code hash in the RLP encoded account data.
    ///      For reference on the account structure, see:
    ///      https://github.com/ethereum/go-ethereum/blob/35dd84ce2999ecf5ca8ace50a4d1a6abc231c370/core/types/state_account.go#L31-L36
    uint256 internal constant CODE_HASH_INDEX = 3;
    /// @dev The index of the storage root in the RLP encoded account data.
    ///      For reference on the account structure, see:
    ///      https://github.com/ethereum/go-ethereum/blob/35dd84ce2999ecf5ca8ace50a4d1a6abc231c370/core/types/state_account.go#L31-L36
    uint256 internal constant STORAGE_ROOT_INDEX = 2;

    /// @dev Extracts the state root from the RLP encoded block header.
    ///      Assumes the state root is the fourth item in the block header.
    /// @param rlpBlockHeader The RLP encoded block header.
    /// @return stateRoot The state root of the block.
    function extractStateRootFromBlockHeader(bytes memory rlpBlockHeader) internal pure returns (bytes32 stateRoot) {
        // extract the state root from the block header
        stateRoot = RLP.readList(rlpBlockHeader.asSlice())[STATE_ROOT_INDEX].readBytes32();
    }

    /// @dev Extracts the code hash from the RLP encoded account data.
    ///      Assumes the code hash is the fourth item in the account data.
    /// @param accountData The RLP encoded account data.
    /// @return codeHash The code hash of the account.
    function extractCodeHashFromAccountData(bytes memory accountData) internal pure returns (bytes32 codeHash) {
        codeHash = RLP.readList(accountData.asSlice())[CODE_HASH_INDEX].readBytes32();
    }

    /// @dev Extracts the storage root from the RLP encoded account data.
    ///      Assumes the storage root is the third item in the account data.
    /// @param accountData The RLP encoded account data.
    /// @return storageRoot The storage root of the account.
    function extractStorageRootFromAccountData(bytes memory accountData) internal pure returns (bytes32 storageRoot) {
        storageRoot = RLP.readList(accountData.asSlice())[STORAGE_ROOT_INDEX].readBytes32();
    }

    /// @dev Given a block hash, RLP encoded block header, account address, storage slot, and the corresponding proofs,
    ///      verifies and returns the value of the storage slot at that block.
    ///      Reverts if the block hash does not match the block header, or if the MPT proofs are invalid.
    /// @param blockHash The hash of the block.
    /// @param rlpBlockHeader The RLP encoded block header.
    /// @param account The account to get the storage slot for.
    /// @param slot The storage slot to get.
    /// @param rlpAccountProof The RLP encoded proof for the account.
    /// @param rlpStorageProof The RLP encoded proof for the storage slot.
    /// @return value The value of the storage slot at the given block.
    function getSlotFromBlockHeader(
        bytes32 blockHash,
        bytes memory rlpBlockHeader,
        address account,
        uint256 slot,
        bytes memory rlpAccountProof,
        bytes memory rlpStorageProof
    ) internal pure returns (bytes32 value) {
        // verify the block header
        require(blockHash == keccak256(rlpBlockHeader), "Block hash does not match");

        // extract the state root from the block header
        bytes32 stateRoot = extractStateRootFromBlockHeader(rlpBlockHeader);

        // verify the account and storage proofs
        value = getStorageSlotFromStateRoot(stateRoot, rlpAccountProof, rlpStorageProof, account, slot);
    }

    /// @dev Given a state root and RLP encoded account proof, verifies the proof and returns the RLP encoded account data.
    /// @param stateRoot The state root of the block.
    /// @param rlpAccountProof The RLP encoded proof for the account.
    /// @param account The account to get the data for.
    /// @return accountExists A boolean indicating if the account exists.
    /// @return accountData The RLP encoded account data.
    function getAccountDataFromStateRoot(bytes32 stateRoot, bytes memory rlpAccountProof, address account)
        internal
        pure
        returns (bool accountExists, bytes memory accountData)
    {

        (accountExists, accountData) = Lib_SecureMerkleTrie.get(abi.encodePacked(account), rlpAccountProof, stateRoot);
    }

    /// @dev Given a state root, RLP encoded account proof, RLP encoded storage proof, account address, and storage slot,
    ///      verifies and returns the value of the storage slot at that state root.
    ///      Reverts if the account does not exist or if the MPT proofs are invalid.
    ///      Will return 0 if the slot does not exist.
    /// @param stateRoot The state root of the block.
    /// @param rlpAccountProof The RLP encoded proof for the account.
    /// @param rlpStorageProof The RLP encoded proof for the storage slot.
    /// @param account The account to get the storage slot for.
    /// @param slot The storage slot to get.
    /// @return value The value of the storage slot at the given state root.
    function getStorageSlotFromStateRoot(
        bytes32 stateRoot,
        bytes memory rlpAccountProof,
        bytes memory rlpStorageProof,
        address account,
        uint256 slot
    ) internal pure returns (bytes32 value) {
        // verify the proof
        (bool accountExists, bytes memory accountValue) =
            getAccountDataFromStateRoot(stateRoot, rlpAccountProof, account);
    

        require(accountExists, "Account does not exist");

        (bool slotExists, bytes memory slotValue) =
            Lib_SecureMerkleTrie.get(abi.encode(slot), rlpStorageProof, extractStorageRootFromAccountData(accountValue));
    

        // decode the slot value
        if (slotExists) value = slotValue.asSlice().readBytes32();
    }
}
