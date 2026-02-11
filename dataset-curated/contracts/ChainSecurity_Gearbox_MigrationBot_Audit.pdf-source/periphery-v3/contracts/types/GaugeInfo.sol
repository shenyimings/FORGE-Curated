// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {BaseParams} from "./BaseState.sol";

struct GaugeInfo {
    address addr;
    address pool;
    string symbol;
    string name;
    address voter;
    address underlying;
    uint16 currentEpoch;
    uint16 epochLastUpdate;
    bool epochFrozen;
    GaugeQuotaParams[] quotaParams;
}

struct GaugeQuotaParams {
    address token;
    uint16 minRate;
    uint16 maxRate;
    uint96 totalVotesLpSide;
    uint96 totalVotesCaSide;
    uint96 stakerVotesLpSide;
    uint96 stakerVotesCaSide;
}
