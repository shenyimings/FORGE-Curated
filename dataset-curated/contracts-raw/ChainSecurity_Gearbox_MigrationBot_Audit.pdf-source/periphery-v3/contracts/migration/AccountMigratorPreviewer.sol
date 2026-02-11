// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IAccountMigratorBot, IAccountMigratorPreviewer} from "../interfaces/IAccountMigratorBot.sol";
import {
    MigrationParams,
    PreviewMigrationResult,
    MigratedCollateral,
    PhantomTokenParams,
    PhantomTokenOverride
} from "../types/AccountMigrationTypes.sol";
import {IGearboxRouter, RouterResult, TokenData} from "../interfaces/external/IGearboxRouter.sol";
import {
    INACTIVE_CREDIT_ACCOUNT_ADDRESS,
    UNDERLYING_TOKEN_MASK,
    WAD,
    PERCENTAGE_FACTOR
} from "@gearbox-protocol/core-v3/contracts/libraries/Constants.sol";
import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";
import {ICreditFacadeV3, MultiCall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {
    ICreditManagerV3,
    CollateralDebtData,
    CollateralCalcTask
} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {
    ICreditFacadeV3Multicall,
    EXTERNAL_CALLS_PERMISSION,
    UPDATE_QUOTA_PERMISSION,
    DECREASE_DEBT_PERMISSION,
    INCREASE_DEBT_PERMISSION,
    WITHDRAW_COLLATERAL_PERMISSION
} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3Multicall.sol";
import {OptionalCall} from "@gearbox-protocol/core-v3/contracts/libraries/OptionalCall.sol";
import {
    IPhantomToken, IPhantomTokenAdapter
} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPhantomToken.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IInterestRateModel} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IInterestRateModel.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {IPriceFeedStore} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeedStore.sol";
import {IPriceOracleV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPriceOracleV3.sol";
import {ACLTrait} from "@gearbox-protocol/core-v3/contracts/traits/ACLTrait.sol";
import {IMarketConfigurator} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";
import {IMarketConfiguratorFactory} from
    "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfiguratorFactory.sol";
import {IContractsRegister} from "@gearbox-protocol/permissionless/contracts/interfaces/IContractsRegister.sol";
import {BitMask} from "@gearbox-protocol/core-v3/contracts/libraries/BitMask.sol";
import {CreditLogic} from "@gearbox-protocol/core-v3/contracts/libraries/CreditLogic.sol";
import {PriceUpdate} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeedStore.sol";

contract AccountMigratorPreviewer is IAccountMigratorPreviewer {
    using SafeERC20 for IERC20;
    using BitMask for uint256;
    using CreditLogic for CollateralDebtData;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant override version = 3_10;
    bytes32 public constant override contractType = "ACCOUNT_MIGRATOR_PREVIEWER";

    address public immutable router;

    address public immutable migratorBot;

    constructor(address _migratorBot, address _router) {
        migratorBot = _migratorBot;
        router = _router;
    }

    /// PREVIEW LOGIC

    /// @notice Previews migration and prepares the required migration parameters.
    ///         Also returns whether the migration will fail and failure reasons, if so.
    /// @param sourceCreditAccount The credit account to migrate from.
    /// @param targetCreditManager The credit manager to migrate to.
    /// @param priceUpdates The price updates to apply.
    /// @return result The preview migration result.
    function previewMigration(
        address sourceCreditAccount,
        address targetCreditManager,
        PriceUpdate[] memory priceUpdates
    ) external returns (PreviewMigrationResult memory result) {
        _applyPriceUpdates(targetCreditManager, priceUpdates);

        result.success = true;
        result.migrationParams.sourceCreditAccount = sourceCreditAccount;
        result.migrationParams.targetCreditManager = targetCreditManager;

        _populateMigrationParams(result);
    }

    /// @dev Populates the migration result struct, including migration parameters and success/failure states.
    function _populateMigrationParams(PreviewMigrationResult memory result) internal {
        address sourceCreditManager = ICreditAccountV3(result.migrationParams.sourceCreditAccount).creditManager();

        result.migrationParams.accountOwner =
            ICreditManagerV3(sourceCreditManager).getBorrowerOrRevert(result.migrationParams.sourceCreditAccount);

        _checkSourceUnderlyingIsCollateral(result, sourceCreditManager);

        if (!result.success) {
            return;
        }

        uint256 underlyingRate = _getUnderlyingRate(sourceCreditManager, result.migrationParams.targetCreditManager);

        _populateMigratedCollaterals(result, sourceCreditManager, underlyingRate);
        _populateDebtAndSwapCalls(result, sourceCreditManager, underlyingRate);

        _countCalls(result);

        _checkFailureStates(result);
    }

    /// @dev Checks if the source credit manager underlying is a collateral in the target credit manager.
    ///      If this is not true, the migration is not possible, because it is not possible to convert quotas or convert
    ///      the new underlying into the old one to repay debt.
    function _checkSourceUnderlyingIsCollateral(PreviewMigrationResult memory result, address sourceCreditManager)
        internal
        view
    {
        address sourceUnderlying = ICreditManagerV3(sourceCreditManager).underlying();

        try ICreditManagerV3(result.migrationParams.targetCreditManager).getTokenMaskOrRevert(sourceUnderlying)
        returns (uint256) {} catch {
            result.success = false;
            result.failureStates.sourceUnderlyingIsNotCollateral = true;
        }
    }

    /// @dev Computes the conversion rate of the source CM underlying to the target CM underlying.
    function _getUnderlyingRate(address sourceCreditManager, address targetCreditManager)
        internal
        view
        returns (uint256)
    {
        address targetPriceOracle = ICreditManagerV3(targetCreditManager).priceOracle();

        address sourceUnderlying = ICreditManagerV3(sourceCreditManager).underlying();
        address targetUnderlying = ICreditManagerV3(targetCreditManager).underlying();

        uint256 rate = IPriceOracleV3(targetPriceOracle).convert(WAD, sourceUnderlying, targetUnderlying);

        return rate;
    }

    /// @dev Populates the list of migrated collaterals. This includes the collateral, amount to transfer,
    ///      the required quota in the new credit manager (if needed), as well as phantom token parameters, such as
    ///      the underlying token and the required calls to withdraw and redeposit the phantom token.
    function _populateMigratedCollaterals(
        PreviewMigrationResult memory result,
        address sourceCreditManager,
        uint256 underlyingRate
    ) internal view {
        (,,,, uint256 enabledTokensMask,,,) =
            ICreditManagerV3(sourceCreditManager).creditAccountInfo(result.migrationParams.sourceCreditAccount);

        MigratedCollateral[] memory migratedCollaterals =
            new MigratedCollateral[](enabledTokensMask.calcEnabledTokens());

        address[] memory uniqueTransferredTokens = new address[](0);

        for (uint256 i = 0; i < migratedCollaterals.length; i++) {
            uint256 tokenMask = enabledTokensMask.lsbMask();
            migratedCollaterals[i].collateral = ICreditManagerV3(sourceCreditManager).getTokenByMask(tokenMask);
            migratedCollaterals[i].amount =
                IERC20(migratedCollaterals[i].collateral).balanceOf(result.migrationParams.sourceCreditAccount);

            (migratedCollaterals[i].underlyingInSource, migratedCollaterals[i].underlyingInTarget) =
            _isCollateralUnderlying(
                sourceCreditManager, result.migrationParams.targetCreditManager, migratedCollaterals[i].collateral
            );

            migratedCollaterals[i].targetQuotaIncrease = _getTargetQuotaIncrease(
                sourceCreditManager, result.migrationParams.sourceCreditAccount, underlyingRate, migratedCollaterals[i]
            );

            migratedCollaterals[i].phantomTokenParams =
                _getPhantomTokenParams(migratedCollaterals[i].collateral, migratedCollaterals[i].amount);

            if (migratedCollaterals[i].phantomTokenParams.isPhantomToken) {
                if (!_includes(uniqueTransferredTokens, migratedCollaterals[i].phantomTokenParams.underlying)) {
                    uniqueTransferredTokens =
                        _push(uniqueTransferredTokens, migratedCollaterals[i].phantomTokenParams.underlying);
                }
            } else {
                if (!_includes(uniqueTransferredTokens, migratedCollaterals[i].collateral)) {
                    uniqueTransferredTokens = _push(uniqueTransferredTokens, migratedCollaterals[i].collateral);
                }
            }

            enabledTokensMask = enabledTokensMask.disable(tokenMask);
        }

        result.migrationParams.migratedCollaterals = migratedCollaterals;
        result.migrationParams.uniqueTransferredTokens = uniqueTransferredTokens;
    }

    /// @dev Populates the debt and swap calls. This includes the debt amount to borrow, as well as the calls to swap
    ///      the target CM underlying to the source CM underlying. This also returns the expected underlying dust,
    ///      to optionally swap it back as part of migration extra calls.
    function _populateDebtAndSwapCalls(
        PreviewMigrationResult memory result,
        address sourceCreditManager,
        uint256 underlyingRate
    ) internal {
        address sourceCreditAccount = result.migrationParams.sourceCreditAccount;

        CollateralDebtData memory cdd = ICreditManagerV3(sourceCreditManager).calcDebtAndCollateral(
            sourceCreditAccount, CollateralCalcTask.DEBT_ONLY
        );
        uint256 debtAmount = cdd.calcTotalDebt();

        if (
            ICreditManagerV3(sourceCreditManager).underlying()
                == ICreditManagerV3(result.migrationParams.targetCreditManager).underlying()
        ) {
            result.migrationParams.targetBorrowAmount = debtAmount;
            return;
        }

        result.migrationParams.targetBorrowAmount = debtAmount * underlyingRate * 10100 / (WAD * 10000);

        _computeUnderlyingSwap(result, sourceCreditManager, debtAmount);
    }

    /// @dev Counts the number of calls of each type required to migrate the credit account. This is done to simplify
    ///      computation during actual migration and save gas.
    function _countCalls(PreviewMigrationResult memory result) internal pure {
        for (uint256 i = 0; i < result.migrationParams.uniqueTransferredTokens.length; i++) {
            for (uint256 j = 0; j < result.migrationParams.migratedCollaterals.length; j++) {
                if (
                    result.migrationParams.uniqueTransferredTokens[i]
                        == result.migrationParams.migratedCollaterals[j].collateral
                        && result.migrationParams.migratedCollaterals[j].amount > 1
                ) {
                    result.migrationParams.numAddCollateralCalls++;
                    break;
                }
                if (
                    result.migrationParams.uniqueTransferredTokens[i]
                        == result.migrationParams.migratedCollaterals[j].phantomTokenParams.underlying
                        && result.migrationParams.migratedCollaterals[j].phantomTokenParams.underlyingAmount > 1
                ) {
                    result.migrationParams.numAddCollateralCalls++;
                    break;
                }
            }
        }

        for (uint256 i = 0; i < result.migrationParams.migratedCollaterals.length; i++) {
            if (!result.migrationParams.migratedCollaterals[i].underlyingInSource) {
                result.migrationParams.numRemoveQuotasCalls++;
            }
        }

        for (uint256 i = 0; i < result.migrationParams.migratedCollaterals.length; i++) {
            if (result.migrationParams.migratedCollaterals[i].targetQuotaIncrease > 0) {
                result.migrationParams.numIncreaseQuotaCalls++;
            }
        }

        for (uint256 i = 0; i < result.migrationParams.migratedCollaterals.length; i++) {
            if (
                result.migrationParams.migratedCollaterals[i].phantomTokenParams.isPhantomToken
                    && result.migrationParams.migratedCollaterals[i].amount > 1
            ) {
                result.migrationParams.numPhantomTokenCalls++;
            }
        }
    }

    /// @dev Checks whether the migration may fail due to various reasons. Also populates the failure states for
    ///      easier display and debugging, as well as the expected HF of the new acount.
    function _checkFailureStates(PreviewMigrationResult memory result) internal view {
        _checkSourceHasMigratorBotAdapter(result);
        _checkTargetCollaterals(result);

        if (!result.success && result.failureStates.migratedCollateralDoesNotExistInTarget) {
            return;
        }

        _checkTargetQuotaLimits(result);
        _checkNewDebt(result);
        _checkTargetHF(result);
    }

    /// @dev Checks whether the collateral is the underlying of the source or target credit manager.
    function _isCollateralUnderlying(address sourceCreditManager, address targetCreditManager, address collateral)
        internal
        view
        returns (bool isUnderlyingInSource, bool isUnderlyingInTarget)
    {
        isUnderlyingInSource = ICreditManagerV3(sourceCreditManager).underlying() == collateral;
        isUnderlyingInTarget = ICreditManagerV3(targetCreditManager).underlying() == collateral;
    }

    /// @dev Computes the required quota increase in the taregt credit manager. In case when the token is quoted in both source and target,
    ///      the quota is computed by converting the source quota to the target underlying. If the token is not quoted in the source,
    ///      the quota is set to 1.005 of the amount.
    function _getTargetQuotaIncrease(
        address sourceCreditManager,
        address sourceCreditAccount,
        uint256 underlyingRate,
        MigratedCollateral memory collateral
    ) internal view returns (uint96 targetQuota) {
        if (collateral.underlyingInTarget) {
            targetQuota = 0;
        } else if (!collateral.underlyingInSource) {
            (uint96 sourceQuota,) = IPoolQuotaKeeperV3(ICreditManagerV3(sourceCreditManager).poolQuotaKeeper()).getQuota(
                sourceCreditAccount, collateral.collateral
            );
            targetQuota = uint96(sourceQuota * underlyingRate / WAD);
        } else {
            targetQuota = uint96(collateral.amount * 10050 * underlyingRate / (WAD * 10000));
        }

        return (targetQuota / 10000) * 10000;
    }

    /// @dev Computes whether to migrated collateral is a phantom token and its underlying.
    function _getPhantomTokenParams(address collateral, uint256 amount)
        internal
        view
        returns (PhantomTokenParams memory ptParams)
    {
        PhantomTokenOverride memory ptOverride = IAccountMigratorBot(migratorBot).phantomTokenOverrides(collateral);
        if (ptOverride.newToken != address(0)) {
            ptParams.isPhantomToken = true;
            ptParams.underlying = ptOverride.underlying;
            ptParams.underlyingAmount = amount;
            return ptParams;
        }

        (, address depositedToken) = _getPhantomTokenInfo(collateral);

        if (depositedToken != address(0)) {
            ptParams.isPhantomToken = true;
            ptParams.underlying = depositedToken;
            ptParams.underlyingAmount = amount;
        }

        return ptParams;
    }

    /// @dev Checks if an array contains an item.
    function _includes(address[] memory array, address item) internal pure returns (bool) {
        uint256 len = array.length;
        for (uint256 i = 0; i < len; i++) {
            if (array[i] == item) return true;
        }
        return false;
    }

    /// @dev Pushes an item to an array.
    function _push(address[] memory array, address item) internal pure returns (address[] memory result) {
        uint256 len = array.length;
        result = new address[](len + 1);
        for (uint256 i = 0; i < len; i++) {
            result[i] = array[i];
        }
        result[len] = item;
    }

    /// @dev Computes the underlying swap calls to swap the target CM underlying to the source CM underlying.
    ///      Due to exact output swaps not being supported, the amount borrowed and swapped is taken with a surplus.
    ///      The expected surplus amount is returned in the result, to be optionally swapped back as part of migration extra calls.
    function _computeUnderlyingSwap(
        PreviewMigrationResult memory result,
        address sourceCreditManager,
        uint256 debtAmount
    ) internal {
        uint256 len = ICreditManagerV3(result.migrationParams.targetCreditManager).collateralTokensCount();
        address underlying = ICreditManagerV3(result.migrationParams.targetCreditManager).underlying();

        TokenData[] memory tData = new TokenData[](len);

        for (uint256 i = 0; i < len; ++i) {
            address token = ICreditManagerV3(result.migrationParams.targetCreditManager).getTokenByMask(1 << i);

            tData[i] = TokenData({
                token: token,
                balance: token == underlying ? result.migrationParams.targetBorrowAmount : 0,
                leftoverBalance: 1,
                numSplits: 2,
                claimRewards: false
            });
        }

        for (uint256 i = 0; i < result.migrationParams.migratedCollaterals.length; i++) {
            if (result.migrationParams.migratedCollaterals[i].underlyingInTarget) {
                tData[0].balance += result.migrationParams.migratedCollaterals[i].amount;
                tData[0].leftoverBalance = result.migrationParams.migratedCollaterals[i].amount;
            }
        }

        try IGearboxRouter(router).routeOpenManyToOne(
            result.migrationParams.targetCreditManager, ICreditManagerV3(sourceCreditManager).underlying(), 50, tData
        ) returns (RouterResult memory routerResult) {
            result.migrationParams.underlyingSwapCalls = routerResult.calls;
            if (routerResult.minAmount < debtAmount) {
                result.success = false;
                result.failureStates.cannotSwapEnoughToCoverDebt = true;
            } else {
                result.expectedUnderlyingDust = routerResult.amount - debtAmount;
            }
        } catch {
            result.success = false;
            result.failureStates.noPathToSourceUnderlying = true;
        }
    }

    /// @dev Checks whether the target credit manager has an adapter for the migrator bot.
    function _checkSourceHasMigratorBotAdapter(PreviewMigrationResult memory result) internal view {
        address sourceAdapter = ICreditManagerV3(
            ICreditAccountV3(result.migrationParams.sourceCreditAccount).creditManager()
        ).contractToAdapter(migratorBot);
        if (sourceAdapter == address(0)) {
            result.success = false;
            result.failureStates.sourceHasNoMigratorBotAdapter = true;
        }
    }

    /// @dev Checks whether the target pool and credit manager support all of the migrated collaterals.
    function _checkTargetCollaterals(PreviewMigrationResult memory result) internal view {
        address sourceCreditManager = ICreditAccountV3(result.migrationParams.sourceCreditAccount).creditManager();

        address sourcePool = ICreditManagerV3(sourceCreditManager).pool();
        address targetPool = ICreditManagerV3(result.migrationParams.targetCreditManager).pool();

        if (sourcePool != targetPool) {
            for (uint256 i = 0; i < result.migrationParams.migratedCollaterals.length; i++) {
                address token = _getCollateralOrOverride(result.migrationParams.migratedCollaterals[i]);

                if (!result.migrationParams.migratedCollaterals[i].underlyingInTarget) {
                    address poolQuotaKeeper = IPoolV3(targetPool).poolQuotaKeeper();

                    (, uint192 indexLU,,,,) = IPoolQuotaKeeperV3(poolQuotaKeeper).getTokenQuotaParams(token);
                    if (indexLU == 0) {
                        result.success = false;
                        result.failureStates.migratedCollateralDoesNotExistInTarget = true;
                    }
                }

                try ICreditManagerV3(result.migrationParams.targetCreditManager).getTokenMaskOrRevert(token) returns (
                    uint256
                ) {} catch {
                    result.success = false;
                    result.failureStates.migratedCollateralDoesNotExistInTarget = true;
                }
            }
        }
    }

    /// @dev Checks whether the target pool and credit manager have enough quotas for the migrated collaterals.
    function _checkTargetQuotaLimits(PreviewMigrationResult memory result) internal view {
        address sourcePool =
            ICreditManagerV3(ICreditAccountV3(result.migrationParams.sourceCreditAccount).creditManager()).pool();
        address targetPool = ICreditManagerV3(result.migrationParams.targetCreditManager).pool();
        address poolQuotaKeeper = IPoolV3(targetPool).poolQuotaKeeper();

        for (uint256 i = 0; i < result.migrationParams.migratedCollaterals.length; i++) {
            if (result.migrationParams.migratedCollaterals[i].underlyingInTarget) {
                continue;
            }

            address token = _getCollateralOrOverride(result.migrationParams.migratedCollaterals[i]);

            (,,, uint96 totalQuoted, uint96 limit,) = IPoolQuotaKeeperV3(poolQuotaKeeper).getTokenQuotaParams(token);

            if (sourcePool != targetPool) {
                if (result.migrationParams.migratedCollaterals[i].targetQuotaIncrease + totalQuoted > limit) {
                    result.success = false;
                    result.failureStates.insufficientTargetQuotaLimits = true;
                }
            } else {
                if (totalQuoted > limit) {
                    result.success = false;
                    result.failureStates.insufficientTargetQuotaLimits = true;
                }
            }
        }
    }

    /// @dev Checks whether the target pool has sufficient liquidity and limits to cover the new debt.
    function _checkNewDebt(PreviewMigrationResult memory result) internal view {
        if (result.migrationParams.targetBorrowAmount == 0) {
            return;
        }

        address targetPool = ICreditManagerV3(result.migrationParams.targetCreditManager).pool();
        address sourcePool =
            ICreditManagerV3(ICreditAccountV3(result.migrationParams.sourceCreditAccount).creditManager()).pool();

        uint256 creditManagerDebtLimit =
            IPoolV3(targetPool).creditManagerDebtLimit(result.migrationParams.targetCreditManager);
        uint256 creditManagerBorrowed =
            IPoolV3(targetPool).creditManagerBorrowed(result.migrationParams.targetCreditManager);

        if (sourcePool != targetPool) {
            if (result.migrationParams.targetBorrowAmount + creditManagerBorrowed > creditManagerDebtLimit) {
                result.success = false;
                result.failureStates.insufficientTargetDebtLimit = true;
            }
        } else {
            if (creditManagerBorrowed > creditManagerDebtLimit) {
                result.success = false;
                result.failureStates.insufficientTargetDebtLimit = true;
            }
        }

        if (
            result.migrationParams.targetBorrowAmount
                > _computePoolBorrowableLiquidity(
                    targetPool, sourcePool != targetPool ? 0 : result.migrationParams.targetBorrowAmount
                )
        ) {
            result.success = false;
            result.failureStates.insufficientTargetBorrowLiquidity = true;
        }

        address creditFacade = ICreditManagerV3(result.migrationParams.targetCreditManager).creditFacade();
        (uint128 minDebt, uint128 maxDebt) = ICreditFacadeV3(creditFacade).debtLimits();

        if (result.migrationParams.targetBorrowAmount > maxDebt || result.migrationParams.targetBorrowAmount < minDebt)
        {
            result.success = false;
            result.failureStates.newTargetDebtOutOfLimits = true;
        }
    }

    /// @dev Computes the expected HF of the new account and checks whether it is solvent after migration.
    function _checkTargetHF(PreviewMigrationResult memory result) internal view {
        address priceOracle = ICreditManagerV3(result.migrationParams.targetCreditManager).priceOracle();
        address underlying = ICreditManagerV3(result.migrationParams.targetCreditManager).underlying();

        uint256 twvUSD = _getTargetTwvUSD(result, false, priceOracle, underlying);
        uint256 safeTwvUSD = _getTargetTwvUSD(result, true, priceOracle, underlying);
        uint256 totalDebtUSD =
            IPriceOracleV3(priceOracle).convertToUSD(result.migrationParams.targetBorrowAmount, underlying);

        if (totalDebtUSD == 0) {
            result.expectedTargetHF = type(uint16).max;
            result.expectedTargetSafeHF = type(uint16).max;
        } else {
            result.expectedTargetHF = twvUSD * PERCENTAGE_FACTOR / totalDebtUSD;
            result.expectedTargetSafeHF = safeTwvUSD * PERCENTAGE_FACTOR / totalDebtUSD;
        }

        if (result.expectedTargetHF < 10000) {
            result.success = false;
            result.failureStates.targetHFTooLow = true;
        }

        if (result.expectedTargetSafeHF < 10000) {
            result.success = false;
            result.failureStates.targetSafeHFTooLow = true;
        }
    }

    function _getTargetTwvUSD(PreviewMigrationResult memory result, bool safe, address priceOracle, address underlying)
        internal
        view
        returns (uint256 twvUSD)
    {
        for (uint256 i = 0; i < result.migrationParams.migratedCollaterals.length; i++) {
            address collateral = _getCollateralOrOverride(result.migrationParams.migratedCollaterals[i]);

            uint16 lt = ICreditManagerV3(result.migrationParams.targetCreditManager).liquidationThresholds(collateral);

            if (result.migrationParams.migratedCollaterals[i].underlyingInTarget) {
                twvUSD += IPriceOracleV3(priceOracle).convertToUSD(
                    result.migrationParams.migratedCollaterals[i].amount, collateral
                ) * lt / PERCENTAGE_FACTOR;
            } else {
                uint256 quotaUSD = IPriceOracleV3(priceOracle).convertToUSD(
                    result.migrationParams.migratedCollaterals[i].targetQuotaIncrease, underlying
                );

                uint256 valueUSD = safe
                    ? IPriceOracleV3(priceOracle).safeConvertToUSD(
                        result.migrationParams.migratedCollaterals[i].amount, collateral
                    )
                    : IPriceOracleV3(priceOracle).convertToUSD(
                        result.migrationParams.migratedCollaterals[i].amount, collateral
                    );

                uint256 wvUSD = valueUSD * lt / PERCENTAGE_FACTOR;

                twvUSD += wvUSD > quotaUSD ? quotaUSD : wvUSD;
            }
        }
    }

    function _getCollateralOrOverride(MigratedCollateral memory collateral) internal view returns (address) {
        if (collateral.phantomTokenParams.isPhantomToken) {
            PhantomTokenOverride memory ptOverride =
                IAccountMigratorBot(migratorBot).phantomTokenOverrides(collateral.collateral);
            if (ptOverride.newToken != address(0)) {
                return ptOverride.newToken;
            }
        }

        return collateral.collateral;
    }

    /// @dev Gets the target and deposited token of a phantom token safely, to account for tokens that may behave
    ///      weirdly on unknown function selector.
    function _getPhantomTokenInfo(address collateral) internal view returns (address target, address depositedToken) {
        (bool success, bytes memory returnData) = OptionalCall.staticCallOptionalSafe({
            target: collateral,
            data: abi.encodeWithSelector(IPhantomToken.getPhantomTokenInfo.selector),
            gasAllowance: 30_000
        });
        if (!success) return (address(0), address(0));

        (target, depositedToken) = abi.decode(returnData, (address, address));
    }

    /// @dev Computes the available liquidity in the pool, taking into account a possible uncrease in available liquidity after
    ///      account closure.
    function _computePoolBorrowableLiquidity(address pool, uint256 liquidityOffset) internal view returns (uint256) {
        uint256 availableLiquidity = IPoolV3(pool).availableLiquidity();
        uint256 expectedLiquidity = IPoolV3(pool).expectedLiquidity();

        address interestRateModel = IPoolV3(pool).interestRateModel();

        return IInterestRateModel(interestRateModel).availableToBorrow(
            expectedLiquidity, availableLiquidity + liquidityOffset
        );
    }

    /// @dev Applies the price updates for push price feeds.
    function _applyPriceUpdates(address creditManager, PriceUpdate[] memory priceUpdates) internal {
        address creditFacade = ICreditManagerV3(creditManager).creditFacade();
        address priceFeedStore = ICreditFacadeV3(creditFacade).priceFeedStore();

        IPriceFeedStore(priceFeedStore).updatePrices(priceUpdates);
    }

    function serialize() external view override returns (bytes memory) {
        return abi.encode(router);
    }
}
