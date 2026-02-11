// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ICustomConnectorRegistry } from "contracts/ConnectorRegistry.sol";
import { AerodromeGaugeConnector } from
    "contracts/connectors/AerodromeGaugeConnector.sol"; // ABI
    // is the same as Aerodrome

interface IStakingRewardsFactory {
    function poolForGauge(address gauge) external view returns (address);
}

contract VelodromeStakingRewardsRegistry is ICustomConnectorRegistry {
    AerodromeGaugeConnector public immutable aerodromeGaugeConnector;
    IStakingRewardsFactory public immutable stakingRewardsFactory;

    constructor(
        IStakingRewardsFactory stakingRewardsFactory_,
        AerodromeGaugeConnector aerodromeGaugeConnector_
    ) {
        stakingRewardsFactory = stakingRewardsFactory_;
        aerodromeGaugeConnector = aerodromeGaugeConnector_;
    }

    function connectorOf(address target)
        external
        view
        override
        returns (address)
    {
        if (stakingRewardsFactory.poolForGauge(target) != address(0)) {
            return address(aerodromeGaugeConnector);
        }

        return address(0);
    }
}
