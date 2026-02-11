// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {BaseState, BaseParams} from "./BaseState.sol";

struct AdapterState {
    BaseParams baseParams;
    address targetContract;
}

struct CollateralToken {
    address token;
    uint16 liquidationThreshold;
}

struct CreditFacadeState {
    BaseParams baseParams;
    address degenNFT;
    address botList;
    bool expirable;
    uint40 expirationDate;
    uint8 maxDebtPerBlockMultiplier;
    uint256 minDebt;
    uint256 maxDebt;
    uint256 forbiddenTokensMask;
    bool isPaused;
}

struct CreditManagerState {
    BaseParams baseParams;
    string name;
    address accountFactory;
    address underlying;
    address pool;
    address creditFacade;
    address creditConfigurator;
    uint8 maxEnabledTokens;
    CollateralToken[] collateralTokens;
    uint16 feeInterest;
    uint16 feeLiquidation;
    uint16 liquidationDiscount;
    uint16 feeLiquidationExpired;
    uint16 liquidationDiscountExpired;
}

struct CreditSuiteData {
    CreditFacadeState creditFacade;
    CreditManagerState creditManager;
    BaseState creditConfigurator;
    BaseState accountFactory;
    AdapterState[] adapters;
}
