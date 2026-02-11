// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Farm } from "contracts/structs/FarmStrategyStructs.sol";
import {
    PositionKey,
    PositionSettings
} from "contracts/structs/PositionSettingsStructs.sol";
import { IPositionSettingsRegistry } from
    "contracts/interfaces/IPositionSettingsRegistry.sol";
import { Sickle } from "contracts/Sickle.sol";
import { IPositionSettingsLib } from
    "contracts/interfaces/libraries/IPositionSettingsLib.sol";

contract PositionSettingsLib is IPositionSettingsLib {
    function setPositionSettings(
        IPositionSettingsRegistry positionSettingsRegistry,
        Farm calldata farm,
        PositionSettings calldata settings
    ) external {
        PositionKey memory key = PositionKey(
            Sickle(payable(address(this))), farm.stakingContract, farm.poolIndex
        );
        positionSettingsRegistry.setPositionSettings(key, settings);
    }
}
