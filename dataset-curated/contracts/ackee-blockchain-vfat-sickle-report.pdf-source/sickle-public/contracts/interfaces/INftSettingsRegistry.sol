// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { NftKey, NftSettings } from "contracts/structs/NftSettingsStructs.sol";

interface INftSettingsRegistry {
    function getNftSettings(
        NftKey calldata key
    ) external view returns (NftSettings memory);

    function setNftSettings(
        NftKey calldata key,
        NftSettings calldata settings
    ) external;

    function resetNftSettings(
        NftKey calldata oldKey,
        NftKey calldata newKey,
        NftSettings calldata settings
    ) external;

    function validateRebalanceFor(
        NftKey memory key
    ) external;

    function validateExitFor(
        NftKey memory key
    ) external;

    function validateHarvestFor(
        NftKey memory key
    ) external;

    function validateCompoundFor(
        NftKey memory key
    ) external;
}
