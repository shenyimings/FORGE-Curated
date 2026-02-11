// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {INeuStorageV1} from "./INeuStorageV1.sol";

interface INeuStorageV2 is INeuStorageV1 {
    event InitializedStorage(uint256 VERSION, address defaultAdmin, address upgrader, address neuContractAddress, address entitlementContractAddress);
    event InitializedStorageV2(address entitlementContractAddress);
    event DataSaved(uint256 indexed tokenId, bytes data);
}
