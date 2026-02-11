// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SickleFactory, Sickle } from "contracts/SickleFactory.sol";
import { ConnectorRegistry } from "contracts/ConnectorRegistry.sol";
import { AccessControlModule } from "contracts/modules/AccessControlModule.sol";

contract StrategyModule is AccessControlModule {
    ConnectorRegistry public immutable connectorRegistry;

    constructor(
        SickleFactory factory,
        ConnectorRegistry connectorRegistry_
    ) AccessControlModule(factory) {
        connectorRegistry = connectorRegistry_;
    }

    function getSickle(address owner) public view returns (Sickle) {
        Sickle sickle = Sickle(payable(factory.sickles(owner)));
        if (address(sickle) == address(0)) {
            revert SickleNotDeployed();
        }
        return sickle;
    }

    function getOrDeploySickle(
        address owner,
        address approved,
        bytes32 referralCode
    ) public returns (Sickle) {
        return
            Sickle(payable(factory.getOrDeploy(owner, approved, referralCode)));
    }
}
