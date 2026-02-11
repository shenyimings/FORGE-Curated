// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { FlashloanInitiator } from
    "contracts/strategies/lending/FlashloanInitiator.sol";
import { FlashloanStrategy } from "contracts/strategies/FlashloanStrategy.sol";
import { TransferLib } from "contracts/libraries/TransferLib.sol";
import { Sickle } from "contracts/Sickle.sol";
import { SickleFactory } from "contracts/SickleFactory.sol";
import { ConnectorRegistry } from "contracts/ConnectorRegistry.sol";
import { StrategyModule } from "contracts/modules/StrategyModule.sol";

contract SimpleLendingStrategy is FlashloanInitiator, StrategyModule {
    TransferLib public immutable transferLib;

    address public immutable strategyAddress;

    constructor(
        SickleFactory factory,
        ConnectorRegistry connectorRegistry,
        FlashloanStrategy flashloanStrategy,
        TransferLib transferLib_
    )
        StrategyModule(factory, connectorRegistry)
        FlashloanInitiator(flashloanStrategy)
    {
        transferLib = transferLib_;
        strategyAddress = address(this);
    }

    /// FLASHLOAN FUNCTIONS ///

    /// @notice  Deposit and Borrow same asset
    /// Flashloan asset A, supply wallet funds + flashloan,
    /// borrow and repay flashloan
    function deposit(
        IncreaseParams calldata increaseParams,
        FlashloanParams calldata flashloanParams,
        address approved,
        bytes32 referralCode
    ) public payable flashloanParamCheck(flashloanParams) {
        Sickle sickle = getOrDeploySickle(msg.sender, approved, referralCode);

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = address(transferLib);
        data[0] = abi.encodeCall(
            TransferLib.transferTokenFromUser,
            (
                increaseParams.token,
                increaseParams.amountIn,
                strategyAddress,
                bytes4(0)
            )
        );

        sickle.multicall{ value: msg.value }(targets, data);

        flashloan_deposit(address(sickle), increaseParams, flashloanParams);
    }

    /// @notice Increase leverage (same asset)
    /// Flashloan asset A, supply flashloan, borrow and repay flashloan
    function increaseLeverage(
        IncreaseParams calldata increaseParams,
        FlashloanParams calldata flashloanParams
    ) public flashloanParamCheck(flashloanParams) {
        Sickle sickle = getSickle(msg.sender);

        flashloan_deposit(address(sickle), increaseParams, flashloanParams);
    }

    /// @notice Repay asset B loan with flashloan, withdraw collateral asset A
    function withdraw(
        DecreaseParams calldata decreaseParams,
        FlashloanParams calldata flashloanParams
    ) public flashloanParamCheck(flashloanParams) {
        Sickle sickle = getSickle(msg.sender);

        flashloan_withdraw(address(sickle), decreaseParams, flashloanParams);

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = address(transferLib);
        data[0] = abi.encodeCall(
            TransferLib.transferTokenToUser, decreaseParams.token
        );

        sickle.multicall(targets, data);
    }

    /// @notice Decrease leverage by repaying asset B loan with flashloan
    function decreaseLeverage(
        DecreaseParams calldata decreaseParams,
        FlashloanParams calldata flashloanParams
    ) public flashloanParamCheck(flashloanParams) {
        Sickle sickle = getSickle(msg.sender);

        flashloan_withdraw(address(sickle), decreaseParams, flashloanParams);
    }
}
