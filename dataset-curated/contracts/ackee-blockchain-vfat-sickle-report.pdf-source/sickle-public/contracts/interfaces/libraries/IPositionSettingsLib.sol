// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Farm } from "contracts/structs/FarmStrategyStructs.sol";
import { PositionSettings } from "contracts/structs/PositionSettingsStructs.sol";
import { IPositionSettingsRegistry } from
    "contracts/interfaces/IPositionSettingsRegistry.sol";

interface IPositionSettingsLib {
    function setPositionSettings(
        IPositionSettingsRegistry nftSettingsRegistry,
        Farm calldata farm,
        PositionSettings calldata settings
    ) external;
}
