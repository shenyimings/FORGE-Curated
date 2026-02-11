// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {DeployParams, DeployResult} from "../Types.sol";
import {IMarketFactory} from "./IMarketFactory.sol";

interface IInterestRateModelFactory is IMarketFactory {
    function deployInterestRateModel(address pool, DeployParams calldata params)
        external
        returns (DeployResult memory);
}
