// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    StrategyModule,
    SickleFactory,
    Sickle,
    ConnectorRegistry
} from "contracts/modules/StrategyModule.sol";
import { IFarmConnector, Farm } from "contracts/interfaces/IFarmConnector.sol";
import {
    Farm,
    DepositParams,
    HarvestParams,
    WithdrawParams,
    CompoundParams,
    SimpleDepositParams,
    SimpleWithdrawParams,
    SimpleHarvestParams
} from "contracts/structs/FarmStrategyStructs.sol";
import { IFeesLib } from "contracts/interfaces/libraries/IFeesLib.sol";
import { ISwapLib } from "contracts/interfaces/libraries/ISwapLib.sol";
import { ITransferLib } from "contracts/interfaces/libraries/ITransferLib.sol";
import { IPositionSettingsLib } from
    "contracts/interfaces/libraries/IPositionSettingsLib.sol";
import { IZapLib } from "contracts/interfaces/libraries/IZapLib.sol";
import { IAutomation } from "contracts/interfaces/IAutomation.sol";
import { IPositionSettingsRegistry } from
    "contracts/interfaces/IPositionSettingsRegistry.sol";
import {
    PositionKey,
    PositionSettings
} from "contracts/structs/PositionSettingsStructs.sol";
import { FarmStrategyEvents } from "contracts/events/FarmStrategyEvents.sol";

library FarmStrategyFees {
    bytes4 constant Deposit = bytes4(keccak256("FarmDepositFee"));
    bytes4 constant Harvest = bytes4(keccak256("FarmHarvestFee"));
    bytes4 constant Compound = bytes4(keccak256("FarmCompoundFee"));
    bytes4 constant Withdraw = bytes4(keccak256("FarmWithdrawFee"));
    bytes4 constant HarvestFor = bytes4(keccak256("FarmHarvestForFee"));
    bytes4 constant CompoundFor = bytes4(keccak256("FarmCompoundForFee"));
}

