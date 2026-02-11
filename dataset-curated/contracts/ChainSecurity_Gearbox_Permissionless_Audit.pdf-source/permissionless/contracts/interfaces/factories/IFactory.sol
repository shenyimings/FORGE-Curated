// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {IDeployerTrait} from "../base/IDeployerTrait.sol";
import {Call} from "../Types.sol";

interface IFactory is IVersion, IDeployerTrait {
    // ------ //
    // ERRORS //
    // ------ //

    error CallerIsNotMarketConfiguratorException(address caller);
    error ForbiddenConfigurationCallException(bytes4 selector);
    error ForbiddenEmergencyConfigurationCallException(bytes4 selector);
    error InvalidConstructorParamsException();

    // --------------- //
    // STATE VARIABLES //
    // --------------- //

    function marketConfiguratorFactory() external view returns (address);

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function configure(address target, bytes calldata callData) external returns (Call[] memory calls);

    function emergencyConfigure(address target, bytes calldata callData) external returns (Call[] memory calls);
}
