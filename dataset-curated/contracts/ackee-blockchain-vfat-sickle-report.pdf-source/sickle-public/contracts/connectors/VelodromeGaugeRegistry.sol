// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ICustomConnectorRegistry } from "contracts/ConnectorRegistry.sol";
import { AerodromeGaugeConnector } from
    "contracts/connectors/AerodromeGaugeConnector.sol";
import { VelodromeSlipstreamGaugeConnector } from
    "contracts/connectors/VelodromeSlipstreamGaugeConnector.sol";
import { IGaugeRegistryVoter } from "contracts/connectors/GaugeRegistry.sol";

interface IPairFactory {
    function isPair(address pair) external view returns (bool);
}

contract VelodromeGaugeRegistry is ICustomConnectorRegistry {
    IGaugeRegistryVoter public immutable voter;
    IPairFactory public immutable v2PairFactory;
    IPairFactory public immutable deprecatedSilpstreamPairFactory;
    IPairFactory public immutable slipstreamPairFactory;
    AerodromeGaugeConnector public immutable v2GaugeConnector;
    VelodromeSlipstreamGaugeConnector public immutable slipstreamGaugeConnector;

    constructor(
        IGaugeRegistryVoter voter_,
        IPairFactory v2PairFactory_,
        IPairFactory deprecatedSilpstreamPairFactory_,
        IPairFactory slipstreamPairFactory_,
        AerodromeGaugeConnector v2GaugeConnector_,
        VelodromeSlipstreamGaugeConnector slipstreamGaugeConnector_
    ) {
        voter = voter_;
        v2PairFactory = v2PairFactory_;
        deprecatedSilpstreamPairFactory = deprecatedSilpstreamPairFactory_;
        slipstreamPairFactory = slipstreamPairFactory_;
        v2GaugeConnector = v2GaugeConnector_;
        slipstreamGaugeConnector = slipstreamGaugeConnector_;
    }

    function connectorOf(address target)
        external
        view
        override
        returns (address)
    {
        if (voter.isGauge(target)) {
            address pair = voter.poolForGauge(target);
            if (v2PairFactory.isPair(pair)) {
                return address(v2GaugeConnector);
            }
            if (deprecatedSilpstreamPairFactory.isPair(pair)) {
                return address(slipstreamGaugeConnector);
            }
            if (slipstreamPairFactory.isPair(pair)) {
                return address(slipstreamGaugeConnector);
            }
        }

        return address(0);
    }
}
