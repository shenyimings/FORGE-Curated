// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPublicAllocatorHandler {
    function reallocateTo(uint8 i, uint8 j, uint128[4] memory amounts) external;
}
