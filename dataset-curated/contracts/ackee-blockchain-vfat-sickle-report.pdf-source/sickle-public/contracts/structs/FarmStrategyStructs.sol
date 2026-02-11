// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ZapIn, ZapOut } from "contracts/libraries/ZapLib.sol";
import { SwapParams } from "contracts/structs/LiquidityStructs.sol";

struct Farm {
    address stakingContract;
    uint256 poolIndex;
}

struct DepositParams {
    Farm farm;
    address[] tokensIn;
    uint256[] amountsIn;
    ZapIn zap;
    bytes extraData;
}

struct WithdrawParams {
    bytes extraData;
    ZapOut zap;
    address[] tokensOut;
}

struct HarvestParams {
    SwapParams[] swaps;
    bytes extraData;
    address[] tokensOut;
}

struct CompoundParams {
    Farm claimFarm;
    bytes claimExtraData;
    address[] rewardTokens;
    ZapIn zap;
    Farm depositFarm;
    bytes depositExtraData;
}

struct SimpleDepositParams {
    Farm farm;
    address lpToken;
    uint256 amountIn;
    bytes extraData;
}

struct SimpleHarvestParams {
    address[] rewardTokens;
    bytes extraData;
}

struct SimpleWithdrawParams {
    address lpToken;
    uint256 amountOut;
    bytes extraData;
}