contract FarmStrategy is StrategyModule, IAutomation, FarmStrategyEvents {
    struct Libraries {
        ITransferLib transferLib;
        ISwapLib swapLib;
        IFeesLib feesLib;
        IZapLib zapLib;
        IPositionSettingsLib positionSettingsLib;
    }

    IZapLib public immutable zapLib;
    ISwapLib public immutable swapLib;
    ITransferLib public immutable transferLib;
    IFeesLib public immutable feesLib;
    IPositionSettingsLib public immutable positionSettingsLib;

    IPositionSettingsRegistry public immutable positionSettingsRegistry;

    address public immutable strategyAddress;

    constructor(
        SickleFactory factory,
        ConnectorRegistry connectorRegistry,
        Libraries memory libraries,
        IPositionSettingsRegistry _positionSettingsRegistry
    ) StrategyModule(factory, connectorRegistry) {
        zapLib = libraries.zapLib;
        swapLib = libraries.swapLib;
        transferLib = libraries.transferLib;
        feesLib = libraries.feesLib;
        positionSettingsLib = libraries.positionSettingsLib;
        positionSettingsRegistry = _positionSettingsRegistry;
        strategyAddress = address(this);
    }

    /**
     * @notice Deposits tokens into the specified farm and sets position
     * settings.
     * @param params The parameters for the deposit, including farm details and
     * token amounts.
     * @param positionSettings The settings for the position, including reward
     * configurations and exit configurations.
     * @param sweepTokens The list of tokens to be swept.
     * @param approved The address approved to manage the position (used on
     * first deposit only).
     * @param referralCode The referral code for tracking referrals (used on
     * first deposit only).
     */
    function deposit(
        DepositParams calldata params,
        PositionSettings calldata positionSettings,
        address[] calldata sweepTokens,
        address approved,
        bytes32 referralCode
    ) public payable {
        Sickle sickle = getOrDeploySickle(msg.sender, approved, referralCode);

        bytes4 fee =
            params.zap.swaps.length > 0 ? FarmStrategyFees.Deposit : bytes4(0);

        _increase(sickle, params, sweepTokens, fee);

        _set_position_settings(sickle, params.farm, positionSettings);

        emit SickleDeposited(
            sickle, params.farm.stakingContract, params.farm.poolIndex
        );
    }

    /**
     * @notice Increases the position by depositing additional tokens into the
     * specified farm.
     * @param params The parameters for the deposit, including farm details and
     * token amounts.
     * @param sweepTokens The list of tokens to be swept.
     */
    function increase(
        DepositParams calldata params,
        address[] calldata sweepTokens
    ) public payable {
        Sickle sickle = getSickle(msg.sender);

        bytes4 fee =
            params.zap.swaps.length > 0 ? FarmStrategyFees.Deposit : bytes4(0);

        _increase(sickle, params, sweepTokens, fee);

        emit SickleDeposited(
            sickle, params.farm.stakingContract, params.farm.poolIndex
        );
    }

    /**
     * @notice Compounds the position by claiming rewards and reinvesting them
     * into the specified farm.
     * @param params The parameters for the compound, including farm details and
     * reward tokens.
     * @param sweepTokens The list of tokens to be swept.
     */
    function compound(
        CompoundParams calldata params,
        address[] calldata sweepTokens
    ) public {
        Sickle sickle = getSickle(msg.sender);

        _compound(sickle, params, sweepTokens);

        emit SickleCompounded(
            sickle,
            params.claimFarm.stakingContract,
            params.claimFarm.poolIndex,
            params.depositFarm.stakingContract,
            params.depositFarm.poolIndex
        );
    }

    /**
     * @notice Withdraws tokens from the specified farm.
     * @param farm The farm details.
     * @param params The parameters for the withdrawal, including zap details.
     * @param sweepTokens The list of tokens to be swept.
     */
    function withdraw(
        Farm calldata farm,
        WithdrawParams calldata params,
        address[] calldata sweepTokens
    ) public {
        Sickle sickle = getSickle(msg.sender);

        bytes4 fee =
            params.zap.swaps.length > 0 ? FarmStrategyFees.Withdraw : bytes4(0);

        _withdraw(sickle, farm, params, sweepTokens, fee);

        emit SickleWithdrawn(sickle, farm.stakingContract, farm.poolIndex);
    }

    /**
     * @notice Claims rewards from the specified farm.
     * @param farm The farm details.
     * @param params The parameters for the harvest, including zap details.
     * @param sweepTokens The list of tokens to be swept.
     */
    function harvest(
        Farm calldata farm,
        HarvestParams calldata params,
        address[] calldata sweepTokens
    ) public {
        Sickle sickle = getSickle(msg.sender);

        _harvest(sickle, farm, params, sweepTokens, FarmStrategyFees.Harvest);

        emit SickleHarvested(sickle, farm.stakingContract, farm.poolIndex);
    }

    /**
     * @notice Exits the position by claiming rewards and withdrawing tokens
     * from the specified farm.
     * @param farm The farm details.
     * @param harvestParams The parameters for the harvest, including zap
     * details.
     * @param harvestSweepTokens The list of tokens to be swept from the
     * harvest.
     * @param withdrawParams The parameters for the withdrawal, including zap
     * details.
     * @param withdrawSweepTokens The list of tokens to be swept from the
     * withdrawal.
     */
    function exit(
        Farm calldata farm,
        HarvestParams calldata harvestParams,
        address[] calldata harvestSweepTokens,
        WithdrawParams calldata withdrawParams,
        address[] calldata withdrawSweepTokens
    ) public {
        Sickle sickle = getSickle(msg.sender);

        _exit(
            sickle,
            farm,
            harvestParams,
            harvestSweepTokens,
            withdrawParams,
            withdrawSweepTokens,
            FarmStrategyFees.Harvest
        );

        emit SickleExited(sickle, farm.stakingContract, farm.poolIndex);
    }

    /* Simple (non-zap) */

    /**
     * @notice Deposits tokens into the specified farm and sets position
     * settings.
     * @param params The parameters for the deposit, including farm details and
     * token amounts.
     * @param positionSettings The settings for the position, including reward
     * configurations and exit configurations.
     * @param approved The address approved to manage the position (used on
     * first deposit only).
     * @param referralCode The referral code for tracking referrals (used on
     * first deposit only).
     */
    function simpleDeposit(
        SimpleDepositParams calldata params,
        PositionSettings calldata positionSettings,
        address approved,
        bytes32 referralCode
    ) public payable {
        Sickle sickle = getOrDeploySickle(msg.sender, approved, referralCode);

        _simple_increase(sickle, params);

        _set_position_settings(sickle, params.farm, positionSettings);

        emit SickleDeposited(
            sickle, params.farm.stakingContract, params.farm.poolIndex
        );
    }

    /**
     * @notice Increases the position by depositing additional tokens into the
     * specified farm.
     * @param params The parameters for the deposit, including farm details and
     * token amounts.
     */
    function simpleIncrease(
        SimpleDepositParams calldata params
    ) public {
        Sickle sickle = getSickle(msg.sender);

        _simple_increase(sickle, params);

        emit SickleDeposited(
            sickle, params.farm.stakingContract, params.farm.poolIndex
        );
    }

    /**
     * @notice Claims rewards from the specified farm.
     * @param farm The farm details.
     * @param params The parameters for the harvest, including zap details.
     */
    function simpleHarvest(
        Farm calldata farm,
        SimpleHarvestParams calldata params
    ) external {
        Sickle sickle = getSickle(msg.sender);

        _simple_harvest(sickle, farm, params);

        emit SickleHarvested(sickle, farm.stakingContract, farm.poolIndex);
    }

    /**
     * @notice Withdraws tokens from the specified farm.
     * @param farm The farm details.
     * @param params The parameters for the withdrawal, including zap details.
     */
    function simpleWithdraw(
        Farm calldata farm,
        SimpleWithdrawParams calldata params
    ) public {
        Sickle sickle = getSickle(msg.sender);

        _simple_withdraw(sickle, farm, params);

        emit SickleWithdrawn(sickle, farm.stakingContract, farm.poolIndex);
    }

    /**
     * @notice Exits the position by claiming rewards and withdrawing tokens
     * from the specified farm.
     * @param farm The farm details.
     * @param harvestParams The parameters for the harvest, including zap
     * details.
     * @param withdrawParams The parameters for the withdrawal, including zap
     * details.
     */
    function simpleExit(
        Farm calldata farm,
        SimpleHarvestParams calldata harvestParams,
        SimpleWithdrawParams calldata withdrawParams
    ) external {
        Sickle sickle = getSickle(msg.sender);

        _simple_harvest(sickle, farm, harvestParams);
        _simple_withdraw(sickle, farm, withdrawParams);

        emit SickleExited(sickle, farm.stakingContract, farm.poolIndex);
    }

    /* Automation */

    /**
     * @notice Claims rewards from the specified farm.
     * Used by Automation contract only.
     * @param farm The farm details.
     * @param params The parameters for the harvest, including zap details.
     * @param sweepTokens The list of tokens to be swept.
     */
    function harvestFor(
        Sickle sickle,
        Farm calldata farm,
        HarvestParams calldata params,
        address[] calldata sweepTokens
    ) external override onlyApproved(sickle) {
        positionSettingsRegistry.validateHarvestFor(
            PositionKey(sickle, farm.stakingContract, farm.poolIndex)
        );
        _harvest(sickle, farm, params, sweepTokens, FarmStrategyFees.HarvestFor);
    }

    /**
     * @notice Compounds the position by claiming rewards and reinvesting them
     * into the specified farm.
     * @param params The parameters for the compound, including farm details and
     * reward tokens.
     * @param sweepTokens The list of tokens to be swept.
     */
    function compoundFor(
        Sickle sickle,
        CompoundParams calldata params,
        address[] calldata sweepTokens
    ) external override onlyApproved(sickle) {
        positionSettingsRegistry.validateCompoundFor(
            PositionKey(
                sickle,
                params.claimFarm.stakingContract,
                params.claimFarm.poolIndex
            )
        );
        _compound(sickle, params, sweepTokens);
    }

    /**
     * @notice Exits the position by claiming rewards and withdrawing tokens
     * from the specified farm.
     * @param farm The farm details.
     * @param harvestParams The parameters for the harvest, including zap
     * details.
     * @param harvestSweepTokens The list of tokens to be swept from the
     * harvest.
     * @param withdrawParams The parameters for the withdrawal, including zap
     * details.
     * @param withdrawSweepTokens The list of tokens to be swept from the
     * withdrawal.
     */
    function exitFor(
        Sickle sickle,
        Farm calldata farm,
        HarvestParams calldata harvestParams,
        address[] calldata harvestSweepTokens,
        WithdrawParams calldata withdrawParams,
        address[] calldata withdrawSweepTokens
    ) external override onlyApproved(sickle) {
        positionSettingsRegistry.validateExitFor(
            PositionKey(sickle, farm.stakingContract, farm.poolIndex)
        );
        _exit(
            sickle,
            farm,
            harvestParams,
            harvestSweepTokens,
            withdrawParams,
            withdrawSweepTokens,
            FarmStrategyFees.HarvestFor
        );
    }

    /* Simple Private */

    function _simple_increase(
        Sickle sickle,
        SimpleDepositParams calldata params
    ) private {
        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);

        targets[0] = address(transferLib);
        data[0] = abi.encodeCall(
            ITransferLib.transferTokenFromUser,
            (params.lpToken, params.amountIn, strategyAddress, bytes4(0))
        );

        targets[1] = connectorRegistry.connectorOf(params.farm.stakingContract);
        data[1] = abi.encodeCall(
            IFarmConnector.deposit,
            (params.farm, params.lpToken, params.extraData)
        );

        sickle.multicall(targets, data);
    }

    function _simple_withdraw(
        Sickle sickle,
        Farm calldata farm,
        SimpleWithdrawParams calldata params
    ) private {
        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);

        address farmConnector =
            connectorRegistry.connectorOf(farm.stakingContract);
        targets[0] = farmConnector;
        data[0] = abi.encodeCall(
            IFarmConnector.withdraw, (farm, params.amountOut, params.extraData)
        );

        targets[1] = address(transferLib);
        data[1] =
            abi.encodeCall(ITransferLib.transferTokenToUser, (params.lpToken));

        sickle.multicall(targets, data);
    }

    function _simple_harvest(
        Sickle sickle,
        Farm calldata farm,
        SimpleHarvestParams calldata params
    ) private {
        address[] memory targets = new address[](3);
        bytes[] memory data = new bytes[](3);

        address farmConnector =
            connectorRegistry.connectorOf(farm.stakingContract);
        targets[0] = farmConnector;
        data[0] = abi.encodeCall(IFarmConnector.claim, (farm, params.extraData));

        targets[1] = address(feesLib);
        data[1] = abi.encodeCall(
            IFeesLib.chargeFees,
            (strategyAddress, FarmStrategyFees.Harvest, params.rewardTokens)
        );

        targets[2] = address(transferLib);
        data[2] = abi.encodeCall(
            ITransferLib.transferTokensToUser, (params.rewardTokens)
        );

        sickle.multicall(targets, data);
    }

    /* Private */

    function _set_position_settings(
        Sickle sickle,
        Farm calldata farm,
        PositionSettings calldata settings
    ) private {
        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = address(positionSettingsLib);
        data[0] = abi.encodeCall(
            positionSettingsLib.setPositionSettings,
            (positionSettingsRegistry, farm, settings)
        );

        sickle.multicall(targets, data);
    }

    function _increase(
        Sickle sickle,
        DepositParams calldata params,
        address[] calldata sweepTokens,
        bytes4 fee
    ) private {
        address[] memory targets = new address[](4);
        bytes[] memory data = new bytes[](4);

        targets[0] = address(transferLib);
        data[0] = abi.encodeCall(
            ITransferLib.transferTokensFromUser,
            (params.tokensIn, params.amountsIn, strategyAddress, fee)
        );

        targets[1] = address(zapLib);
        data[1] = abi.encodeCall(IZapLib.zapIn, (params.zap));

        targets[2] = connectorRegistry.connectorOf(params.farm.stakingContract);
        data[2] = abi.encodeCall(
            IFarmConnector.deposit,
            (
                params.farm,
                params.zap.addLiquidityParams.lpToken,
                params.extraData
            )
        );

        targets[3] = address(transferLib);
        data[3] =
            abi.encodeCall(ITransferLib.transferTokensToUser, (sweepTokens));

        sickle.multicall{ value: msg.value }(targets, data);
    }

    function _harvest(
        Sickle sickle,
        Farm calldata farm,
        HarvestParams calldata params,
        address[] calldata sweepTokens,
        bytes4 fee
    ) private {
        address[] memory targets = new address[](4);
        bytes[] memory data = new bytes[](4);

        address farmConnector =
            connectorRegistry.connectorOf(farm.stakingContract);
        targets[0] = farmConnector;
        data[0] = abi.encodeCall(IFarmConnector.claim, (farm, params.extraData));

        targets[1] = address(swapLib);
        data[1] = abi.encodeCall(ISwapLib.swapMultiple, (params.swaps));

        targets[2] = address(feesLib);
        data[2] = abi.encodeCall(
            IFeesLib.chargeFees, (strategyAddress, fee, params.tokensOut)
        );

        targets[3] = address(transferLib);
        data[3] =
            abi.encodeCall(ITransferLib.transferTokensToUser, (sweepTokens));

        sickle.multicall(targets, data);
    }

    function _withdraw(
        Sickle sickle,
        Farm calldata farm,
        WithdrawParams calldata params,
        address[] calldata sweepTokens,
        bytes4 fee
    ) private {
        address[] memory targets = new address[](4);
        bytes[] memory data = new bytes[](4);

        address farmConnector =
            connectorRegistry.connectorOf(farm.stakingContract);
        targets[0] = farmConnector;
        data[0] = abi.encodeCall(
            IFarmConnector.withdraw,
            (
                farm,
                params.zap.removeLiquidityParams.lpAmountIn,
                params.extraData
            )
        );

        targets[1] = address(zapLib);
        data[1] = abi.encodeCall(IZapLib.zapOut, (params.zap));

        targets[2] = address(feesLib);
        data[2] = abi.encodeCall(
            IFeesLib.chargeFees, (strategyAddress, fee, params.tokensOut)
        );

        targets[3] = address(transferLib);
        data[3] =
            abi.encodeCall(ITransferLib.transferTokensToUser, (sweepTokens));

        sickle.multicall(targets, data);
    }

    function _exit(
        Sickle sickle,
        Farm calldata farm,
        HarvestParams calldata harvestParams,
        address[] calldata harvestSweepTokens,
        WithdrawParams calldata withdrawParams,
        address[] calldata withdrawSweepTokens,
        bytes4 harvestFee
    ) private {
        _harvest(sickle, farm, harvestParams, harvestSweepTokens, harvestFee);
        _withdraw(
            sickle,
            farm,
            withdrawParams,
            withdrawSweepTokens,
            FarmStrategyFees.Withdraw
        );
    }

    function _compound(
        Sickle sickle,
        CompoundParams calldata params,
        address[] calldata sweepTokens
    ) private {
        address[] memory targets = new address[](5);
        bytes[] memory data = new bytes[](5);

        address farmConnector =
            connectorRegistry.connectorOf(params.claimFarm.stakingContract);

        targets[0] = farmConnector;
        data[0] = abi.encodeCall(
            IFarmConnector.claim, (params.claimFarm, params.claimExtraData)
        );

        targets[1] = address(feesLib);
        data[1] = abi.encodeCall(
            IFeesLib.chargeFees,
            (strategyAddress, FarmStrategyFees.Compound, params.rewardTokens)
        );

        targets[2] = address(zapLib);
        data[2] = abi.encodeCall(IZapLib.zapIn, (params.zap));

        address depositConnector =
            connectorRegistry.connectorOf(params.depositFarm.stakingContract);

        targets[3] = depositConnector;
        data[3] = abi.encodeCall(
            IFarmConnector.deposit,
            (
                params.depositFarm,
                params.zap.addLiquidityParams.lpToken,
                params.depositExtraData
            )
        );

        targets[4] = address(transferLib);
        data[4] =
            abi.encodeCall(ITransferLib.transferTokensToUser, (sweepTokens));

        sickle.multicall(targets, data);
    }
}
