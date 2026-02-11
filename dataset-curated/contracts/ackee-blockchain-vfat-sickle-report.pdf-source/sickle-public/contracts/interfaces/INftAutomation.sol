// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IUniswapV3Pool } from
    "contracts/interfaces/external/uniswap/IUniswapV3Pool.sol";
import { Sickle } from "contracts/Sickle.sol";
import {
    NftPosition,
    NftRebalance,
    NftHarvest,
    NftWithdraw,
    NftCompound
} from "contracts/structs/NftFarmStrategyStructs.sol";

interface INftAutomation {
    function rebalanceFor(
        Sickle sickle,
        NftRebalance calldata rebalance,
        address[] calldata sweepTokens
    ) external;

    function harvestFor(
        Sickle sickle,
        NftPosition calldata position,
        NftHarvest calldata params
    ) external;

    function compoundFor(
        Sickle sickle,
        NftPosition calldata position,
        NftCompound calldata params,
        bool inPlace,
        address[] memory sweepTokens
    ) external;

    function exitFor(
        Sickle sickle,
        NftPosition calldata position,
        NftHarvest calldata harvestParams,
        NftWithdraw calldata withdrawParams,
        address[] memory sweepTokens
    ) external;
}
