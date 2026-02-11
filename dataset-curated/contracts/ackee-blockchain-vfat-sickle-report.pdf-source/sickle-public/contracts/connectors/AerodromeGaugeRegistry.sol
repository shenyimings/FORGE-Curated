// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ICustomConnectorRegistry } from "contracts/ConnectorRegistry.sol";
import { AerodromeGaugeConnector } from
    "contracts/connectors/AerodromeGaugeConnector.sol";
import { AerodromeSlipstreamGaugeConnector } from
    "contracts/connectors/AerodromeSlipstreamGaugeConnector.sol";
import { IGaugeRegistryVoter } from "contracts/connectors/GaugeRegistry.sol";
import { IPoolFactory } from
    "contracts/interfaces/external/aerodrome/IPoolFactory.sol";

contract AerodromeGaugeRegistry is ICustomConnectorRegistry {
    IGaugeRegistryVoter public immutable voter;
    IPoolFactory public immutable v2PairFactory;
    IPoolFactory public immutable slipstreamPairFactory;
    AerodromeGaugeConnector public immutable v2GaugeConnector;
    AerodromeSlipstreamGaugeConnector public immutable slipstreamGaugeConnector;

    constructor(
        IGaugeRegistryVoter voter_,
        IPoolFactory v2PairFactory_,
        IPoolFactory slipstreamPairFactory_,
        AerodromeGaugeConnector v2GaugeConnector_,
        AerodromeSlipstreamGaugeConnector slipstreamGaugeConnector_
    ) {
        voter = voter_;
        v2PairFactory = v2PairFactory_;
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
            if (v2PairFactory.isPool(pair)) {
                return address(v2GaugeConnector);
            }
            if (slipstreamPairFactory.isPool(pair)) {
                return address(slipstreamGaugeConnector);
            }
        }

        return address(0);
    }
}
