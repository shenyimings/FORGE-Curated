// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IPool } from "contracts/interfaces/external/aerodrome/IPool.sol";

import { Sickle } from "contracts/Sickle.sol";

struct PositionKey {
    Sickle sickle;
    address stakingContract;
    uint256 poolIndex;
}

enum RewardBehavior {
    None,
    Harvest,
    Compound
}

struct RewardConfig {
    RewardBehavior rewardBehavior;
    address harvestTokenOut;
}

struct ExitConfig {
    uint256 triggerPriceHigh;
    uint256 triggerPriceLow;
    uint256 triggerReserves0;
    uint256 triggerReserves1;
    address exitTokenOutLow;
    address exitTokenOutHigh;
    uint256 priceImpactBP;
    uint256 slippageBP;
}

/**
 * Settings for automating an ERC20 position
 * @param pool: Uniswap or Aerodrome vAMM/sAMM pair for the position (requires
 * token0/token1/getReserves functions)
 * @param router: Router for the pair (requires connector registration)
 * @param automateRewards: Whether to automatically harvest or compound rewards
 * for this position, regardless of rebalance settings.
 * @param rewardConfig: Configuration for reward automation
 * Harvest as-is, harvest and convert to a different token, or compound into the
 * position.
 * @param autoExit: Whether to automatically exit the position when it goes out
 * of
 * range
 * @param exitConfig: Configuration for the above
 */
struct PositionSettings {
    IPool pair;
    address router;
    bool automateRewards;
    RewardConfig rewardConfig;
    bool autoExit;
    ExitConfig exitConfig;
}
