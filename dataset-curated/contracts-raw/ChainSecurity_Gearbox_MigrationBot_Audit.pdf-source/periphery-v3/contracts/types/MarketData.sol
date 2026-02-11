// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {BaseParams, BaseState} from "./BaseState.sol";
import {CreditSuiteData} from "./CreditSuiteData.sol";
import {PriceOracleState} from "./PriceOracleState.sol";
import {TokenData} from "./TokenData.sol";

struct CreditManagerDebtParams {
    address creditManager;
    uint256 borrowed;
    uint256 limit;
    uint256 available;
}

struct MarketData {
    address acl;
    address contractsRegister;
    address treasury;
    PoolState pool;
    QuotaKeeperState quotaKeeper;
    BaseState interestRateModel;
    RateKeeperState rateKeeper;
    PriceOracleState priceOracle;
    BaseState lossPolicy;
    TokenData[] tokens;
    CreditSuiteData[] creditManagers;
    address configurator;
    address[] pausableAdmins;
    address[] unpausableAdmins;
    address[] emergencyLiquidators;
}

struct PoolState {
    BaseParams baseParams;
    string symbol;
    string name;
    uint8 decimals;
    uint256 totalSupply;
    address quotaKeeper;
    address interestRateModel;
    address underlying;
    uint256 availableLiquidity;
    uint256 expectedLiquidity;
    uint256 baseInterestIndex;
    uint256 baseInterestRate;
    uint256 dieselRate;
    uint256 supplyRate;
    uint256 withdrawFee;
    uint256 totalBorrowed;
    uint256 totalDebtLimit;
    CreditManagerDebtParams[] creditManagerDebtParams;
    uint256 baseInterestIndexLU;
    uint256 expectedLiquidityLU;
    uint256 quotaRevenue;
    uint40 lastBaseInterestUpdate;
    uint40 lastQuotaRevenueUpdate;
    bool isPaused;
}

struct QuotaKeeperState {
    BaseParams baseParams;
    address rateKeeper;
    QuotaTokenParams[] quotas;
    address[] creditManagers;
    uint40 lastQuotaRateUpdate;
}

struct QuotaTokenParams {
    address token;
    uint16 rate;
    uint192 cumulativeIndexLU;
    uint16 quotaIncreaseFee;
    uint96 totalQuoted;
    uint96 limit;
    bool isActive;
}

struct Rate {
    address token;
    uint16 rate;
}

struct RateKeeperState {
    BaseParams baseParams;
    Rate[] rates;
}
