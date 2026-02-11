// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

library Bytes {
    function sequentialByteArrayOfSize(uint256 length) internal pure returns (bytes memory data) {
        data = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            data[i] = bytes1(uint8(i));
        }
    }
}
