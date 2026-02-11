// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {PythPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/updatable/PythPriceFeed.sol";
import {IStateSerializerLegacy} from "../../interfaces/IStateSerializerLegacy.sol";

contract PythPriceFeedSerializer is IStateSerializerLegacy {
    function serialize(address priceFeed) external view override returns (bytes memory) {
        PythPriceFeed pf = PythPriceFeed(payable(priceFeed));

        return abi.encode(pf.token(), pf.priceFeedId(), pf.pyth());
    }
}
