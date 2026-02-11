// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ComptrollerV1Storage } from
    "contracts/interfaces/external/compound-v2/ComptrollerStorage.sol";
import { ICustomConnectorRegistry } from "contracts/ConnectorRegistry.sol";
import { CompoundMarketConnector } from
    "contracts/connectors/CompoundMarketConnector.sol";

contract ComptrollerRegistry is ICustomConnectorRegistry {
    ComptrollerV1Storage public immutable comptroller;
    CompoundMarketConnector public immutable connector;

    constructor(
        ComptrollerV1Storage comptroller_,
        CompoundMarketConnector connector_
    ) {
        comptroller = comptroller_;
        connector = connector_;
    }

    function connectorOf(address target)
        external
        view
        override
        returns (address)
    {
        (bool isListed,,) = comptroller.markets(target);
        if (isListed) {
            return address(connector);
        }

        return address(0);
    }
}
