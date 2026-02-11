// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {BaseState} from "../types/BaseState.sol";
import {MarketFilter} from "../types/Filters.sol";
import {MarketData, PoolState, QuotaKeeperState, RateKeeperState} from "../types/MarketData.sol";

interface IMarketCompressor is IVersion {
    function getMarkets(MarketFilter memory filter) external view returns (MarketData[] memory);

    function getMarketData(address pool) external view returns (MarketData memory);

    function getMarketData(address pool, address configurator) external view returns (MarketData memory);

    function getPoolState(address pool) external view returns (PoolState memory);

    function getQuotaKeeperState(address quotaKeeper) external view returns (QuotaKeeperState memory);

    function getRateKeeperState(address rateKeeper) external view returns (RateKeeperState memory);

    function getInterestRateModelState(address interestRateModel) external view returns (BaseState memory);

    function getLossPolicyState(address lossPolicy) external view returns (BaseState memory);
}
