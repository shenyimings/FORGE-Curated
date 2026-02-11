// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {RedstonePriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/updatable/RedstonePriceFeed.sol";
import {IStateSerializerLegacy} from "../../interfaces/IStateSerializerLegacy.sol";

contract RedstonePriceFeedSerializer is IStateSerializerLegacy {
    function serialize(address priceFeed) external view override returns (bytes memory) {
        RedstonePriceFeed pf = RedstonePriceFeed(priceFeed);

        address[10] memory signers = [
            pf.signerAddress0(),
            pf.signerAddress1(),
            pf.signerAddress2(),
            pf.signerAddress3(),
            pf.signerAddress4(),
            pf.signerAddress5(),
            pf.signerAddress6(),
            pf.signerAddress7(),
            pf.signerAddress8(),
            pf.signerAddress9()
        ];

        return abi.encode(
            pf.token(),
            pf.dataFeedId(),
            signers,
            pf.getUniqueSignersThreshold(),
            pf.lastPrice(),
            pf.lastPayloadTimestamp()
        );
    }
}
