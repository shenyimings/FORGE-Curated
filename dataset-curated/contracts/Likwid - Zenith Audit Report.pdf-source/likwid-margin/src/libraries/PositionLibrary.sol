// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity ^0.8.0;

/// @title PositionLibrary
/// @notice A library for creating unique identifiers for positions.
library PositionLibrary {
    /// @notice Calculates a unique position key for an owner and a salt.
    /// @param owner The owner of the position.
    /// @param salt A unique salt for the position.
    /// @return positionKey The unique identifier for the position.
    function calculatePositionKey(address owner, bytes32 salt) internal pure returns (bytes32 positionKey) {
        // This assembly block is a gas-optimized version of:
        // positionKey = keccak256(abi.encodePacked(owner, salt));
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            // Place owner and salt sequentially into memory
            mstore(fmp, owner)
            mstore(add(fmp, 0x20), salt)
            // Hash the 20 bytes of owner and 32 bytes of salt.
            // An address is 20 bytes, but stored in a 32-byte word. It's right-aligned,
            // so we skip the first 12 zero bytes.
            // The total length to hash is 20 (owner) + 32 (salt) = 52 bytes (0x34).
            positionKey := keccak256(add(fmp, 0x0c), 0x34)

            // now clean the memory we used
            mstore(fmp, 0) // fmp held owner
            mstore(add(fmp, 0x20), 0) // fmp held salt
        }
    }

    function calculatePositionKey(address owner, bool isForOne, bytes32 salt)
        internal
        pure
        returns (bytes32 positionKey)
    {
        assembly ("memory-safe") {
            // Get a pointer to some free memory
            let ptr := mload(0x40)

            // abi.encodePacked(owner, isForOne, salt) is 53 bytes:
            // | owner (20 bytes) | isForOne (1 byte) | salt (32 bytes) |

            // We construct the first 32 bytes of the packed data:
            // | owner (20 bytes) | isForOne (1 byte) | salt (first 11 bytes) |
            // Shift owner left by 12 bytes (96 bits) to align it to the start of the word.
            let word1 := shl(96, owner)
            // Shift isForOne left by 11 bytes (88 bits) to place it right after the owner.
            word1 := or(word1, shl(88, isForOne))
            // Take the top 11 bytes (88 bits) of the salt and place them after isForOne.
            word1 := or(word1, shr(168, salt))

            // We construct the second 32 bytes of the packed data:
            // | salt (last 21 bytes) | padding (11 bytes) |
            // Shift the salt left by 88 bits to get the last 21 bytes at the start of the word.
            let word2 := shl(88, salt)

            // Store the two constructed words in memory
            mstore(ptr, word1)
            mstore(add(ptr, 0x20), word2)

            // Hash the 53 bytes of packed data
            positionKey := keccak256(ptr, 53)

            // Clean the memory that we used
            mstore(ptr, 0)
            mstore(add(ptr, 0x20), 0)
        }
    }
}
