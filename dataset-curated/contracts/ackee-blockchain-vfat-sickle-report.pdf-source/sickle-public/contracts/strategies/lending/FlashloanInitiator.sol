// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { LendingStructs } from "contracts/strategies/lending/LendingStructs.sol";
import { IFlashloanCallback } from "contracts/interfaces/IFlashloanCallback.sol";
import { FlashloanStrategy } from "contracts/strategies/FlashloanStrategy.sol";

abstract contract FlashloanInitiator is LendingStructs {
    error ArrayLengthMismatch();

    modifier flashloanParamCheck(FlashloanParams calldata flashloanParams) {
        if (
            flashloanParams.flashloanAssets.length
                != flashloanParams.flashloanAmounts.length
        ) {
            revert ArrayLengthMismatch();
        }
        _;
    }

    FlashloanStrategy public immutable flashloanStrategy;

    constructor(FlashloanStrategy flashloanStrategy_) {
        flashloanStrategy = flashloanStrategy_;
    }

    /// Internal functions ///

    function flashloan_deposit(
        address sickleAddress,
        IncreaseParams calldata increaseParams,
        FlashloanParams calldata flashloanParams
    ) internal {
        uint256[] memory premiums = flashloanStrategy.calculatePremiums(
            flashloanParams.flashloanProvider, flashloanParams.flashloanAmounts
        );

        bytes memory callback = abi.encodeCall(
            IFlashloanCallback.flashloanDepositCallback,
            (
                flashloanParams.flashloanAssets,
                flashloanParams.flashloanAmounts,
                premiums,
                abi.encode(increaseParams)
            )
        );
        flashloanStrategy.initiateFlashloan(
            sickleAddress,
            flashloanParams.flashloanProvider,
            flashloanParams.flashloanAssets,
            flashloanParams.flashloanAmounts,
            callback
        );
    }

    function flashloan_withdraw(
        address sickleAddress,
        DecreaseParams calldata decreaseParams,
        FlashloanParams calldata flashLoanParams
    ) internal {
        // calculate expected premiums on flashloan amount
        uint256[] memory premiums = flashloanStrategy.calculatePremiums(
            flashLoanParams.flashloanProvider, flashLoanParams.flashloanAmounts
        );

        bytes memory encoded = abi.encodeCall(
            IFlashloanCallback.flashloanWithdrawCallback,
            (
                flashLoanParams.flashloanAssets,
                flashLoanParams.flashloanAmounts,
                premiums,
                abi.encode(decreaseParams)
            )
        );

        flashloanStrategy.initiateFlashloan(
            sickleAddress,
            flashLoanParams.flashloanProvider,
            flashLoanParams.flashloanAssets,
            flashLoanParams.flashloanAmounts,
            encoded
        );
    }
}
