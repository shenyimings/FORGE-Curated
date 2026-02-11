// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SwapParams } from "contracts/libraries/SwapLib.sol";

library LendingStrategyFees {
    bytes4 constant Deposit = bytes4(keccak256("LendingStrategyDepositFee"));
    bytes4 constant Withdraw = bytes4(keccak256("LendingStrategyWithdrawFee"));
    bytes4 constant Harvest = bytes4(keccak256("LendingStrategyHarvestFee"));
    bytes4 constant Compound = bytes4(keccak256("LendingStrategyCompoundFee"));
    bytes4 constant Flashloan = bytes4(keccak256("LendingStrategyFlashloanFee"));
}

contract LendingStructs {
    struct FlashloanParams {
        bytes flashloanProvider;
        address[] flashloanAssets;
        uint256[] flashloanAmounts;
    }

    struct IncreaseParams {
        address market;
        address token;
        uint256 amountIn; // Amount transferred from user
        bytes extraData;
        SwapParams optionalSwap; // Swap the flashloan asset to the supplied
            // token
    }

    struct DecreaseParams {
        address market;
        address token;
        uint256 repayAmount;
        uint256 redeemAmount;
        bytes extraData;
        SwapParams optionalSwap; // After redeeming, swap to pay the flashloan
    }
}
