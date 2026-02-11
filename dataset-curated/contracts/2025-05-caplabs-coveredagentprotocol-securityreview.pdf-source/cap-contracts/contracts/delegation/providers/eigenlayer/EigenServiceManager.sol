// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IAVSDirectory } from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import { IRewardsCoordinator } from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import { IRegistryCoordinator } from "eigenlayer/src/interfaces/IRegistryCoordinator.sol";
import { IStakeRegistry } from "eigenlayer/src/interfaces/IStakeRegistry.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ServiceManagerBase } from "eigenlayer/src/ServiceManagerBase.sol";

contract EigenServiceManager is ServiceManagerBase {
    constructor(
        IAVSDirectory _avsDirectory,
        IRewardsCoordinator _rewardsCoordinator,
        IRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry
    ) ServiceManagerBase(_avsDirectory, _rewardsCoordinator, _registryCoordinator, _stakeRegistry) {
        _disableInitializers();
    }

    /// @notice This function initializes the contract's owner and the rewards initiator.
    /// @param initialOwner The address to be set as the initial owner of the contract.
    /// @param rewardsInitiator The address to be set as the rewards initiator for the contract.
    function initialize(address initialOwner, address rewardsInitiator) external initializer {
        __ServiceManagerBase_init(initialOwner, rewardsInitiator);
    }
}
