// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// A Mock contract for testing purposes
contract MockOApp {
    mapping(uint32 => bytes) public bytesMapping;

    function setBytes(uint32 _dstEid, bytes calldata _bytes) public {
        bytesMapping[_dstEid] = _bytes;
    }

    receive() external payable {}
}
