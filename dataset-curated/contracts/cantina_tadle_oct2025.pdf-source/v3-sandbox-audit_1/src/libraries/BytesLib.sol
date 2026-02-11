// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title BytesLib
 * @dev Library for handling byte array operations
 * @notice Provides utility functions for extracting data from byte arrays
 */
library BytesLib {
    /**
     * @dev Extracts an address from a bytes array at a specific position
     * @param _bytes The byte array to extract from
     * @param _start The starting position in the byte array
     * @return The extracted address
     * @notice Requires exactly 20 bytes for address extraction
     * @custom:security Validates array bounds to prevent buffer overflow
     */
    function toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
        require(_start + 20 >= _start, "BytesLib: start position overflow");
        require(_bytes.length >= _start + 20, "BytesLib: insufficient bytes for address extraction");
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }
}
