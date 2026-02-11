// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Sickle } from "contracts/Sickle.sol";
import {
    Farm,
    HarvestParams,
    CompoundParams,
    WithdrawParams
} from "contracts/structs/FarmStrategyStructs.sol";

interface IAutomation {
    function harvestFor(
        Sickle sickle,
        Farm calldata farm,
        HarvestParams calldata params,
        address[] calldata sweepTokens
    ) external;

    function compoundFor(
        Sickle sickle,
        CompoundParams calldata params,
        address[] calldata sweepTokens
    ) external;

    function exitFor(
        Sickle sickle,
        Farm calldata farm,
        HarvestParams calldata harvestParams,
        address[] calldata harvestSweepTokens,
        WithdrawParams calldata withdrawParams,
        address[] calldata withdrawSweepTokens
    ) external;
}
