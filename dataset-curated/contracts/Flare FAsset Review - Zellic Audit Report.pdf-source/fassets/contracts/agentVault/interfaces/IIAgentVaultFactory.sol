// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import {IIAgentVault} from "./IIAgentVault.sol";
import {IIAssetManager} from "../../assetManager/interfaces/IIAssetManager.sol";
import {IUpgradableContractFactory} from "../../utils/interfaces/IUpgradableContractFactory.sol";


/**
 * @title Agent vault factory
 */
interface IIAgentVaultFactory is IUpgradableContractFactory {
    /**
     * @notice Creates new agent vault
     */
    function create(IIAssetManager _assetManager) external returns (IIAgentVault);
}
