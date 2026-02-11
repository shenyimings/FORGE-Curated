// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Sickle } from "contracts/Sickle.sol";
import { SickleFactory } from "contracts/SickleFactory.sol";
import { ConnectorRegistry } from "contracts/ConnectorRegistry.sol";
import { FlashloanStrategy } from "contracts/strategies/FlashloanStrategy.sol";
import { FlashloanInitiator } from
    "contracts/strategies/lending/FlashloanInitiator.sol";
import { TransferLib } from "contracts/libraries/TransferLib.sol";
import { ZapLib, ZapIn, ZapOut } from "contracts/libraries/ZapLib.sol";
import { FeesLib } from "contracts/libraries/FeesLib.sol";
import { IFarmConnector, Farm } from "contracts/interfaces/IFarmConnector.sol";
import { LendingStrategyFees } from
    "contracts/strategies/lending/LendingStructs.sol";
import { StrategyModule } from "contracts/modules/StrategyModule.sol";

contract LendingStrategy is FlashloanInitiator, StrategyModule {
    error SwapPathNotSupported(); // 0x6b46d10f
    error InputArgumentsMismatch(); // 0xe3814450

    struct Libraries {
        TransferLib transferLib;
        ZapLib zapLib;
        FeesLib feesLib;
    }

    struct DepositParams {
        address tokenIn;
        uint256 amountIn;
        ZapIn zap;
    }

    struct WithdrawParams {
        address tokenOut;
        ZapOut zap;
    }

    struct CompoundParams {
        Farm farm;
        bytes extraData;
        ZapIn zap;
    }

    TransferLib public immutable transferLib;
    ZapLib public immutable zapLib;
    FeesLib public immutable feesLib;

    address public immutable strategyAddress;

    constructor(
        SickleFactory factory,
        ConnectorRegistry connectorRegistry,
        FlashloanStrategy flashloanStrategy,
        Libraries memory libraries
    )
        FlashloanInitiator(flashloanStrategy)
        StrategyModule(factory, connectorRegistry)
    {
        transferLib = libraries.transferLib;
        zapLib = libraries.zapLib;
        feesLib = libraries.feesLib;
        strategyAddress = address(this);
    }

    /// FLASHLOAN FUNCTIONS ///

    /// @notice Deposit using a zap
    /// Deposit asset X, swap for asset A
    /// Flashloan asset A, or flashloan asset Z and swap for asset A
    /// Supply asset A, borrow asset A + fees, repay flashloan
    function deposit(
        DepositParams calldata depositParams,
        IncreaseParams calldata increaseParams,
        FlashloanParams calldata flashloanParams,
        address[] memory sweepTokens,
        address approved,
        bytes32 referralCode
    ) public payable flashloanParamCheck(flashloanParams) {
        Sickle sickle = getOrDeploySickle(msg.sender, approved, referralCode);

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);

        targets[0] = address(transferLib);
        data[0] = abi.encodeCall(
            TransferLib.transferTokenFromUser,
            (
                depositParams.tokenIn,
                depositParams.amountIn,
                strategyAddress,
                LendingStrategyFees.Deposit
            )
        );

        targets[1] = address(zapLib);
        data[1] = abi.encodeCall(ZapLib.zapIn, (depositParams.zap));

        sickle.multicall{ value: msg.value }(targets, data);

        flashloan_deposit(address(sickle), increaseParams, flashloanParams);

        if (sweepTokens.length > 0) {
            targets = new address[](1);
            data = new bytes[](1);

            targets[0] = address(transferLib);
            data[0] =
                abi.encodeCall(TransferLib.transferTokensToUser, (sweepTokens));

            sickle.multicall(targets, data);
        }
    }

    /// @notice Repay asset A loan with flashloan, withdraw collateral asset A
    function withdraw(
        DecreaseParams calldata decreaseParams,
        FlashloanParams calldata flashloanParams,
        WithdrawParams calldata withdrawParams,
        address[] memory sweepTokens
    ) public {
        Sickle sickle = getSickle(msg.sender);

        flashloan_withdraw(address(sickle), decreaseParams, flashloanParams);

        address[] memory targets = new address[](3);
        bytes[] memory data = new bytes[](3);

        targets[0] = address(zapLib);
        data[0] = abi.encodeCall(ZapLib.zapOut, (withdrawParams.zap));

        targets[1] = address(feesLib);
        data[1] = abi.encodeCall(
            FeesLib.chargeFee,
            (
                strategyAddress,
                LendingStrategyFees.Withdraw,
                withdrawParams.tokenOut,
                0
            )
        );

        targets[2] = address(transferLib);
        data[2] =
            abi.encodeCall(TransferLib.transferTokensToUser, (sweepTokens));

        sickle.multicall(targets, data);
    }

    /// @notice Claim accrued rewards, sell for loan token and leverage with
    /// flashloan
    function compound(
        CompoundParams calldata compoundParams,
        IncreaseParams calldata increaseParams,
        FlashloanParams calldata flashloanParams,
        address[] memory sweepTokens
    ) public {
        Sickle sickle = getSickle(msg.sender);

        // delegatecall callback function
        address[] memory targets = new address[](3);
        bytes[] memory data = new bytes[](3);

        targets[0] =
            connectorRegistry.connectorOf(compoundParams.farm.stakingContract);
        data[0] = abi.encodeCall(
            IFarmConnector.claim,
            (compoundParams.farm, compoundParams.extraData)
        );

        targets[1] = address(zapLib);
        data[1] = abi.encodeCall(ZapLib.zapIn, (compoundParams.zap));

        address flashloanToken = flashloanParams.flashloanAssets[0]
            == address(0)
            ? flashloanParams.flashloanAssets[1]
            : flashloanParams.flashloanAssets[0];
        targets[2] = address(feesLib);
        data[2] = abi.encodeCall(
            FeesLib.chargeFee,
            (strategyAddress, LendingStrategyFees.Compound, flashloanToken, 0)
        );

        sickle.multicall(targets, data);

        flashloan_deposit(address(sickle), increaseParams, flashloanParams);

        if (sweepTokens.length > 0) {
            targets = new address[](1);
            data = new bytes[](1);

            targets[0] = address(transferLib);
            data[0] =
                abi.encodeCall(TransferLib.transferTokensToUser, (sweepTokens));

            sickle.multicall(targets, data);
        }
    }
}
