// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

struct BaseParams {
    address addr;
    uint256 version;
    bytes32 contractType;
    bytes serializedParams;
}

struct BaseState {
    BaseParams baseParams;
}
