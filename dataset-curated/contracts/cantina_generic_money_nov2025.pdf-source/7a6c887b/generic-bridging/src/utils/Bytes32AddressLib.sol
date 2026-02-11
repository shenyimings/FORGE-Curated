// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/// @notice Library for converting between addresses and bytes32 values.
library Bytes32AddressLib {
    function toAddressFromLowBytes(bytes32 bytesValue) internal pure returns (address) {
        return address(uint160(uint256(bytesValue)));
    }

    function toBytes32WithLowAddress(address addressValue) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addressValue)));
    }
}
