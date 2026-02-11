/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title AddressConverter
 * @notice Utility library for converting between address and bytes32 types
 * @dev Provides simple functions to convert between address (20 bytes) and bytes32 (32 bytes)
 */
library AddressConverter {
    error InvalidAddress(bytes32 value);

    /**
     * @notice Convert an Ethereum address to bytes32
     * @dev Pads the 20-byte address to 32 bytes by converting to uint160, then uint256, then bytes32
     * @param addr The address to convert
     * @return The bytes32 representation of the address
     */
    function toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /**
     * @notice Convert bytes32 to an Ethereum address
     * @dev Truncates the 32-byte value to 20 bytes by converting to uint256, then uint160, then address
     * @param b The bytes32 value to convert
     * @return The address representation of the bytes32 value
     */
    function toAddress(bytes32 b) internal pure returns (address) {
        if (!isValidAddress(b)) {
            revert InvalidAddress(b);
        }

        return address(uint160(uint256(b)));
    }

    /**
     * @notice Check if a bytes32 value represents a valid Ethereum address
     * @dev An Ethereum address must have the top 12 bytes as zero
     * @param b The bytes32 value to check
     * @return True if the bytes32 value can be safely converted to an Ethereum address
     */
    function isValidAddress(bytes32 b) internal pure returns (bool) {
        // The top 12 bytes must be zero for a valid Ethereum address
        return uint256(b) >> 160 == 0;
    }
}
