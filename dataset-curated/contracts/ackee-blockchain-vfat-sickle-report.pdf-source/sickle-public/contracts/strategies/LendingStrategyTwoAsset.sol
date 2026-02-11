// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    FlashloanInitiator,
    FlashloanStrategy
} from "contracts/strategies/lending/FlashloanInitiator.sol";
import { ILendingConnector } from "contracts/interfaces/ILendingConnector.sol";
import {
    StrategyModule,
    SickleFactory,
    Sickle,
    ConnectorRegistry
} from "contracts/modules/StrategyModule.sol";
import { SwapParams } from "contracts/structs/LiquidityStructs.sol";
import { TransferLib } from "contracts/libraries/TransferLib.sol";
import { SwapLib } from "contracts/libraries/SwapLib.sol";
import { LendingStrategyFees } from
    "contracts/strategies/lending/LendingStructs.sol";

contract LendingStrategyTwoAsset is FlashloanInitiator, StrategyModule {
    error SwapPathNotSupported(); // 0x6b46d10f
    error InputArgumentsMismatch(); // 0xe3814450

    struct SupplyParams {
        // The collateral asset
        address market;
        address token;
        uint256 amountIn; // Amount transferred from user
        bytes extraData;
    }

    struct RedeemParams {
        // The collateral asset
        address market;
        address token;
        uint256 amount;
        bytes extraData;
    }

    TransferLib public immutable transferLib;
    SwapLib public immutable swapLib;

    address public immutable strategyAddress;

    constructor(
        SickleFactory factory,
        ConnectorRegistry connectorRegistry,
        FlashloanStrategy flashloanStrategy,
        TransferLib transferLib_,
        SwapLib swapLib_
    )
        FlashloanInitiator(flashloanStrategy)
        StrategyModule(factory, connectorRegistry)
    {
        transferLib = transferLib_;
        swapLib = swapLib_;
        strategyAddress = address(this);
    }

    /// FLASHLOAN FUNCTIONS ///

    /// Two-asset functions (Supply asset A, Borrow+Leverage asset B) ///

    /// @notice Deposit collateral asset A, flash loan and leverage asset B
    function deposit_and_borrow(
        SupplyParams calldata collateralTokenParams,
        IncreaseParams calldata increaseParams,
        FlashloanParams calldata flashloanParams,
        address approved,
        bytes32 referralCode
    ) public payable {
        Sickle sickle = getOrDeploySickle(msg.sender, approved, referralCode);
        address[] memory targets = new address[](2);
        targets[0] = address(transferLib);
        targets[1] = connectorRegistry.connectorOf(collateralTokenParams.market);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(
            TransferLib.transferTokenFromUser,
            (
                collateralTokenParams.token,
                collateralTokenParams.amountIn,
                strategyAddress,
                LendingStrategyFees.Deposit
            )
        );
        data[1] = abi.encodeCall(
            ILendingConnector.mint,
            (
                collateralTokenParams.market,
                collateralTokenParams.amountIn,
                collateralTokenParams.extraData
            )
        );

        sickle.multicall{ value: msg.value }(targets, data);

        flashloan_deposit(address(sickle), increaseParams, flashloanParams);
    }

    /// @notice Repay asset B loan with flashloan, withdraw collateral asset A
    function repay_and_withdraw(
        SwapParams calldata interestSwapParams,
        DecreaseParams calldata decreaseParams,
        FlashloanParams calldata flashloanParams,
        RedeemParams calldata collateralTokenParams,
        address[] memory sweepTokens
    ) public {
        Sickle sickle = getSickle(msg.sender);

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);

        targets[0] = connectorRegistry.connectorOf(collateralTokenParams.market);
        data[0] = abi.encodeCall(
            ILendingConnector.redeemUnderlying,
            (
                collateralTokenParams.market,
                interestSwapParams.amountIn,
                collateralTokenParams.extraData
            )
        );

        targets[1] = address(swapLib);
        data[1] = abi.encodeCall(SwapLib.swap, (interestSwapParams));

        sickle.multicall(targets, data);

        flashloan_withdraw(address(sickle), decreaseParams, flashloanParams);

        targets[0] = connectorRegistry.connectorOf(collateralTokenParams.market);
        data[0] = abi.encodeCall(
            ILendingConnector.redeem,
            (
                collateralTokenParams.market,
                collateralTokenParams.amount,
                collateralTokenParams.extraData
            )
        );

        targets[1] = address(transferLib);
        data[1] =
            abi.encodeCall(TransferLib.transferTokensToUser, (sweepTokens));

        sickle.multicall(targets, data);
    }
}
