// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundaiton, 2025.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {BotState, ConnectedBotState, ZapperState} from "../types/PeripheryState.sol";

interface IPeripheryCompressor is IVersion {
    function getZappers(address marketConfigurator, address pool) external view returns (ZapperState[] memory);

    function getBots(address marketConfigurator) external view returns (BotState[] memory);

    function getConnectedBots(address marketConfigurator, address creditAccount)
        external
        view
        returns (ConnectedBotState[] memory);
}
