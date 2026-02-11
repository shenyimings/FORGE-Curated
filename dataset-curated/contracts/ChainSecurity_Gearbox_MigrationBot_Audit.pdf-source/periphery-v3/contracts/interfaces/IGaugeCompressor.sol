// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {MarketFilter} from "../types/Filters.sol";
import {GaugeInfo} from "../types/GaugeInfo.sol";

interface IGaugeCompressor is IVersion {
    function getGauges(MarketFilter memory filter, address staker) external view returns (GaugeInfo[] memory);

    function getGaugeInfo(address gauge, address staker) external view returns (GaugeInfo memory);
}
