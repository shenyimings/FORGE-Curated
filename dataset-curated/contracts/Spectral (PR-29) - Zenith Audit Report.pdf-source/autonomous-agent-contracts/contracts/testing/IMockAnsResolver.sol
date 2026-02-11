// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IMockAnsResolver {

    function addr(bytes32 node) external view returns (address);

    function setAddr(bytes32 node, address addr_) external;

    function ans(address addr_) external view returns (bytes32);
}