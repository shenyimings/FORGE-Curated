// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IANSReverseRegistrar {
    function setName(string calldata name) external;
    function getName(address addr) external view returns (string memory name_);
}