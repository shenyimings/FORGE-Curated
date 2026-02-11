// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Farm } from "contracts/structs/FarmStrategyStructs.sol";
import { ZapIn } from "contracts/structs/ZapStructs.sol";
import {
    NftPosition,
    SimpleNftHarvest
} from "contracts/structs/NftFarmStrategyStructs.sol";
import { SwapParams } from "contracts/structs/LiquidityStructs.sol";
import { NftZapIn } from "contracts/structs/NftZapStructs.sol";

struct ClaimParams {
    Farm claimFarm;
    bytes claimExtraData;
}

struct NftClaimParams {
    NftPosition position;
    SimpleNftHarvest harvest;
}

struct MultiCompoundParams {
    ClaimParams[] claims;
    NftClaimParams[] nftClaims;
    address[] rewardTokens;
    ZapIn zap;
    Farm depositFarm;
    bytes depositExtraData;
}

struct NftMultiCompoundParams {
    ClaimParams[] claims;
    NftClaimParams[] nftClaims;
    address[] rewardTokens;
    NftZapIn zap;
    NftPosition depositPosition;
    bytes depositExtraData;
    bool compoundInPlace;
}

struct MultiHarvestParams {
    ClaimParams[] claims;
    NftClaimParams[] nftClaims;
    SwapParams[] swaps;
    address[] tokensOut;
}
