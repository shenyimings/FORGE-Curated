// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {MultiCall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";

struct TokenData {
    address token;
    uint256 balance;
    uint256 leftoverBalance;
    uint256 numSplits;
    bool claimRewards;
}

struct RouterResult {
    uint256 amount;
    uint256 minAmount;
    MultiCall[] calls;
}

interface IGearboxRouter {
    function routeOpenManyToOne(address creditManager, address target, uint256 slippage, TokenData[] calldata tData)
        external
        returns (RouterResult memory);
}
