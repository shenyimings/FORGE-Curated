// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ICustomConnectorRegistry } from "contracts/ConnectorRegistry.sol";

interface IGaugeRegistryVoter {
    function isGauge(address target) external view returns (bool);

    function poolForGauge(address gauge) external view returns (address);
}

contract GaugeRegistry is ICustomConnectorRegistry {
    IGaugeRegistryVoter public immutable voter;
    address public immutable connector;

    constructor(IGaugeRegistryVoter voter_, address connector_) {
        voter = voter_;
        connector = connector_;
    }

    function connectorOf(address target)
        external
        view
        override
        returns (address)
    {
        if (voter.isGauge(target)) {
            return connector;
        }

        return address(0);
    }
}
