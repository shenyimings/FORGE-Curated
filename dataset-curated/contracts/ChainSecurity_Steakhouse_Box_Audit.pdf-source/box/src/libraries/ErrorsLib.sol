// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

library ErrorsLib {
    // General errors
    error InvalidAddress();
    error InvalidAmount();
    error InvalidValue();
    error CannotRemove();
    error AlreadyWhitelisted();
    error NotWhitelisted();
    error NotClean();
    error NotAllowed();

    // Access control errors
    error OnlyOwner();
    error OnlyCurator();
    error OnlyGuardian();
    error OnlyCuratorOrGuardian();
    error OnlyAllocators();
    error OnlyFeeders();
    error OnlySkimRecipient();
    error OnlyAllocatorsOrWinddown();
    error OnlyMorpho();
    error OnlyBox();
    error OnlyPool();
    error OnlyThisContract();
    error CannotDuringShutdown();
    error CannotDuringWinddown();

    // Withdraw/Redeem errors
    error InsufficientShares();
    error InsufficientAllowance();
    error InsufficientLiquidity();
    error DataAlreadyTimelocked();

    // Token errors
    error TokenNotWhitelisted();
    error TokenAlreadyWhitelisted();
    error OracleRequired();
    error NoOracleForToken();
    error TokenBalanceMustBeZero();
    error TooManyTokens();

    // Slippage errors
    error SwapperDidSpendTooMuch();
    error AllocationTooExpensive();
    error TokenSaleNotGeneratingEnoughAssets();
    error ReallocationSlippageTooHigh();
    error TooMuchAccumulatedSlippage();
    error SlippageTooHigh();

    // Shutdown/Recover errors
    error OnlyGuardianOrCuratorCanShutdown();
    error OnlyGuardianCanRecover();
    error AlreadyShutdown();
    error NotShutdown();
    error CannotRecoverAfterWinddown();

    // Timelock errors
    error TimelockNotExpired();
    error DataNotTimelocked();
    error InvalidTimelock();
    error TimelockNotIncreasing();
    error TimelockNotDecreasing();
    error FunctionDisabled();

    // Skim errors
    error CannotSkimToken();
    error CannotSkimZero();
    error SkimChangedNav();
    error TransferFailed();

    // Funding module errors
    error ExcessiveLTV();
    error NoNavDuringCache();
    error InvalidFacilityData();

    // Flash callback errors
    error ReentryNotAllowed();
}
