// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity ^0.8.0;

library TimeLibrary {
    function getTimeElapsed(uint32 blockTimestampLast) internal view returns (uint256 timeElapsed) {
        uint32 blockTimestamp = uint32(block.timestamp);
        if (blockTimestampLast <= blockTimestamp) {
            timeElapsed = uint256(blockTimestamp - blockTimestampLast);
        } else {
            timeElapsed = uint256(2 ** 32 - blockTimestampLast + blockTimestamp);
        }
    }
}
