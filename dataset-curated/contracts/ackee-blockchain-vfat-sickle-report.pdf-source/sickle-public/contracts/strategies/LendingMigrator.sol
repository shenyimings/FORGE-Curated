// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20 } from
    "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FlashloanStrategy } from "contracts/strategies/FlashloanStrategy.sol";
import { ILendingConnector } from "contracts/interfaces/ILendingConnector.sol";
import {
    StrategyModule,
    SickleFactory,
    Sickle
} from "contracts/modules/StrategyModule.sol";
import { ConnectorRegistry } from "contracts/ConnectorRegistry.sol";
import { DelegateModule } from "contracts/modules/DelegateModule.sol";
import { FeesLib } from "contracts/libraries/FeesLib.sol";

struct MigratePositionParams {
    address sickleAddress;
    address borrowerAddress;
    address lendingMarket;
    address strategy;
}

library LendingMigratorFees {
    bytes4 constant Flashloan = bytes4(keccak256("LendingMigratorFlashloanFee"));
}

contract LendingMigrator is StrategyModule, DelegateModule {
    FlashloanStrategy public immutable flashloanStrategy;
    FeesLib public immutable feesLib;

    constructor(
        SickleFactory factory,
        ConnectorRegistry connectorRegistry,
        FlashloanStrategy flashloanStrategy_,
        FeesLib feesLib_
    ) StrategyModule(factory, connectorRegistry) {
        flashloanStrategy = flashloanStrategy_;
        feesLib = feesLib_;
    }

    /// @notice Uses a flash loan to repay a user's loan,
    /// transfers their cTokens to sickle,
    /// takes out a new loan to repay the flash loan
    function migrate_user_position(
        address lendingMarket,
        address approved,
        bytes32 referralCode,
        bytes calldata flashloanProvider,
        address[] calldata flashloanAssets,
        uint256[] calldata flashloanAmounts
    ) public {
        Sickle sickle = getOrDeploySickle(msg.sender, approved, referralCode);

        flashloan_repay_for(
            address(sickle),
            lendingMarket,
            msg.sender,
            flashloanProvider,
            flashloanAssets,
            flashloanAmounts
        );
    }

    /// Flashloan callbacks ///

    /// @notice Callback function for flashloan_repay_for()
    /// Repays a user's loan with a flashloan
    function flashloanRepayForCallback(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        bytes calldata extraData
    ) public onlyRegisteredSickle {
        if (msg.sender != address(flashloanStrategy)) {
            revert FlashloanStrategy.NotFlashloanStrategy();
        }

        MigratePositionParams memory params =
            abi.decode(extraData, (MigratePositionParams));

        uint256 assetIndex = amounts[0] > 0 ? 0 : 1;

        // charge flashloan fees
        _delegateTo(
            address(feesLib),
            abi.encodeCall(
                FeesLib.chargeFee,
                (
                    params.strategy,
                    LendingMigratorFees.Flashloan,
                    assets[assetIndex],
                    amounts[assetIndex]
                )
            )
        );

        _delegateTo(
            connectorRegistry.connectorOf(params.lendingMarket),
            abi.encodeCall(
                ILendingConnector.repayFor, // Repay all
                (params.lendingMarket, params.borrowerAddress, 0, "")
            )
        );

        SafeTransferLib.safeTransferFrom(
            params.lendingMarket,
            params.borrowerAddress,
            params.sickleAddress,
            IERC20(params.lendingMarket).balanceOf(params.borrowerAddress)
        );

        _delegateTo(
            connectorRegistry.connectorOf(params.lendingMarket),
            abi.encodeCall(
                ILendingConnector.borrow,
                (
                    params.lendingMarket,
                    amounts[assetIndex] + premiums[assetIndex],
                    ""
                )
            )
        );

        // send borrowed amounts to FlashloanStrategy contract for repayment
        SafeTransferLib.safeTransfer(
            assets[assetIndex],
            address(flashloanStrategy),
            amounts[assetIndex] + premiums[assetIndex]
        );
    }

    function flashloan_repay_for(
        address sickleAddress,
        address lendingMarket,
        address borrowerAddress,
        bytes calldata flashloanProvider,
        address[] calldata flashloanAssets,
        uint256[] calldata flashloanAmounts
    ) internal {
        // calculate expected premiums on flashloan amount
        uint256[] memory premiums = flashloanStrategy.calculatePremiums(
            flashloanProvider, flashloanAmounts
        );

        // borrow target repayment asset with a flashloan
        MigratePositionParams memory migratePositionParams =
        MigratePositionParams({
            sickleAddress: sickleAddress,
            borrowerAddress: borrowerAddress,
            lendingMarket: lendingMarket,
            strategy: address(this)
        });

        bytes memory encoded = abi.encodeCall(
            this.flashloanRepayForCallback,
            (
                flashloanAssets,
                flashloanAmounts,
                premiums,
                abi.encode(migratePositionParams)
            )
        );

        flashloanStrategy.initiateFlashloan(
            sickleAddress,
            flashloanProvider,
            flashloanAssets,
            flashloanAmounts,
            encoded
        );
    }
}
