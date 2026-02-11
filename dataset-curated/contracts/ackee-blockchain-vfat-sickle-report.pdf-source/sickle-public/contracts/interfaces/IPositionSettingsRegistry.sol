// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    PositionKey,
    PositionSettings
} from "contracts/structs/PositionSettingsStructs.sol";

interface IPositionSettingsRegistry {
    function getPositionSettings(
        PositionKey calldata key
    ) external view returns (PositionSettings memory);

    function setPositionSettings(
        PositionKey calldata key,
        PositionSettings calldata settings
    ) external;

    function validateExitFor(
        PositionKey memory key
    ) external;

    function validateHarvestFor(
        PositionKey memory key
    ) external;

    function validateCompoundFor(
        PositionKey memory key
    ) external;
}
