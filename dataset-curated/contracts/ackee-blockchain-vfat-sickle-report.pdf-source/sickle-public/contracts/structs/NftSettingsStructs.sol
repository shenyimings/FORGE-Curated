// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { INonfungiblePositionManager } from
    "contracts/interfaces/external/uniswap/INonfungiblePositionManager.sol";
import { IUniswapV3Pool } from
    "contracts/interfaces/external/uniswap/IUniswapV3Pool.sol";

import { Sickle } from "contracts/Sickle.sol";
import {
    RewardConfig,
    RewardBehavior
} from "contracts/structs/PositionSettingsStructs.sol";

struct NftKey {
    Sickle sickle;
    INonfungiblePositionManager nftManager;
    uint256 tokenId;
}

struct ExitConfig {
    int24 triggerTickLow;
    int24 triggerTickHigh;
    address exitTokenOutLow;
    address exitTokenOutHigh;
    uint256 priceImpactBP;
    uint256 slippageBP;
}

/**
 * @notice Settings for automatic rebalancing
 * @param tickSpacesBelow: Position width measured in tick spaces below
 * Default: 0 (Position doesn't include any tick spaces below current)
 * @param tickSpacesAbove: Position width measured in tick spaces above
 * Default: 0 (Position doesn't include any tick spaces above current)
 * @param bufferTicksBelow: Difference from position tickLower to
 * rebalance below. Can be negative (rebalance before position goes under
 * range)
 * Default: 0 (always rebalance if tick < tickLower)
 * @param bufferTicksAbove: Difference from position tickUpper to
 * rebalance above. Can be negative (rebalance before position goes above range)
 * Default: 0 (always rebalance if tick >= tickUpper)
 * @param dustBP: Dust allowance in basis points
 * @param priceImpactBP: Price impact allowance in basis points
 * @param slippageBP: Slippage allowance in basis points
 * @param cutoffTickLow: Stop rebalancing below this tick
 * default: MIN_TICK (no stop loss)
 * @param cutoffTickHigh: Stop rebalancing above this tick
 * default: MAX_TICK (no stop loss)
 * @param delayMin: Delay in minutes before rebalancing
 * @param rewardConfig: Configuration for handling rewards when rebalancing
 */
struct RebalanceConfig {
    uint24 tickSpacesBelow;
    uint24 tickSpacesAbove;
    int24 bufferTicksBelow;
    int24 bufferTicksAbove;
    uint256 dustBP;
    uint256 priceImpactBP;
    uint256 slippageBP;
    int24 cutoffTickLow;
    int24 cutoffTickHigh;
    uint8 delayMin;
    RewardConfig rewardConfig;
}

/**
 * Settings for automating an NFT position
 * @param autoRebalance: Whether to rebalance automatically when position goes
 * out of range
 * @param rebalanceConfig: Configuration for the above
 * @param automateRewards: Whether to automatically harvest or compound rewards
 * for this position, regardless of rebalance settings.
 * @param rewardConfig: Configuration for reward automation
 * Harvest as-is, harvest and convert to a different token, or compound into the
 * position.
 */
struct NftSettings {
    IUniswapV3Pool pool;
    bool autoRebalance;
    RebalanceConfig rebalanceConfig;
    bool automateRewards;
    RewardConfig rewardConfig;
    bool autoExit;
    ExitConfig exitConfig;
}
