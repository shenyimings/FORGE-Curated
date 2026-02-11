// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IUniV4, IPoolManager, PoolId} from "../interfaces/IUniV4.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solady/src/utils/SafeCastLib.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {MixedSignLib} from "../libraries/MixedSignLib.sol";
import {TickLib} from "../libraries/TickLib.sol";

struct PoolRewards {
    mapping(bytes32 uniPositionKey => Position position) positions;
    mapping(int24 tick => uint256 growthOutsideX128) rewardGrowthOutsideX128;
    uint256 globalGrowthX128;
}

struct Position {
    uint256 lastGrowthInsideX128;
}

using PoolRewardsLib for PoolRewards global;

library PoolRewardsLib {
    using IUniV4 for IPoolManager;
    using FixedPointMathLib for uint256;
    using MixedSignLib for uint128;
    using SafeCastLib for int256;
    using TickLib for int24;

    error RewardOverflow();
    error NegativeDeltaForAdd();
    error PositiveDeltaForRemove();

    function updateAfterLiquidityAdd(
        PoolRewards storage self,
        IPoolManager pm,
        PoolId id,
        int24 tickSpacing,
        address sender,
        ModifyLiquidityParams calldata params
    ) internal {
        uint256 growthInside;
        {
            int24 currentTick = pm.getSlot0(id).tick();
            uint256 lowerGrowthX128 = self.rewardGrowthOutsideX128[params.tickLower];
            uint256 upperGrowthX128 = self.rewardGrowthOutsideX128[params.tickUpper];

            if (currentTick < params.tickLower) {
                unchecked {
                    growthInside = lowerGrowthX128 - upperGrowthX128;
                }
            } else if (params.tickUpper <= currentTick) {
                // Following Uniswap's convention, if tick is below and uninitialized initialize growth
                // outside to global accumulator.
                if (!pm.isInitialized(id, params.tickLower, tickSpacing)) {
                    self.rewardGrowthOutsideX128[params.tickLower] =
                        lowerGrowthX128 = self.globalGrowthX128;
                }
                if (!pm.isInitialized(id, params.tickUpper, tickSpacing)) {
                    self.rewardGrowthOutsideX128[params.tickUpper] =
                        upperGrowthX128 = self.globalGrowthX128;
                }
                unchecked {
                    growthInside = upperGrowthX128 - lowerGrowthX128;
                }
            } else {
                if (!pm.isInitialized(id, params.tickLower, tickSpacing)) {
                    self.rewardGrowthOutsideX128[params.tickLower] =
                        lowerGrowthX128 = self.globalGrowthX128;
                }
                unchecked {
                    growthInside = self.globalGrowthX128 - lowerGrowthX128 - upperGrowthX128;
                }
            }
        }

        (Position storage position, bytes32 positionKey) =
            self.getPosition(sender, params.tickLower, params.tickUpper, params.salt);

        uint128 newLiquidity = pm.getPositionLiquidity(id, positionKey);
        if (!(params.liquidityDelta >= 0)) revert NegativeDeltaForAdd();
        uint128 lastLiquidity = newLiquidity.sub(params.liquidityDelta.toInt128());

        if (lastLiquidity == 0) {
            position.lastGrowthInsideX128 = growthInside;
        } else {
            // We want to update `lastGrowthInside` such that any previously accrued rewards are
            // preserved:
            // rewards' == rewards
            // (growth_inside - last') * L' = (growth_inside - last) * L
            //  growth_inside - last' = (growth_inside - last) * L / L'
            // last' = growth_inside - (growth_inside - last) * L / L'
            unchecked {
                uint256 lastGrowthAdjustment = FixedPointMathLib.fullMulDiv(
                    growthInside - position.lastGrowthInsideX128, lastLiquidity, newLiquidity
                );
                position.lastGrowthInsideX128 = growthInside - lastGrowthAdjustment;
            }
        }
    }

    function updateAfterLiquidityRemove(
        PoolRewards storage self,
        IPoolManager pm,
        PoolId id,
        address sender,
        ModifyLiquidityParams calldata params
    ) internal returns (uint256 rewards) {
        unchecked {
            (Position storage position, bytes32 positionKey) =
                self.getPosition(sender, params.tickLower, params.tickUpper, params.salt);
            int24 currentTick = pm.getSlot0(id).tick();
            uint256 growthInsideX128 =
                self.getGrowthInsideX128(currentTick, params.tickLower, params.tickUpper);

            uint128 newPositionLiquidity = pm.getPositionLiquidity(id, positionKey);
            if (!(0 >= params.liquidityDelta)) revert PositiveDeltaForRemove();
            uint128 lastPositionLiquidity =
                newPositionLiquidity.sub(params.liquidityDelta.toInt128());
            rewards = FixedPointMathLib.fullMulDivN(
                growthInsideX128 - position.lastGrowthInsideX128, lastPositionLiquidity, 128
            );

            // Only reset `lastGrowthInsideX128` if there were any rewards to avoid unnecessarily
            // rounding down someone's rewards.
            if (rewards > 0) {
                position.lastGrowthInsideX128 = growthInsideX128;
            }
        }
    }

    function getPendingPositionRewards(
        PoolRewards storage self,
        IPoolManager pm,
        PoolId id,
        address owner,
        int24 lowerTick,
        int24 upperTick,
        bytes32 salt
    ) internal view returns (uint256 rewards) {
        unchecked {
            (Position storage position, bytes32 positionKey) =
                self.getPosition(owner, lowerTick, upperTick, salt);
            int24 currentTick = pm.getSlot0(id).tick();
            uint256 growthInsideX128 = self.getGrowthInsideX128(currentTick, lowerTick, upperTick);
            uint128 positionLiquidity = pm.getPositionLiquidity(id, positionKey);
            rewards = FixedPointMathLib.fullMulDivN(
                growthInsideX128 - position.lastGrowthInsideX128, positionLiquidity, 128
            );
        }
    }

    function getPosition(
        PoolRewards storage self,
        address owner,
        int24 lowerTick,
        int24 upperTick,
        bytes32 salt
    ) internal view returns (Position storage position, bytes32 positionKey) {
        assembly ("memory-safe") {
            // Compute Uniswap position key `keccak256(abi.encodePacked(owner, lowerTick, upperTick, salt))`.
            mstore(0x06, upperTick)
            mstore(0x03, lowerTick)
            mstore(0x00, owner)
            // WARN: Free memory pointer temporarily invalid from here on.
            mstore(0x26, salt)
            positionKey := keccak256(12, add(add(3, 3), add(20, 32)))
            // Upper bytes of free memory pointer cleared.
            mstore(0x26, 0)
        }
        position = self.positions[positionKey];
    }

    function getGrowthInsideX128(
        PoolRewards storage self,
        int24 currentTick,
        int24 lowerTick,
        int24 upperTick
    ) internal view returns (uint256 growthInsideX128) {
        unchecked {
            uint256 lowerGrowthX128 = self.rewardGrowthOutsideX128[lowerTick];
            uint256 upperGrowthX128 = self.rewardGrowthOutsideX128[upperTick];

            if (currentTick < lowerTick) {
                return lowerGrowthX128 - upperGrowthX128;
            }
            if (upperTick <= currentTick) {
                return upperGrowthX128 - lowerGrowthX128;
            }

            return self.globalGrowthX128 - lowerGrowthX128 - upperGrowthX128;
        }
    }

    /// @dev Update growth values for a valid tick move from `prevTick` to `newTick`. Expects
    /// `prevTick` and `newTick` to be valid Uniswap ticks (defined as tick ∈ [TickMath.MIN_TICK;
    /// TickMath.MAX_TICK]).
    function updateAfterTickMove(
        PoolRewards storage self,
        PoolId id,
        IPoolManager pm,
        int24 prevTick,
        int24 newTick,
        int24 tickSpacing
    ) internal {
        if (newTick > prevTick) {
            // We assume the ticks are valid so no risk of underflow with these calls.
            if (newTick.normalizeUnchecked(tickSpacing) > prevTick) {
                _updateTickMoveUp(self, pm, id, prevTick, newTick, tickSpacing);
            }
        } else if (newTick < prevTick) {
            // We assume the ticks are valid so no risk of underflow with these calls.
            if (newTick < prevTick.normalizeUnchecked(tickSpacing)) {
                _updateTickMoveDown(self, pm, id, prevTick, newTick, tickSpacing);
            }
        }
    }

    function _updateTickMoveUp(
        PoolRewards storage self,
        IPoolManager pm,
        PoolId id,
        int24 tick,
        int24 newTick,
        int24 tickSpacing
    ) private {
        uint256 globalGrowthX128 = self.globalGrowthX128;
        while (true) {
            bool initialized;
            (initialized, tick) = pm.getNextTickGt(id, tick, tickSpacing);

            if (newTick < tick) break;
            if (initialized) {
                unchecked {
                    self.rewardGrowthOutsideX128[tick] =
                        globalGrowthX128 - self.rewardGrowthOutsideX128[tick];
                }
            }
        }
    }

    function _updateTickMoveDown(
        PoolRewards storage self,
        IPoolManager pm,
        PoolId id,
        int24 tick,
        int24 newTick,
        int24 tickSpacing
    ) private {
        uint256 globalGrowthX128 = self.globalGrowthX128;
        while (true) {
            bool initialized;
            (initialized, tick) = pm.getNextTickLe(id, tick, tickSpacing);

            if (tick <= newTick) break;

            if (initialized) {
                unchecked {
                    self.rewardGrowthOutsideX128[tick] =
                        globalGrowthX128 - self.rewardGrowthOutsideX128[tick];
                }
            }
            tick--;
        }
    }

    function getGrowthDelta(uint256 reward, uint256 liquidity)
        internal
        pure
        returns (uint256 growthDeltaX128)
    {
        if (!(reward < 1 << 128)) revert RewardOverflow();
        return (reward << 128).rawDiv(liquidity);
    }
}
