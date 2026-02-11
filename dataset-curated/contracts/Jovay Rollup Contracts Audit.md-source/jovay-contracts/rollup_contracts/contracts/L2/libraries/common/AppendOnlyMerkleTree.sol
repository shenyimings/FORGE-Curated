// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

abstract contract AppendOnlyMerkleTree {
    /// @dev The maximum height of the withdraw merkle tree.
    uint256 private constant MAX_TREE_HEIGHT = 40;

    /// @notice The merkle root of the current merkle tree.
    /// @dev This is actual equal to `branches[n]`.
    bytes32 internal _msgRoot;

    /// @notice The next unused message index.
    uint256 internal _nextMsgIndex;

    /// @notice The list of zero hash in each height.
    bytes32[MAX_TREE_HEIGHT] private _zeroHashes;

    /// @notice The list of minimum merkle proofs needed to compute next root.
    /// @dev Only first `n` elements are used, where `n` is the minimum value that `2^{n-1} >= currentMaxNonce + 1`.
    /// It means we only use `currentMaxNonce + 1` leaf nodes to construct the merkle tree.
    bytes32[MAX_TREE_HEIGHT] public _branches;

    function _initializeMerkleTree() internal {
        // Compute hashes in empty sparse Merkle tree
        for (uint256 height = 0; height + 1 < MAX_TREE_HEIGHT; height++) {
            _zeroHashes[height + 1] = _efficientHash(_zeroHashes[height], _zeroHashes[height]);
        }
    }

    function _appendMsgHash(bytes32 msgHash) internal returns (uint256, bytes32) {
        // can called only after initialize
        // require(_zeroHashes[1] != bytes32(0), "call before initialization");

        uint256 currentMsgIndex = _nextMsgIndex;
        bytes32 hash = msgHash;
        uint256 height = 0;

        while (currentMsgIndex != 0) {
            if (currentMsgIndex % 2 == 0) {
                // it may be used in next round.
                _branches[height] = hash;
                // it's a left child, the right child must be null
                hash = _efficientHash(hash, _zeroHashes[height]);
            } else {
                // it's a right child, use previously computed hash
                hash = _efficientHash(_branches[height], hash);
            }
            unchecked {
                height += 1;
            }
            currentMsgIndex >>= 1;
        }

        _branches[height] = hash;
        _msgRoot = hash;

        currentMsgIndex = _nextMsgIndex;
        unchecked {
            _nextMsgIndex = currentMsgIndex + 1;
        }

        return (currentMsgIndex, hash);
    }

    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}
