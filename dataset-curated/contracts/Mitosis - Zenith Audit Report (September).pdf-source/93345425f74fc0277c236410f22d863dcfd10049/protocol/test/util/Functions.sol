// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

// forgefmt: disable-start
function cat(string memory v1, string memory v2) pure returns (string memory) { return string.concat(v1, v2); }
function cat(string memory v1, string memory v2, string memory v3) pure returns (string memory) { return string.concat(v1, v2, v3); }
function cat(string memory v1, string memory v2, string memory v3, string memory v4) pure returns (string memory) { return string.concat(v1, v2, v3, v4); }
function cat(string memory v1, string memory v2, string memory v3, string memory v4, string memory v5) pure returns (string memory) { return string.concat(v1, v2, v3, v4, v5); }
function pack(bytes memory a, bytes memory b) pure returns (bytes memory) { return abi.encodePacked(a, b); }
function salt(string memory v) pure returns (bytes32) { return keccak256(abi.encodePacked(v)); }
function toAddr(bytes32 a) pure returns (address) { return address(uint160(uint256(a))); }
function toBz32(address a) pure returns (bytes32) { return bytes32(uint256(uint160(a))); }
// forgefmt: disable-end
