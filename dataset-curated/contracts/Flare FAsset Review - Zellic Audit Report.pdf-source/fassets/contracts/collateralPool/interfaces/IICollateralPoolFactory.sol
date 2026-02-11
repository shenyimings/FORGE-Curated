// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import {IICollateralPool} from "./IICollateralPool.sol";
import {IIAssetManager} from "../../assetManager/interfaces/IIAssetManager.sol";
import {IUpgradableContractFactory} from "../../utils/interfaces/IUpgradableContractFactory.sol";
import {AgentSettings} from "../../userInterfaces/data/AgentSettings.sol";



/**
 * @title Collateral pool factory
 */
interface IICollateralPoolFactory is IUpgradableContractFactory {
    /**
     * @notice Creates new collateral pool
     */
    function create(
        IIAssetManager _assetManager,
        address _agentVault,
        AgentSettings.Data memory _settings
    ) external
        returns (IICollateralPool);
}
