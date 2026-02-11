// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {PriceUpdate} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeedStore.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

struct TokenBalance {
    address token;
    uint256 balance;
    bool isForbidden;
    bool isEnabled;
    bool isQuoted;
    uint256 quota;
    uint16 quotaRate;
    uint256 quotaCumulativeIndexLU;
}

struct QuotaInfo {
    address token;
    uint16 rate;
    uint16 quotaIncreaseFee;
    uint96 totalQuoted;
    uint96 limit;
    bool isActive;
}

struct ContractAdapter {
    address targetContract;
    address adapter;
}

struct ZapperInfo {
    address zapper;
    address tokenIn;
    address tokenOut;
}

struct CreditAccountData {
    // if not successful, priceFeedsNeeded are filled with the data
    bool isSuccessful;
    address[] priceFeedsNeeded;
    address addr;
    address borrower;
    address creditManager;
    string cmName;
    address creditFacade;
    address underlying;
    uint256 debt;
    uint256 cumulativeIndexLastUpdate;
    uint128 cumulativeQuotaInterest;
    uint256 accruedInterest;
    uint256 accruedFees;
    uint256 totalDebtUSD;
    uint256 totalValue;
    uint256 totalValueUSD;
    uint256 twvUSD;
    uint256 enabledTokensMask;
    ///
    uint256 healthFactor;
    uint256 baseBorrowRate;
    uint256 aggregatedBorrowRate;
    TokenBalance[] balances;
    uint64 since;
    uint256 cfVersion;
    // V3 features
    uint40 expirationDate;
    address[] activeBots;
}

struct LinearModel {
    address interestRateModel;
    uint256 version;
    uint16 U_1;
    uint16 U_2;
    uint16 R_base;
    uint16 R_slope1;
    uint16 R_slope2;
    uint16 R_slope3;
    bool isBorrowingMoreU2Forbidden;
}

struct CreditManagerData {
    address addr;
    string name;
    uint256 cfVersion;
    address creditFacade; // V2 only: address of creditFacade
    address creditConfigurator; // V2 only: address of creditConfigurator
    address underlying;
    address pool;
    uint256 totalDebt;
    uint256 totalDebtLimit;
    uint256 baseBorrowRate;
    uint256 minDebt;
    uint256 maxDebt;
    uint256 availableToBorrow;
    address[] collateralTokens;
    ContractAdapter[] adapters;
    uint256[] liquidationThresholds;
    bool isDegenMode; // V2 only: true if contract is in Degen mode
    address degenNFT; // V2 only: degenNFT, address(0) if not in degen mode
    uint256 forbiddenTokenMask; // V2 only: mask which forbids some particular tokens
    uint8 maxEnabledTokensLength; // V2 only: in V1 as many tokens as the CM can support (256)
    uint16 feeInterest; // Interest fee protocol charges: fee = interest accrues * feeInterest
    uint16 feeLiquidation; // Liquidation fee protocol charges: fee = totalValue * feeLiquidation
    uint16 liquidationDiscount; // Miltiplier to get amount which liquidator should pay: amount = totalValue * liquidationDiscount
    uint16 feeLiquidationExpired; // Liquidation fee protocol charges on expired accounts
    uint16 liquidationDiscountExpired; // Multiplier for the amount the liquidator has to pay when closing an expired account
    // V3 Fileds
    QuotaInfo[] quotas;
    LinearModel lirm;
    bool isPaused;
}
// LIR

struct CreditManagerDebtParams {
    address creditManager;
    uint256 borrowed;
    uint256 limit;
    uint256 availableToBorrow;
}

struct PoolData {
    address addr;
    address underlying;
    address dieselToken;
    string symbol;
    string name;
    ///
    uint256 baseInterestIndex;
    uint256 availableLiquidity;
    uint256 expectedLiquidity;
    //
    uint256 totalBorrowed;
    uint256 totalDebtLimit;
    CreditManagerDebtParams[] creditManagerDebtParams;
    uint256 totalAssets;
    uint256 totalSupply;
    uint256 supplyRate;
    uint256 baseInterestRate;
    uint256 dieselRate_RAY;
    uint256 withdrawFee;
    uint256 lastBaseInterestUpdate;
    uint256 baseInterestIndexLU;
    uint256 version;
    address poolQuotaKeeper;
    address gauge;
    QuotaInfo[] quotas;
    ZapperInfo[] zappers;
    LinearModel lirm;
    bool isPaused;
}

struct GaugeQuotaParams {
    address token;
    uint16 minRate;
    uint16 maxRate;
    uint96 totalVotesLpSide;
    uint96 totalVotesCaSide;
    uint16 rate;
    uint16 quotaIncreaseFee;
    uint96 totalQuoted;
    uint96 limit;
    bool isActive;
    uint96 stakerVotesLpSide;
    uint96 stakerVotesCaSide;
}

struct GaugeInfo {
    address addr;
    address pool;
    string symbol;
    string name;
    address underlying;
    uint16 currentEpoch;
    bool epochFrozen;
    GaugeQuotaParams[] quotaParams;
}

interface IDataCompressorV3 is IVersion {
    /// @dev Returns CreditAccountData for all opened accounts for particular borrower
    /// @param borrower Borrower address
    /// @param priceUpdates Price updates for price on demand oracles
    function getCreditAccountsByBorrower(address borrower, PriceUpdate[] memory priceUpdates)
        external
        returns (CreditAccountData[] memory);

    /// @dev Returns CreditAccountData for all opened accounts for particular borrower
    /// @param creditManager Address
    /// @param priceUpdates Price updates for price on demand oracles
    function getCreditAccountsByCreditManager(address creditManager, PriceUpdate[] memory priceUpdates)
        external
        returns (CreditAccountData[] memory);

    /// @dev Returns CreditAccountData for all accounts with hf <1
    /// @param priceUpdates Price updates for price on demand oracles
    function getLiquidatableCreditAccounts(PriceUpdate[] memory priceUpdates)
        external
        returns (CreditAccountData[] memory result);

    /// @dev Returns CreditAccountData for a particular Credit Account account, based on creditManager and borrower
    /// @param creditAccount Address of credit account
    /// @param priceUpdates Price updates for price on demand oracles
    function getCreditAccountData(address creditAccount, PriceUpdate[] memory priceUpdates)
        external
        returns (CreditAccountData memory);

    /// @dev Returns CreditManagerData for all Credit Managers
    function getCreditManagersV3List() external view returns (CreditManagerData[] memory);

    /// @dev Returns CreditManagerData for a particular _creditManager
    /// @param creditManager CreditManager address
    function getCreditManagerData(address creditManager) external view returns (CreditManagerData memory);

    /// @dev Returns PoolData for a particular pool
    /// @param _pool Pool address
    function getPoolData(address _pool) external view returns (PoolData memory);

    /// @dev Returns PoolData for all registered pools
    function getPoolsV3List() external view returns (PoolData[] memory);

    /// @dev Returns GaugeInfo for all registered gauges
    function getGaugesV3Data(address staker) external view returns (GaugeInfo[] memory result);
}
