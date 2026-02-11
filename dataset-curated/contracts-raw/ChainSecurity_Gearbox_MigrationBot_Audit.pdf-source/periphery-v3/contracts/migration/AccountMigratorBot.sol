// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IAccountMigratorBot, IAccountMigratorAdapter} from "../interfaces/IAccountMigratorBot.sol";
import {
    MigrationParams,
    PreviewMigrationResult,
    MigratedCollateral,
    PhantomTokenParams,
    PhantomTokenOverride
} from "../types/AccountMigrationTypes.sol";
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
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
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
import {ReentrancyGuardTrait} from "@gearbox-protocol/core-v3/contracts/traits/ReentrancyGuardTrait.sol";

contract AccountMigratorBot is Ownable, ReentrancyGuardTrait, IAccountMigratorBot {
    using SafeERC20 for IERC20;
    using BitMask for uint256;
    using CreditLogic for CollateralDebtData;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant override version = 3_10;
    bytes32 public constant override contractType = "BOT::ACCOUNT_MIGRATOR";

    uint192 public constant override requiredPermissions =
        EXTERNAL_CALLS_PERMISSION | UPDATE_QUOTA_PERMISSION | DECREASE_DEBT_PERMISSION;

    address internal activeCreditAccount = INACTIVE_CREDIT_ACCOUNT_ADDRESS;

    mapping(address => PhantomTokenOverride) internal _phantomTokenOverrides;

    EnumerableSet.AddressSet internal _overridenPhantomTokens;

    address public immutable mcFactory;

    address public immutable contractsRegisterOld;

    constructor(address _mcFactory, address _ioProxy, address _contractsRegisterOld) {
        _transferOwnership(_ioProxy);
        mcFactory = _mcFactory;
        contractsRegisterOld = _contractsRegisterOld;
    }

    /// EXECUTION LOGIC

    /// @notice Migrates a credit account from one credit manager to another.
    /// @param params The migration parameters.
    /// @param priceUpdates The price updates to apply.
    function migrateCreditAccount(MigrationParams memory params, PriceUpdate[] memory priceUpdates)
        external
        nonReentrant
    {
        address sourceCreditManager = ICreditAccountV3(params.sourceCreditAccount).creditManager();

        _validateParameters(sourceCreditManager, params);

        _applyPriceUpdates(params.targetCreditManager, priceUpdates);
        _checkAccountOwner(sourceCreditManager, params);

        address creditFacade = ICreditManagerV3(sourceCreditManager).creditFacade();
        address adapter = ICreditManagerV3(sourceCreditManager).contractToAdapter(address(this));

        MultiCall[] memory calls = _getClosingMultiCalls(creditFacade, adapter, params);

        _unlockAdapter(params.sourceCreditAccount, adapter);
        ICreditFacadeV3(creditFacade).botMulticall(params.sourceCreditAccount, calls);
        _lockAdapter(adapter);
    }

    /// @notice Transfer the collaterals from the previous credit account and opens a new credit account with required calls.
    ///         Can only be used when the adapter is unlocked and by the active credit account.
    function migrate(MigrationParams memory params) external {
        if (msg.sender != activeCreditAccount) {
            revert("MigratorBot: caller is not the active credit account");
        }

        uint256[] memory balances = _transferCollaterals(params);

        address targetCreditFacade = ICreditManagerV3(params.targetCreditManager).creditFacade();

        MultiCall[] memory calls = _getOpeningMultiCalls(targetCreditFacade, params, balances);

        ICreditFacadeV3(targetCreditFacade).openCreditAccount(params.accountOwner, calls, 0);
    }

    /// @dev Transfers the collaterals from the previous credit account and returns the unique tokens and the transferred balances.
    function _transferCollaterals(MigrationParams memory params) internal returns (uint256[] memory) {
        uint256[] memory minimalAmounts = _getMinimalAssetAmounts(params);

        uint256 len = params.uniqueTransferredTokens.length;

        uint256[] memory balances = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            address token = params.uniqueTransferredTokens[i];

            balances[i] = IERC20(token).balanceOf(msg.sender);

            if (balances[i] < minimalAmounts[i]) {
                revert("MigratorBot: insufficient token balance to cover expected amount");
            }

            IERC20(token).safeTransferFrom(msg.sender, address(this), balances[i]);
            IERC20(token).forceApprove(params.targetCreditManager, balances[i]);
        }

        return balances;
    }

    /// @dev Gets the aggregated amounts for each transferred collateral or PT underlying.
    function _getMinimalAssetAmounts(MigrationParams memory params) internal pure returns (uint256[] memory) {
        uint256[] memory totalAmounts = new uint256[](params.uniqueTransferredTokens.length);

        uint256 len = params.migratedCollaterals.length;

        for (uint256 i = 0; i < len; i++) {
            address token = params.migratedCollaterals[i].phantomTokenParams.isPhantomToken
                ? params.migratedCollaterals[i].phantomTokenParams.underlying
                : params.migratedCollaterals[i].collateral;

            uint256 amount = params.migratedCollaterals[i].phantomTokenParams.isPhantomToken
                ? params.migratedCollaterals[i].phantomTokenParams.underlyingAmount
                : params.migratedCollaterals[i].amount;

            uint256 index = _indexOf(params.uniqueTransferredTokens, token);
            totalAmounts[index] += amount;
        }

        return totalAmounts;
    }

    /// @dev Gets the index of an item in an array.
    function _indexOf(address[] memory array, address item) internal pure returns (uint256) {
        uint256 len = array.length;

        for (uint256 i = 0; i < len; i++) {
            if (array[i] == item) return i;
        }

        revert("MigratorBot: item not found in array");
    }

    /// @dev Checks whether the caller is the owner of the source credit account.
    function _checkAccountOwner(address sourceCreditManager, MigrationParams memory params) internal view {
        address sourceAccountOwner =
            ICreditManagerV3(sourceCreditManager).getBorrowerOrRevert(params.sourceCreditAccount);

        if (msg.sender != sourceAccountOwner || msg.sender != params.accountOwner) {
            revert("MigratorBot: caller is not the account owner");
        }
    }

    /// @dev Builds a MultiCall array to close the source credit account.
    function _getClosingMultiCalls(address creditFacade, address adapter, MigrationParams memory params)
        internal
        view
        returns (MultiCall[] memory calls)
    {
        uint256 collateralsLength = params.migratedCollaterals.length;

        calls = new MultiCall[](
            params.numRemoveQuotasCalls + params.numPhantomTokenCalls + (params.targetBorrowAmount > 0 ? 1 : 0) + 1
        );

        uint256 k = 0;

        address sourceCreditManager = ICreditAccountV3(params.sourceCreditAccount).creditManager();

        for (uint256 i = 0; i < collateralsLength; i++) {
            if (
                params.migratedCollaterals[i].phantomTokenParams.isPhantomToken
                    && params.migratedCollaterals[i].amount > 1
            ) {
                calls[k++] = _getPhantomTokenWithdrawalCall(
                    sourceCreditManager, params.migratedCollaterals[i].collateral, params.migratedCollaterals[i].amount
                );
            }
        }

        calls[k++] = MultiCall({target: adapter, callData: abi.encodeCall(IAccountMigratorAdapter.migrate, (params))});

        for (uint256 i = 0; i < collateralsLength; i++) {
            if (!params.migratedCollaterals[i].underlyingInSource) {
                calls[k++] = MultiCall({
                    target: creditFacade,
                    callData: abi.encodeCall(
                        ICreditFacadeV3Multicall.updateQuota, (params.migratedCollaterals[i].collateral, type(int96).min, 0)
                    )
                });
            }
        }

        if (params.targetBorrowAmount > 0) {
            calls[k] = MultiCall({
                target: creditFacade,
                callData: abi.encodeCall(ICreditFacadeV3Multicall.decreaseDebt, (type(uint256).max))
            });
        }

        return calls;
    }

    /// @dev Builds a MultiCall array to open the target credit account.
    function _getOpeningMultiCalls(address creditFacade, MigrationParams memory params, uint256[] memory balances)
        internal
        view
        returns (MultiCall[] memory calls)
    {
        calls = new MultiCall[](
            params.numAddCollateralCalls + params.numIncreaseQuotaCalls + params.numPhantomTokenCalls
                + params.underlyingSwapCalls.length + params.extraOpeningCalls.length
                + (params.targetBorrowAmount > 0 ? 2 : 0)
        );

        uint256 uniqueTokensLength = params.uniqueTransferredTokens.length;

        uint256 k = 0;

        for (uint256 i = 0; i < uniqueTokensLength; i++) {
            address token = params.uniqueTransferredTokens[i];

            if (balances[i] > 1) {
                calls[k++] = MultiCall({
                    target: creditFacade,
                    callData: abi.encodeCall(ICreditFacadeV3Multicall.addCollateral, (token, balances[i]))
                });
            }
        }

        uint256 collateralsLength = params.migratedCollaterals.length;

        for (uint256 i = 0; i < collateralsLength; i++) {
            if (
                params.migratedCollaterals[i].phantomTokenParams.isPhantomToken
                    && params.migratedCollaterals[i].amount > 1
            ) {
                calls[k++] = _getPhantomTokenDepositCall(
                    params.targetCreditManager,
                    params.migratedCollaterals[i].collateral,
                    params.migratedCollaterals[i].amount
                );
            }
        }

        if (params.targetBorrowAmount > 0) {
            calls[k++] = MultiCall({
                target: creditFacade,
                callData: abi.encodeCall(ICreditFacadeV3Multicall.increaseDebt, (params.targetBorrowAmount))
            });
        }

        for (uint256 i = 0; i < collateralsLength; i++) {
            if (params.migratedCollaterals[i].targetQuotaIncrease > 0) {
                calls[k++] = MultiCall({
                    target: creditFacade,
                    callData: abi.encodeCall(
                        ICreditFacadeV3Multicall.updateQuota,
                        (
                            _getCollateralOrOverride(params.migratedCollaterals[i].collateral),
                            int96(params.migratedCollaterals[i].targetQuotaIncrease),
                            params.migratedCollaterals[i].targetQuotaIncrease
                        )
                    )
                });
            }
        }

        uint256 underlyingSwapCallsLength = params.underlyingSwapCalls.length;

        for (uint256 i = 0; i < underlyingSwapCallsLength; i++) {
            calls[k++] = params.underlyingSwapCalls[i];
        }

        if (params.targetBorrowAmount > 0) {
            calls[k++] = _getUnderlyingWithdrawCall(creditFacade, params);
        }

        uint256 extraOpeningCallsLength = params.extraOpeningCalls.length;

        for (uint256 i = 0; i < extraOpeningCallsLength; i++) {
            calls[k++] = params.extraOpeningCalls[i];
        }
    }

    /// @dev Builds a call to withdraw an amount of underlying equal to the source account's debt.
    function _getUnderlyingWithdrawCall(address creditFacade, MigrationParams memory params)
        internal
        view
        returns (MultiCall memory call)
    {
        address underlying = ICreditManagerV3(ICreditAccountV3(params.sourceCreditAccount).creditManager()).underlying();
        uint256 totalDebt = _getAccountTotalDebt(params.sourceCreditAccount);

        return MultiCall({
            target: creditFacade,
            callData: abi.encodeCall(
                ICreditFacadeV3Multicall.withdrawCollateral, (underlying, totalDebt, params.sourceCreditAccount)
            )
        });
    }

    /// @dev Builds a call to deposit a phantom token.
    function _getPhantomTokenDepositCall(address creditManager, address collateral, uint256 amount)
        internal
        view
        returns (MultiCall memory call)
    {
        PhantomTokenOverride memory ptOverride = _phantomTokenOverrides[collateral];

        if (ptOverride.newToken != address(0)) {
            (address target,) = _getPhantomTokenInfo(ptOverride.newToken);

            address adapter = ICreditManagerV3(creditManager).contractToAdapter(target);

            return MultiCall({
                target: adapter,
                callData: abi.encodeCall(IPhantomTokenAdapter.depositPhantomToken, (ptOverride.newToken, amount))
            });
        }

        (address target,) = _getPhantomTokenInfo(collateral);

        if (target == address(0)) revert("MigratorBot: phantom token is not valid");

        address adapter = ICreditManagerV3(creditManager).contractToAdapter(target);

        return MultiCall({
            target: adapter,
            callData: abi.encodeCall(IPhantomTokenAdapter.depositPhantomToken, (collateral, amount))
        });
    }

    /// @dev Builds a call to withdraw a phantom token.
    function _getPhantomTokenWithdrawalCall(address creditManager, address collateral, uint256 amount)
        internal
        view
        returns (MultiCall memory call)
    {
        PhantomTokenOverride memory ptOverride = _phantomTokenOverrides[collateral];

        if (ptOverride.newToken != address(0)) {
            (address target,) = _getPhantomTokenInfo(collateral);

            address adapter = ICreditManagerV3(creditManager).contractToAdapter(target);

            return MultiCall({target: adapter, callData: ptOverride.withdrawalCallData});
        }

        (address target,) = _getPhantomTokenInfo(collateral);

        if (target == address(0)) revert("MigratorBot: phantom token is not valid");

        address adapter = ICreditManagerV3(creditManager).contractToAdapter(target);

        return MultiCall({
            target: adapter,
            callData: abi.encodeCall(IPhantomTokenAdapter.withdrawPhantomToken, (collateral, amount))
        });
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

    /// @dev Computes the total debt of a credit account.
    function _getAccountTotalDebt(address creditAccount) internal view returns (uint256) {
        address creditManager = ICreditAccountV3(creditAccount).creditManager();

        CollateralDebtData memory cdd =
            ICreditManagerV3(creditManager).calcDebtAndCollateral(creditAccount, CollateralCalcTask.DEBT_ONLY);

        return cdd.calcTotalDebt();
    }

    /// @dev Applies the price updates for push price feeds.
    function _applyPriceUpdates(address creditManager, PriceUpdate[] memory priceUpdates) internal {
        address creditFacade = ICreditManagerV3(creditManager).creditFacade();
        address priceFeedStore = ICreditFacadeV3(creditFacade).priceFeedStore();

        IPriceFeedStore(priceFeedStore).updatePrices(priceUpdates);
    }

    /// @dev Unlocks the account migration adapter.
    function _unlockAdapter(address creditAccount, address adapter) internal {
        activeCreditAccount = creditAccount;
        IAccountMigratorAdapter(adapter).unlock();
    }

    /// @dev Locks the account migration adapter.
    function _lockAdapter(address adapter) internal {
        activeCreditAccount = INACTIVE_CREDIT_ACCOUNT_ADDRESS;
        IAccountMigratorAdapter(adapter).lock();
    }

    /// @dev Validates the migration parameters. Checks that:
    ///      - the source credit manager is valid
    ///      - the target credit manager is valid
    ///      - the migrated tokens are collaterals in the source CM
    ///      - the phantom token underlyings are correct
    ///      - the migration adapter is not called in the underlying swap calls or extra opening calls
    function _validateParameters(address sourceCreditManager, MigrationParams memory params) internal view {
        _validateCreditManager(sourceCreditManager);
        _validateCreditManager(params.targetCreditManager);

        for (uint256 i = 0; i < params.migratedCollaterals.length; i++) {
            try ICreditManagerV3(sourceCreditManager).getTokenMaskOrRevert(params.migratedCollaterals[i].collateral)
            returns (uint256) {} catch {
                revert("MigratorBot: migrated token is not a valid collateral");
            }

            if (params.migratedCollaterals[i].phantomTokenParams.isPhantomToken) {
                PhantomTokenOverride memory ptOverride =
                    _phantomTokenOverrides[params.migratedCollaterals[i].collateral];

                if (
                    ptOverride.underlying != address(0)
                        && ptOverride.underlying != params.migratedCollaterals[i].phantomTokenParams.underlying
                ) {
                    revert("MigratorBot: incorrect phantom token underlying");
                }

                (, address underlying) = _getPhantomTokenInfo(ptOverride.newToken);
                if (params.migratedCollaterals[i].phantomTokenParams.underlying != underlying) {
                    revert("MigratorBot: incorrect phantom token underlying");
                }
            }
        }

        address targetAdapter = ICreditManagerV3(params.targetCreditManager).contractToAdapter(address(this));

        if (targetAdapter != address(0)) {
            uint256 len = params.underlyingSwapCalls.length;

            for (uint256 i = 0; i < len; i++) {
                if (params.underlyingSwapCalls[i].target == targetAdapter) {
                    revert("MigratorBot: arbitrary call to migration adapter");
                }
            }

            len = params.extraOpeningCalls.length;

            for (uint256 i = 0; i < len; i++) {
                if (params.extraOpeningCalls[i].target == targetAdapter) {
                    revert("MigratorBot: arbitrary call to migration adapter");
                }
            }
        }

        uint256 uniqueTokensLength = params.uniqueTransferredTokens.length;
        uint256 migratedCollateralsLength = params.migratedCollaterals.length;

        for (uint256 i = 0; i < uniqueTokensLength; i++) {
            bool found = false;
            for (uint256 j = 0; j < migratedCollateralsLength; j++) {
                address token = params.migratedCollaterals[j].phantomTokenParams.isPhantomToken
                    ? params.migratedCollaterals[j].phantomTokenParams.underlying
                    : params.migratedCollaterals[j].collateral;

                if (params.uniqueTransferredTokens[i] == token) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                revert("MigratorBot: transferred token not found among collaterals");
            }
        }

        for (uint256 i = 0; i < migratedCollateralsLength; i++) {
            bool found = false;
            for (uint256 j = 0; j < uniqueTokensLength; j++) {
                address token = params.migratedCollaterals[i].phantomTokenParams.isPhantomToken
                    ? params.migratedCollaterals[i].phantomTokenParams.underlying
                    : params.migratedCollaterals[i].collateral;

                if (token == params.uniqueTransferredTokens[j]) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                revert("MigratorBot: migrated collateral not found among transferred tokens");
            }
        }
    }

    /// @dev Validates that the credit manager is known by Gearbox protocol.
    function _validateCreditManager(address creditManager) internal view {
        uint256 cmVersion = IVersion(creditManager).version();

        if (cmVersion < 3_10) {
            if (!IContractsRegister(contractsRegisterOld).isCreditManager(creditManager)) {
                revert("MigratorBot: credit manager is not valid");
            }
        } else {
            address creditConfigurator = ICreditManagerV3(creditManager).creditConfigurator();
            address acl = ACLTrait(creditConfigurator).acl();
            address mc = Ownable(acl).owner();

            address contractsRegister = IMarketConfigurator(mc).contractsRegister();

            if (
                !IMarketConfiguratorFactory(mcFactory).isMarketConfigurator(mc)
                    || !IContractsRegister(contractsRegister).isCreditManager(creditManager)
            ) {
                revert("MigratorBot: credit manager is not valid");
            }
        }
    }

    /// @dev Returns either the collateral token or its PT override token.
    function _getCollateralOrOverride(address collateral) internal view returns (address) {
        PhantomTokenOverride memory ptOverride = _phantomTokenOverrides[collateral];

        if (ptOverride.newToken != address(0)) {
            return ptOverride.newToken;
        }

        return collateral;
    }

    function serialize() external view override returns (bytes memory) {
        address[] memory overridenPhantomTokens = _overridenPhantomTokens.values();

        PhantomTokenOverride[] memory ptOverrides = new PhantomTokenOverride[](overridenPhantomTokens.length);

        for (uint256 i = 0; i < overridenPhantomTokens.length; i++) {
            ptOverrides[i] = _phantomTokenOverrides[overridenPhantomTokens[i]];
        }

        return abi.encode(mcFactory, ptOverrides);
    }

    function setPhantomTokenOverride(
        address phantomToken,
        address newToken,
        address underlying,
        bytes calldata withdrawalCallData
    ) external onlyOwner {
        _phantomTokenOverrides[phantomToken] =
            PhantomTokenOverride({newToken: newToken, underlying: underlying, withdrawalCallData: withdrawalCallData});

        _overridenPhantomTokens.add(phantomToken);
    }

    function phantomTokenOverrides(address phantomToken) external view override returns (PhantomTokenOverride memory) {
        return _phantomTokenOverrides[phantomToken];
    }
}
