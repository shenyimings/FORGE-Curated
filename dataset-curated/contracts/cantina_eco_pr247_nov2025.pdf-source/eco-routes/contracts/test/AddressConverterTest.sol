// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AddressConverter} from "../libs/AddressConverter.sol";

/**
 * @title AddressConverterTest
 * @notice Test contract that exposes AddressConverter library functions for testing
 */
contract AddressConverterTest {
    /**
     * @notice Convert an Ethereum address to bytes32
     * @param addr The address to convert
     * @return The bytes32 representation of the address
     */
    function toBytes32(address addr) external pure returns (bytes32) {
        return AddressConverter.toBytes32(addr);
    }

    /**
     * @notice Convert bytes32 to an Ethereum address
     * @param b The bytes32 value to convert
     * @return The address representation of the bytes32 value
     */
    function toAddress(bytes32 b) external pure returns (address) {
        return AddressConverter.toAddress(b);
    }

    /**
     * @notice Check if a bytes32 value represents a valid Ethereum address
     * @param b The bytes32 value to check
     * @return True if the bytes32 value can be safely converted to an Ethereum address
     */
    function isValidEthereumAddress(bytes32 b) external pure returns (bool) {
        return AddressConverter.isValidAddress(b);
    }

    // The toBytes32Array function has been removed as the corresponding
    // library function no longer exists

    // The toAddressArray function has been removed as the corresponding
    // library function no longer exists
}
