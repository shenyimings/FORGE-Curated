// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {IDeployerTrait} from "./base/IDeployerTrait.sol";

interface IMarketConfiguratorFactory is IVersion, IDeployerTrait {
    // ------ //
    // EVENTS //
    // ------ //

    event CreateMarketConfigurator(address indexed marketConfigurator, string name);
    event ShutdownMarketConfigurator(address indexed marketConfigurator);

    // ------ //
    // ERRORS //
    // ------ //

    error AddressIsNotMarketConfiguratorException(address addr);
    error CallerIsNotCrossChainGovernanceException(address caller);
    error CallerIsNotMarketConfiguratorException(address caller);
    error CallerIsNotMarketConfiguratorAdminException(address caller);
    error CantShutdownMarketConfiguratorException();
    error MarketConfiguratorIsAlreadyAddedException(address marketConfigurator);
    error MarketConfiguratorIsAlreadyShutdownException(address marketConfigruator);

    function isMarketConfigurator(address account) external view returns (bool);

    function getMarketConfigurators() external view returns (address[] memory);

    function getShutdownMarketConfigurators() external view returns (address[] memory);

    function createMarketConfigurator(
        address admin,
        address emergencyAdmin,
        address adminFeeTreasury,
        string calldata curatorName,
        bool deployGovernor
    ) external returns (address marketConfigurator);

    function shutdownMarketConfigurator(address marketConfigurator) external;

    function addMarketConfigurator(address marketConfigurator) external;
}
