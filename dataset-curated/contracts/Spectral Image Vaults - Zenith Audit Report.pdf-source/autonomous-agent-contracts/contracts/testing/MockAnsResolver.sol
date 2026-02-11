// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

contract MockAnsResolver {
    mapping(bytes32 => address) public addresses;
    mapping(address => bytes32) public names;

    function addr(bytes32 node) external view returns (address) {
        return addresses[node];
    }

    function setAddr(bytes32 node, address addr_) external {
        addresses[node] = addr_;
        names[addr_] = node;
    }

    function ans(address addr_) external view returns (bytes32) {
        return names[addr_];
    }
}