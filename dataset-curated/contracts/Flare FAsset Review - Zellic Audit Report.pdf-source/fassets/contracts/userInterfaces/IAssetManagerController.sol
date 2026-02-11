// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import {IAssetManager} from "./IAssetManager.sol";


interface IAssetManagerController {
    /**
     * Return the list of all asset managers managed by this controller.
     */
    function getAssetManagers()
        external view
        returns (IAssetManager[] memory);

    /**
     * Check whether the asset manager is managed by this controller.
     * @param _assetManager an asset manager address
     */
    function assetManagerExists(address _assetManager)
        external view
        returns (bool);
}
