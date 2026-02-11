// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {RewardInfo} from "../types/RewardInfo.sol";

interface IRewardsCompressor is IVersion {
    function getRewards(address creditAccount) external view returns (RewardInfo[] memory rewards);
}
