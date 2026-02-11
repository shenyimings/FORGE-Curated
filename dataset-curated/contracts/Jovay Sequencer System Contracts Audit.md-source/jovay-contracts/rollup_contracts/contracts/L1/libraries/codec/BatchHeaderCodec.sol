// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

// solhint-disable no-inline-assembly
/// @dev Below is the encoding for `Chunk`, total 40*n+1+m bytes.
/// ```text
///   * Field           Bytes       Type            Index       Comments
///   * numBlocks       1           uint8           0           The number of blocks in this chunk
///   * block[0]        40          BlockContext    1           The first block in this chunk
///   * ......
///   * block[i]        40          BlockContext    40*i+1      The (i+1)'th block in this chunk
///   * ......
///   * block[n-1]      40          BlockContext    40*n-39     The last block in this chunk
///   * l2Transactions  dynamic     bytes           40*n+1      l2txRlpdatalength|l2txRlpdata|l2txRlpdatalength|l2txRlpdata| ...
/// ```
///
/// @dev Below is the encoding for `BlockContext`, total 40 bytes.
/// ```text
///   * Field                   Bytes      Type         Index  Comments
///   * spec_version            4          uint32       0      The spec_version of this block.
///   * blockNumber             8          uint64       4      The height of this block.
///   * timestamp               8          uint64       12     The timestamp of this block.
///   * baseFee                 8          uint64       20     The base fee of this block. Currently, it is always 0, because we disable EIP-1559.
///   * gasLimit                8          uint64       28     The gas limit of this block.
///   * numTransactions         2          uint16       36     The number of transactions in this block, both L1 & L2 txs.
///   * numL1Messages           2          uint16       38     The number of l1 messages in this block.
/// ```

/// @dev Below is the encoding for `BatchHeader` V0, total 89 + ceil(l1MessagePopped / 256) * 32 bytes.
/// ```text
///   * Field                   Bytes       Type        Index   Comments
///   * version                 1           uint8       0       The batch version
///   * batchIndex              8           uint64      1       The index of the batch
///   * L1MsgRollingHash        32          bytes32     9       Number of total L1 message popped after the batch
///   * dataHash                32          bytes32     41      The data hash of the batch
///   * parentBatchHash         32          bytes32     73      The parent batch hash
/// ```
library BatchHeaderCodec {
    /// @dev The length of fixed parts of the batch header.
    uint256 internal constant BATCH_HEADER_FIXED_LENGTH = 105;

    /// @notice Load batch header in calldata to memory.
    /// @param _batchHeader The encoded batch header bytes in calldata.
    /// @return batchPtr The start memory offset of the batch header in memory.
    /// @return length The length in bytes of the batch header.
    function loadAndValidate(bytes calldata _batchHeader) internal pure returns (uint256 batchPtr, uint256 length) {
        length = _batchHeader.length;
        require(length == BATCH_HEADER_FIXED_LENGTH, "INVALID_PARAMETER : batchHeader is invalid");

        // copy batch header to memory.
        assembly {
            batchPtr := mload(0x40)
            calldatacopy(batchPtr, _batchHeader.offset, length)
            mstore(0x40, add(batchPtr, length))
        }
    }

    /// @notice Get the version of the batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _version The version of the batch header.
    function version(uint256 batchPtr) internal pure returns (uint256 _version) {
        assembly {
            _version := shr(248, mload(batchPtr))
        }
    }

        /// @notice Get the batch index of the batch.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _batchIndex The batch index of the batch.
    function batchIndex(uint256 batchPtr) internal pure returns (uint256 _batchIndex) {
        assembly {
            _batchIndex := shr(192, mload(add(batchPtr, 1)))
        }
    }

    /// @notice Get the number of L1 messages popped before this batch.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _l1RollingHash The the number of L1 messages popped before this batch.
    function l1RollingHash(uint256 batchPtr) internal pure returns (bytes32 _l1RollingHash) {
        assembly {
            _l1RollingHash := mload(add(batchPtr, 9))
        }
    }

    /// @notice Get the data hash of the batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _dataHash The data hash of the batch header.
    function dataHash(uint256 batchPtr) internal pure returns (bytes32 _dataHash) {
        assembly {
            _dataHash := mload(add(batchPtr, 41))
        }
    }

    /// @notice Get the parent batch hash of the batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _parentBatchHash The parent batch hash of the batch header.
    function parentBatchHash(uint256 batchPtr) internal pure returns (bytes32 _parentBatchHash) {
        assembly {
            _parentBatchHash := mload(add(batchPtr, 73))
        }
    }

    /// @notice Store the version of batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param _version The version of batch header.
    function storeVersion(uint256 batchPtr, uint256 _version) internal pure {
        assembly {
            mstore8(batchPtr, _version)
        }
    }

    /// @notice Store the batch index of batch header.
    /// @dev Because this function can overwrite the subsequent fields, it must be called before
    /// `storeL1MessagePopped`, `storeTotalL1MessagePopped`, and `storeDataHash`.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param _batchIndex The batch index.
    function storeBatchIndex(uint256 batchPtr, uint256 _batchIndex) internal pure {
        assembly {
            mstore(add(batchPtr, 1), shl(192, _batchIndex))
        }
    }

    /// @notice Store the total number of L1 messages popped after current batch to batch header.
    /// @dev Because this function can overwrite the subsequent fields, it must be called before
    /// `storeDataHash`.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param _l1RollingHash The total number of L1 messages popped after current batch.
    function storeL1RollingHash(uint256 batchPtr, bytes32 _l1RollingHash) internal pure {
        assembly {
            mstore(add(batchPtr, 9), _l1RollingHash)
        }
    }

    /// @notice Store the data hash of batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param _dataHash The data hash.
    function storeDataHash(uint256 batchPtr, bytes32 _dataHash) internal pure {
        assembly {
            mstore(add(batchPtr, 41), _dataHash)
        }
    }

    /// @notice Store the parent batch hash of batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param _parentBatchHash The parent batch hash.
    function storeParentBatchHash(uint256 batchPtr, bytes32 _parentBatchHash) internal pure {
        assembly {
            mstore(add(batchPtr, 73), _parentBatchHash)
        }
    }

    /// @notice Compute the batch hash.
    /// @dev Caller should make sure that the encoded batch header is correct.
    ///
    /// @param batchPtr The memory offset of the encoded batch header.
    /// @param length The length of the batch.
    /// @return _batchHash The hash of the corresponding batch.
    function computeBatchHash(uint256 batchPtr, uint256 length) internal pure returns (bytes32 _batchHash) {
        // in the current version, the hash is: keccak(BatchHeader without timestamp)
        assembly {
            _batchHash := keccak256(batchPtr, length)
        }
    }
}
