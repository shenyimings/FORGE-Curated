// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {INeuStorageV2} from "./INeuStorageV2.sol";

interface INeuStorageV3 is INeuStorageV2 {
    event InitializedStorage(uint256 version, address defaultAdmin, address upgrader, address neuContractAddress);
    event DataSavedV3(address indexed user, bytes data);

    function saveDataV3(address entitlementContract, bytes memory data) external;
}
