// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {DeployResult} from "../Types.sol";
import {IMarketFactory} from "./IMarketFactory.sol";

interface IPoolFactory is IMarketFactory {
    function deployPool(address underlying, string calldata name, string calldata symbol)
        external
        returns (DeployResult memory);

    function computePoolAddress(
        address marketConfigurator,
        address underlying,
        string calldata name,
        string calldata symbol
    ) external view returns (address);
}
