// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ICustomConnectorRegistry } from "contracts/ConnectorRegistry.sol";
import { NuriGaugeConnector } from
    "contracts/connectors/nuri/NuriGaugeConnector.sol";
import { NuriV3Connector } from "contracts/connectors/nuri/NuriV3Connector.sol";
import { IGaugeRegistryVoter } from "contracts/connectors/GaugeRegistry.sol";
import { IGaugeV2 } from "contracts/interfaces/external/ramses/IGaugeV2.sol";

interface INuriPairFactory {
    function isPair(address pair) external view returns (bool);
}

contract NuriGaugeRegistry is ICustomConnectorRegistry {
    IGaugeRegistryVoter public immutable voter;
    NuriGaugeConnector public immutable nuriGaugeConnector;
    INuriPairFactory public immutable nuriPairFactory;
    NuriV3Connector public immutable nuriV3Connector;
    address public immutable nuriCLGaugeFactory;

    constructor(
        IGaugeRegistryVoter voter_,
        NuriGaugeConnector nuriGaugeConnector_,
        INuriPairFactory nuriPairFactory_,
        NuriV3Connector nuriV3Connector_,
        address nuriCLGaugeFactory_
    ) {
        voter = voter_;
        nuriGaugeConnector = nuriGaugeConnector_;
        nuriPairFactory = nuriPairFactory_;
        nuriV3Connector = nuriV3Connector_;
        nuriCLGaugeFactory = nuriCLGaugeFactory_;
    }

    function connectorOf(address target)
        external
        view
        override
        returns (address)
    {
        if (voter.isGauge(target)) {
            if (nuriPairFactory.isPair(voter.poolForGauge(target))) {
                return address(nuriGaugeConnector);
            }
            address gaugeFactory = IGaugeV2(target).gaugeFactory();
            if (gaugeFactory == nuriCLGaugeFactory) {
                return address(nuriV3Connector);
            }
        }

        return address(0);
    }
}
