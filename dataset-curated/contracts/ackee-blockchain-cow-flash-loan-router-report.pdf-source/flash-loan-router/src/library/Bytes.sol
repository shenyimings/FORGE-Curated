// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

/// @title Bytes Library
/// @author CoW DAO developers
/// @notice Helper functions to handle bytes array at a raw-memory level.
library Bytes {
    uint256 private constant BYTES_LENGTH_SIZE = 32;

    /// @notice Allocate a bytes array in memory with arbitrary data in it.
    /// This is cheaper than `new bytes(length)` because it doesn't zero the
    /// content of the array. It is supposed to be used when the newly allocated
    /// memory will be fully overwritten at a later step.
    /// @param length The length of the bytes array to create.
    /// @return array A bytes array of the specified length with unknown data in
    /// it.
    function allocate(uint256 length) internal pure returns (bytes memory array) {
        // <https://docs.soliditylang.org/en/v0.8.26/internals/layout_in_memory.html>
        uint256 freeMemoryPointer;
        assembly ("memory-safe") {
            freeMemoryPointer := mload(0x40)
        }

        // Add to the free memory pointer the size of the array and the bytes
        // for storing the array length.
        uint256 updatedFreeMemoryPointer = freeMemoryPointer + BYTES_LENGTH_SIZE + length;
        assembly ("memory-safe") {
            // The array will be located at the first free available memory.
            array := freeMemoryPointer
            // The first 32 bytes are the array length.
            mstore(array, length)
            mstore(0x40, updatedFreeMemoryPointer)
        }
    }

    /// @notice Return the location of the content of an array in memory. Note
    /// that the array length is not part of the content.
    /// @param array A bytes array.
    /// @return ref The location in memory of the content of the array.
    function memoryPointerToContent(bytes memory array) internal pure returns (uint256 ref) {
        // Unchecked: arrays allocated by Solidity cannot cause an overflow,
        // since a transaction would run out of gas long before reaching the
        // length needed for an overflow. Arrays that were manually allocated
        // through assembly may cause an overflow, but any attempt to read from
        // or write to them would cause an out-of-gas revert.

        assembly ("memory-safe") {
            ref := add(array, BYTES_LENGTH_SIZE)
        }
    }
}
