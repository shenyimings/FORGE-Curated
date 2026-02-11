// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import {
    StrategyModule,
    SickleFactory,
    Sickle,
    ConnectorRegistry
} from "contracts/modules/StrategyModule.sol";
import { DelegateModule } from "contracts/modules/DelegateModule.sol";
import { ILendingConnector } from "contracts/interfaces/ILendingConnector.sol";
import { SwapLib } from "contracts/libraries/SwapLib.sol";
import { FeesLib } from "contracts/libraries/FeesLib.sol";
import { FlashloanStrategy } from "contracts/strategies/FlashloanStrategy.sol";
import { LendingStrategyFees } from
    "contracts/strategies/lending/LendingStructs.sol";
import { LendingStructs } from "contracts/strategies/lending/LendingStructs.sol";

contract FlashloanLib is DelegateModule, LendingStructs {
    struct FlashloanedAsset {
        address contractAddress;
        uint256 flashloanedAmount;
        uint256 premium;
    }

    ConnectorRegistry public immutable connectorRegistry;
    FlashloanStrategy public immutable flashloanStrategy;
    FeesLib public immutable feesLib;
    SwapLib public immutable swapLib;

    constructor(
        ConnectorRegistry connectorRegistry_,
        FlashloanStrategy flashloanStrategy_,
        FeesLib feesLib_,
        SwapLib swapLib_
    ) DelegateModule() {
        connectorRegistry = connectorRegistry_;
        flashloanStrategy = flashloanStrategy_;
        feesLib = feesLib_;
        swapLib = swapLib_;
    }

    /// Flashloan callbacks ///

    /// @notice Callback function for flashloan_deposit()
    /// Optionally swaps the flashloan for the collateral asset,
    /// supplies the loaned amount,
    /// borrows from the debt market (plus fee) to repay the flashloan
    function flashloanDepositCallback(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        bytes calldata extraData
    ) external {
        if (msg.sender != address(flashloanStrategy)) {
            revert FlashloanStrategy.NotFlashloanStrategy();
        }

        Sickle sickle = Sickle(payable(address(this)));

        // handling uniV2/uniV3 flashloans where token1 in the Pair is the one
        // being borrowed and flashloaned asset appears at index 1 of function
        // parameters
        uint256 assetIndex = amounts[0] > 0 ? 0 : 1;

        FlashloanedAsset memory flashloanedAsset = FlashloanedAsset({
            contractAddress: assets[assetIndex],
            flashloanedAmount: amounts[assetIndex],
            premium: premiums[assetIndex]
        });

        IncreaseParams memory increaseParams =
            abi.decode(extraData, (IncreaseParams));

        _chargeFlashloanFees(flashloanedAsset);

        if (increaseParams.optionalSwap.router != address(0)) {
            _delegateTo(
                address(swapLib),
                abi.encodeCall(SwapLib.swap, (increaseParams.optionalSwap))
            );
        }

        // updating sickle balance after fees and swap
        uint256 supplyAmount = feesLib.getBalance(sickle, increaseParams.token);

        _delegateTo(
            connectorRegistry.connectorOf(increaseParams.market),
            abi.encodeCall(
                ILendingConnector.mint,
                (increaseParams.market, supplyAmount, increaseParams.extraData)
            )
        );

        _delegateTo(
            connectorRegistry.connectorOf(increaseParams.market),
            abi.encodeCall(
                ILendingConnector.borrow,
                (
                    increaseParams.market,
                    flashloanedAsset.flashloanedAmount
                        + flashloanedAsset.premium,
                    increaseParams.extraData
                )
            )
        );

        // send borrowed amounts to FlashloanStrategy contract for repayment
        SafeTransferLib.safeTransfer(
            flashloanedAsset.contractAddress,
            address(flashloanStrategy),
            flashloanedAsset.flashloanedAmount + flashloanedAsset.premium
        );
    }

    /// @notice Callback function for flashloan_withdraw()
    /// Repays the loaned amount, withdraws collateral and repays the flashloan
    function flashloanWithdrawCallback(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        bytes calldata extraData
    ) public {
        if (msg.sender != address(flashloanStrategy)) {
            revert FlashloanStrategy.NotFlashloanStrategy();
        }

        DecreaseParams memory decreaseParams =
            abi.decode(extraData, (DecreaseParams));

        uint256 assetIndex = amounts[0] > 0 ? 0 : 1;

        FlashloanedAsset memory flashloanedAsset = FlashloanedAsset({
            contractAddress: assets[assetIndex],
            flashloanedAmount: amounts[assetIndex],
            premium: premiums[assetIndex]
        });

        _chargeFlashloanFees(flashloanedAsset);

        _delegateTo(
            connectorRegistry.connectorOf(decreaseParams.market),
            abi.encodeCall(
                ILendingConnector.repay,
                (
                    decreaseParams.market,
                    decreaseParams.repayAmount,
                    decreaseParams.extraData
                )
            )
        );

        if (decreaseParams.redeemAmount > 0) {
            _delegateTo(
                connectorRegistry.connectorOf(decreaseParams.market),
                abi.encodeCall(
                    ILendingConnector.redeem,
                    (
                        decreaseParams.market,
                        decreaseParams.redeemAmount,
                        decreaseParams.extraData
                    )
                )
            );
        }

        if (decreaseParams.optionalSwap.router != address(0)) {
            _delegateTo(
                address(swapLib),
                abi.encodeCall(SwapLib.swap, (decreaseParams.optionalSwap))
            );
        }

        // send borrowed amounts to FlashloanStrategy contract for repayment
        SafeTransferLib.safeTransfer(
            flashloanedAsset.contractAddress,
            address(flashloanStrategy),
            flashloanedAsset.flashloanedAmount + flashloanedAsset.premium
        );
    }

    function _chargeFlashloanFees(FlashloanedAsset memory params) internal {
        _delegateTo(
            address(feesLib),
            abi.encodeCall(
                FeesLib.chargeFee,
                (
                    address(flashloanStrategy),
                    LendingStrategyFees.Flashloan,
                    params.contractAddress,
                    params.flashloanedAmount
                )
            )
        );
    }
}
