// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Call} from "../Types.sol";
import {IFactory} from "./IFactory.sol";

interface IMarketFactory is IFactory {
    // ------------ //
    // MARKET HOOKS //
    // ------------ //

    function onCreateMarket(
        address pool,
        address priceOracle,
        address interestRateModel,
        address rateKeeper,
        address lossPolicy,
        address underlyingPriceFeed
    ) external returns (Call[] memory calls);

    function onShutdownMarket(address pool) external returns (Call[] memory calls);

    function onCreateCreditSuite(address creditManager) external returns (Call[] memory calls);

    function onShutdownCreditSuite(address creditManager) external returns (Call[] memory calls);

    function onUpdatePriceOracle(address pool, address newPriceOracle, address oldPriceOracle)
        external
        returns (Call[] memory calls);

    function onUpdateInterestRateModel(address pool, address newInterestRateModel, address oldInterestRateModel)
        external
        returns (Call[] memory calls);

    function onUpdateRateKeeper(address pool, address newRateKeeper, address oldRateKeeper)
        external
        returns (Call[] memory calls);

    function onUpdateLossPolicy(address pool, address newLossPolicy, address oldLossPolicy)
        external
        returns (Call[] memory calls);

    function onAddToken(address pool, address token, address priceFeed) external returns (Call[] memory calls);
}
