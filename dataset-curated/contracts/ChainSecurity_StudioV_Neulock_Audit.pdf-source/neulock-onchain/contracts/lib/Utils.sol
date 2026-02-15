// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

library Bytes8Utils {
    function toString(bytes8 data) internal pure returns (string memory) {
        uint8 i = 0;

        unchecked {
            while(i < 8 && data[i] != 0) {
                i++;
            }
        }

        bytes memory bytesArray = new bytes(i);

        for (uint256 j = 0; j < i; j++) {
            bytesArray[j] = data[j];
        }

        return string(bytesArray);
    }
}