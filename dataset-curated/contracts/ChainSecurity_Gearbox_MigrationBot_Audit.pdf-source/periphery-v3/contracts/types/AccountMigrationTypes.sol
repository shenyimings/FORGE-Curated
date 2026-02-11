// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {MultiCall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";

struct PhantomTokenOverride {
    address newToken;
    address underlying;
    bytes withdrawalCallData;
}

struct PhantomTokenParams {
    bool isPhantomToken;
    address underlying;
    uint256 underlyingAmount;
}

struct MigratedCollateral {
    address collateral;
    uint256 amount;
    uint96 targetQuotaIncrease;
    bool underlyingInSource;
    bool underlyingInTarget;
    PhantomTokenParams phantomTokenParams;
}

struct FailureStates {
    bool targetHFTooLow;
    bool targetSafeHFTooLow;
    bool sourceUnderlyingIsNotCollateral;
    bool migratedCollateralDoesNotExistInTarget;
    bool insufficientTargetQuotaLimits;
    bool insufficientTargetBorrowLiquidity;
    bool insufficientTargetDebtLimit;
    bool newTargetDebtOutOfLimits;
    bool noPathToSourceUnderlying;
    bool cannotSwapEnoughToCoverDebt;
    bool sourceHasNoMigratorBotAdapter;
}

struct MigrationParams {
    address accountOwner;
    address sourceCreditAccount;
    address targetCreditManager;
    MigratedCollateral[] migratedCollaterals;
    uint256 targetBorrowAmount;
    MultiCall[] underlyingSwapCalls;
    MultiCall[] extraOpeningCalls;
    address[] uniqueTransferredTokens;
    uint256 numAddCollateralCalls;
    uint256 numRemoveQuotasCalls;
    uint256 numIncreaseQuotaCalls;
    uint256 numPhantomTokenCalls;
}

struct PreviewMigrationResult {
    bool success;
    uint256 expectedTargetHF;
    uint256 expectedTargetSafeHF;
    uint256 expectedUnderlyingDust;
    FailureStates failureStates;
    MigrationParams migrationParams;
}
