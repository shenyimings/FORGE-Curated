// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {BaseParams} from "./BaseState.sol";
import {TokenData} from "./TokenData.sol";

struct BotState {
    BaseParams baseParams;
    uint192 requiredPermissions;
}

struct ConnectedBotState {
    BaseParams baseParams;
    uint192 requiredPermissions;
    address creditAccount;
    uint192 permissions;
    bool forbidden;
}

struct ZapperState {
    BaseParams baseParams;
    TokenData tokenIn;
    TokenData tokenOut;
}
