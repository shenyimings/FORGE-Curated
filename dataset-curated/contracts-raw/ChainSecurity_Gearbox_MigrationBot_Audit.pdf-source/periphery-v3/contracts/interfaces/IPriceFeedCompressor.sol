// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {BaseParams} from "../types/BaseState.sol";
import {MarketFilter} from "../types/Filters.sol";
import {PriceFeedTreeNode, PriceOracleState} from "../types/PriceOracleState.sol";

interface IPriceFeedCompressor is IVersion {
    function getPriceOracles(MarketFilter memory filter) external view returns (PriceOracleState[] memory);

    function getPriceOracleState(address priceOracle) external view returns (PriceOracleState memory);

    function getPriceOracleState(address priceOracle, address[] memory tokens)
        external
        view
        returns (PriceOracleState memory);

    function loadPriceFeedTree(MarketFilter memory filter) external view returns (PriceFeedTreeNode[] memory);

    function loadPriceFeedTree(address[] memory priceFeeds) external view returns (PriceFeedTreeNode[] memory);

    function getUpdatablePriceFeeds(MarketFilter memory filter) external view returns (BaseParams[] memory);

    function getUpdatablePriceFeeds(address[] memory priceFeeds) external view returns (BaseParams[] memory);
}
