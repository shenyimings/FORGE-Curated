// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { VaultConfig } from "../../../contracts/deploy/interfaces/DeployConfigs.sol";

contract VaultConfigHelpers {
    function _getAssetIndex(VaultConfig memory vault, address asset) internal pure returns (uint256) {
        for (uint256 i = 0; i < vault.assets.length; i++) {
            if (vault.assets[i] == asset) {
                return i;
            }
        }

        revert("Asset not found");
    }
}
