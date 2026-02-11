// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProverUtils} from "../../libraries/ProverUtils.sol";
import {IBlockHashProver} from "../../interfaces/IBlockHashProver.sol";
import {IBuffer} from "block-hash-pusher/contracts/interfaces/IBuffer.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";


/// @notice Arbitrum implementation of a child to parent IBlockHashProver.
/// @dev    verifyTargetBlockHash and getTargetBlockHash get block hashes from the block hash buffer at 0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071.
///         See https://github.com/OffchainLabs/block-hash-pusher/blob/a1e26f2e42e6306d1e7f03c5d20fa6aa64ff7a12 for more details.
///         verifyStorageSlot is implemented to work against any parent chain with a standard Ethereum block header and state trie.
contract ChildToParentProver is IBlockHashProver {
    /// @dev Address of the block hash buffer contract
    ///      See https://github.com/OffchainLabs/block-hash-pusher/blob/a1e26f2e42e6306d1e7f03c5d20fa6aa64ff7a12/.env.example#L12
    address public constant blockHashBuffer = 0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071;
    /// @dev Storage slot the buffer contract uses to store block hashes.
    ///      See https://github.com/OffchainLabs/block-hash-pusher/blob/a1e26f2e42e6306d1e7f03c5d20fa6aa64ff7a12/contracts/Buffer.sol#L32
    uint256 public constant blockHashMappingSlot = 51;

    uint256 public immutable homeChainId;

    error CallNotOnHomeChain();
    error CallOnHomeChain();


    constructor(uint256 _homeChainId){
        homeChainId = _homeChainId;

    }
    

    /// @notice Get a parent chain block hash from the buffer at `blockHashBuffer` using a storage proof
    /// @param  homeBlockHash The block hash of the home chain.
    /// @param  input ABI encoded (bytes blockHeader, uint256 targetBlockNumber, bytes accountProof, bytes storageProof)
    function verifyTargetBlockHash(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetBlockHash)
    {
        if(block.chainid == homeChainId) {
            revert CallOnHomeChain();
        }
        // decode the input
        (bytes memory rlpBlockHeader, uint256 targetBlockNumber, bytes memory accountProof, bytes memory storageProof) =
            abi.decode(input, (bytes, uint256, bytes, bytes));

        // calculate the slot based on the provided block number
        // see: https://github.com/OffchainLabs/block-hash-pusher/blob/a1e26f2e42e6306d1e7f03c5d20fa6aa64ff7a12/contracts/Buffer.sol#L32
        uint256 slot = uint256(SlotDerivation.deriveMapping(bytes32(blockHashMappingSlot), targetBlockNumber));

        // verify proofs and get the block hash
        targetBlockHash = ProverUtils.getSlotFromBlockHeader(
            homeBlockHash, rlpBlockHeader, blockHashBuffer, slot, accountProof, storageProof
        );
    }

    /// @notice Get a parent chain block hash from the buffer at `blockHashBuffer`.
    /// @param  input ABI encoded (uint256 targetBlockNumber)
    function getTargetBlockHash(bytes calldata input) external view returns (bytes32 targetBlockHash) {

        if(block.chainid != homeChainId) {
            revert CallNotOnHomeChain();
        }
        //decode the input
        uint256 targetBlockNumber = abi.decode(input, (uint256));

        // get the block hash from the buffer
        targetBlockHash = IBuffer(blockHashBuffer).parentChainBlockHash(targetBlockNumber);
    }

    /// @notice Verify a storage slot given a target chain block hash and a proof.
    /// @param  targetBlockHash The block hash of the target chain.
    /// @param  input ABI encoded (bytes blockHeader, address account, uint256 slot, bytes accountProof, bytes storageProof)
    function verifyStorageSlot(bytes32 targetBlockHash, bytes calldata input)
        external
        pure
        returns (address account, uint256 slot, bytes32 value)
    {
        // decode the input
        bytes memory rlpBlockHeader;
        bytes memory accountProof;
        bytes memory storageProof;
        (rlpBlockHeader, account, slot, accountProof, storageProof) =
            abi.decode(input, (bytes, address, uint256, bytes, bytes));

        // verify proofs and get the value
        value = ProverUtils.getSlotFromBlockHeader(
            targetBlockHash, rlpBlockHeader, account, slot, accountProof, storageProof
        );
    }

    /// @inheritdoc IBlockHashProver
    function version() external pure returns (uint256) {
        return 1;
    }
}
