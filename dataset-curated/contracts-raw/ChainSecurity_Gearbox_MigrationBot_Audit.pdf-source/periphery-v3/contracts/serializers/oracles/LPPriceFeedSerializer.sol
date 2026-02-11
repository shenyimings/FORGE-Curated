// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {ILPPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/interfaces/ILPPriceFeed.sol";
import {IStateSerializerLegacy} from "../../interfaces/IStateSerializerLegacy.sol";

contract LPPriceFeedSerializer is IStateSerializerLegacy {
    struct PriceData {
        uint256 exchangeRate;
        int256 aggregatePrice;
        uint256 scale;
        bool exchageRateSuccess;
        bool aggregatePriceSuccess;
    }

    function serialize(address priceFeed) public view virtual override returns (bytes memory) {
        ILPPriceFeed pf = ILPPriceFeed(priceFeed);

        return abi.encode(pf.lpToken(), pf.lpContract(), pf.lowerBound(), pf.upperBound(), _getPriceData(pf));
    }

    function _getPriceData(ILPPriceFeed priceFeed) internal view returns (PriceData memory data) {
        try priceFeed.getLPExchangeRate() returns (uint256 rate) {
            data.exchangeRate = rate;
            data.exchageRateSuccess = true;
        } catch {}

        try priceFeed.getAggregatePrice() returns (int256 price) {
            data.aggregatePrice = price;
            data.aggregatePriceSuccess = true;
        } catch {}

        // safe to assume that `getScale` is non-reverting
        data.scale = priceFeed.getScale();
    }
}
