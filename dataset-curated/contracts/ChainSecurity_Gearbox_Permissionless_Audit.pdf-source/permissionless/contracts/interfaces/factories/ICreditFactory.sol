// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Call, DeployResult} from "../Types.sol";
import {IFactory} from "./IFactory.sol";

interface ICreditFactory is IFactory {
    function deployCreditSuite(address pool, bytes calldata encodedParams) external returns (DeployResult memory);

    function computeCreditManagerAddress(address marketConfigurator, address pool, bytes calldata encodedParams)
        external
        view
        returns (address);

    // ------------ //
    // CREDIT HOOKS //
    // ------------ //

    function onUpdatePriceOracle(address creditManager, address newPriceOracle, address oldPriceOracle)
        external
        returns (Call[] memory calls);

    function onUpdateLossPolicy(address creditManager, address newLossPolicy, address oldLossPolicy)
        external
        returns (Call[] memory calls);
}
