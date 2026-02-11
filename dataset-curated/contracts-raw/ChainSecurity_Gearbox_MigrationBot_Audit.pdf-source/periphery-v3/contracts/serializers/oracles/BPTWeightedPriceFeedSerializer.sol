// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {BPTWeightedPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/balancer/BPTWeightedPriceFeed.sol";
import {LPPriceFeedSerializer} from "./LPPriceFeedSerializer.sol";

contract BPTWeightedPriceFeedSerializer is LPPriceFeedSerializer {
    function serialize(address priceFeed) public view override returns (bytes memory) {
        BPTWeightedPriceFeed pf = BPTWeightedPriceFeed(priceFeed);

        uint256[8] memory weights = [
            pf.weight0(),
            pf.weight1(),
            pf.weight2(),
            pf.weight3(),
            pf.weight4(),
            pf.weight5(),
            pf.weight6(),
            pf.weight7()
        ];

        return abi.encode(super.serialize(priceFeed), pf.vault(), pf.poolId(), weights);
    }
}
