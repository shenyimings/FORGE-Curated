// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";

import {PoolId} from "../types/PoolId.sol";
import {MarginState} from "../types/MarginState.sol";
import {DoubleEndedQueue} from "../libraries/external/DoubleEndedQueue.sol";
import {IMarginBase} from "../interfaces/IMarginBase.sol";
import {Math} from "../libraries/Math.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {StageMath} from "../libraries/StageMath.sol";
import {CustomRevert} from "../libraries/CustomRevert.sol";

abstract contract MarginBase is IMarginBase, Owned {
    using SafeCast for *;
    using StageMath for uint256;
    using CustomRevert for bytes4;
    using DoubleEndedQueue for DoubleEndedQueue.Uint256Deque;

    error LiquidityLocked();

    MarginState public marginState;
    address public marginController;
    mapping(PoolId id => uint256) private lastStageTimestampStore; // Timestamp of the last stage
    mapping(PoolId id => DoubleEndedQueue.Uint256Deque) private liquidityLockedQueue;

    modifier onlyManager() {
        if (msg.sender != marginController) Unauthorized.selector.revertWith();
        _;
    }

    uint24 private constant MAX_PRICE_MOVE_PER_SECOND = 3000; // 0.3%/second
    uint24 private constant RATE_BASE = 50000;
    uint24 private constant USE_MIDDLE_LEVEL = 400000;
    uint24 private constant USE_HIGH_LEVEL = 800000;
    uint24 private constant M_LOW = 10;
    uint24 private constant M_MIDDLE = 100;
    uint24 private constant M_HIGH = 10000;
    uint24 private constant STAGE_DURATION = 12 hours; // default: 12 hour seconds
    uint24 private constant STAGE_SIZE = 5; // default: 5 stages
    uint24 private constant STAGE_LEAVE_PART = 5; // default: 5, meaning 20% of the total liquidity is free

    constructor(address initialOwner) Owned(initialOwner) {
        MarginState _marginState = marginState.setMaxPriceMovePerSecond(MAX_PRICE_MOVE_PER_SECOND);
        _marginState = _marginState.setRateBase(RATE_BASE);
        _marginState = _marginState.setUseMiddleLevel(USE_MIDDLE_LEVEL);
        _marginState = _marginState.setUseHighLevel(USE_HIGH_LEVEL);
        _marginState = _marginState.setMLow(M_LOW);
        _marginState = _marginState.setMMiddle(M_MIDDLE);
        _marginState = _marginState.setMHigh(M_HIGH);
        _marginState = _marginState.setStageDuration(STAGE_DURATION);
        _marginState = _marginState.setStageSize(STAGE_SIZE);
        _marginState = _marginState.setStageLeavePart(STAGE_LEAVE_PART);
        marginState = _marginState;
    }

    /// @notice Gets the amount of released and next-to-be-released liquidity.
    /// @dev Internal view function to calculate the amount of liquidity that is currently released and the amount that will be released in the next stage.
    /// @param id The ID of the pool.
    /// @return releasedLiquidity The amount of liquidity that is currently released.
    /// @return nextReleasedLiquidity The amount of liquidity that will be released in the next stage.
    function _getReleasedLiquidity(PoolId id)
        internal
        view
        returns (uint128 releasedLiquidity, uint128 nextReleasedLiquidity)
    {
        releasedLiquidity = type(uint128).max;
        if (uint256(marginState.stageDuration()) * marginState.stageSize() > 0) {
            DoubleEndedQueue.Uint256Deque storage queue = liquidityLockedQueue[id];
            uint256 lastStageTimestamp = lastStageTimestampStore[id];
            if (!queue.empty()) {
                uint256 currentStage = queue.front();
                (, releasedLiquidity) = currentStage.decode();
                if (
                    queue.length() > 1 && currentStage.isFree(marginState.stageLeavePart())
                        && block.timestamp >= lastStageTimestamp + marginState.stageDuration()
                ) {
                    uint256 nextStage = queue.at(1);
                    (, nextReleasedLiquidity) = nextStage.decode();
                }
            }
        }
    }

    /// @notice Handles the addition of liquidity to a pool.
    /// @dev Locks the liquidity according to the staging mechanism.
    /// @param id The ID of the pool.
    /// @param liquidityAdded The amount of liquidity to add.
    function _handleAddLiquidity(PoolId id, uint256 liquidityAdded) internal {
        uint256 stageSize = marginState.stageSize();
        if (uint256(marginState.stageDuration()) * stageSize == 0) {
            return; // No locking if stageDuration or stageSize is zero
        }
        uint256 lastStageTimestamp = lastStageTimestampStore[id];
        if (lastStageTimestamp == 0) {
            // Initialize lastStageTimestamp if it's not set
            lastStageTimestampStore[id] = block.timestamp;
        }
        DoubleEndedQueue.Uint256Deque storage queue = liquidityLockedQueue[id];
        uint128 lockAmount = Math.ceilDiv(liquidityAdded, stageSize).toUint128(); // Ensure at least 1 unit is locked per stage
        uint256 zeroStage = 0;
        if (queue.empty()) {
            for (uint32 i = 0; i < stageSize; i++) {
                queue.pushBack(zeroStage.add(lockAmount));
            }
        } else {
            uint256 queueSize = Math.min(queue.length(), stageSize);
            // If the queue is not empty, we need to update the existing stages
            // and add new stages if necessary
            for (uint256 i = 0; i < queueSize; i++) {
                uint256 stage = queue.at(i);
                queue.set(i, stage.add(lockAmount));
            }
            for (uint256 i = queueSize; i < stageSize; i++) {
                queue.pushBack(zeroStage.add(lockAmount));
            }
        }
    }

    /// @notice Handles the removal of liquidity from a pool.
    /// @dev Checks if the requested amount of liquidity is available for withdrawal and updates the liquidity queue.
    /// @param id The ID of the pool.
    /// @param liquidityRemoved The amount of liquidity to remove .
    function _handleRemoveLiquidity(PoolId id, uint256 liquidityRemoved) internal {
        if (uint256(marginState.stageDuration()) * marginState.stageSize() > 0) {
            (uint128 releasedLiquidity, uint128 nextReleasedLiquidity) = _getReleasedLiquidity(id);
            uint256 availableLiquidity = releasedLiquidity + nextReleasedLiquidity;
            if (availableLiquidity < liquidityRemoved) {
                LiquidityLocked.selector.revertWith();
            }
            DoubleEndedQueue.Uint256Deque storage queue = liquidityLockedQueue[id];
            if (!queue.empty()) {
                if (nextReleasedLiquidity > 0) {
                    // If next stage is free, we can release the next stage liquidity
                    uint256 currentStage = queue.popFront(); // Remove the current stage
                    uint256 nextStage = queue.front();
                    (, uint128 currentLiquidity) = currentStage.decode();
                    if (currentLiquidity > liquidityRemoved) {
                        nextStage = nextStage.add((currentLiquidity - liquidityRemoved).toUint128());
                    } else {
                        nextStage = nextStage.sub((liquidityRemoved - currentLiquidity).toUint128());
                    }
                    queue.set(0, nextStage);
                    // Update lastStageTimestamp to the next stage time
                    lastStageTimestampStore[id] = block.timestamp;
                } else {
                    // If next stage is not free, we just reduce the current stage liquidity
                    uint256 currentStage = queue.front();
                    uint256 afterStage;
                    if (queue.length() == 1) {
                        afterStage = currentStage.subTotal(liquidityRemoved.toUint128());
                    } else {
                        afterStage = currentStage.sub(liquidityRemoved.toUint128());
                    }
                    if (!currentStage.isFree(marginState.stageLeavePart()) || queue.length() == 1) {
                        // Update lastStageTimestamp
                        lastStageTimestampStore[id] = block.timestamp;
                    }
                    queue.set(0, afterStage);
                }
            }
        }
    }

    // ******************** OWNER CALL ********************
    /// @notice Sets the margin controller address.
    /// @dev Only the owner can call this function.
    /// @param controller The address of the new margin controller.
    function setMarginController(address controller) external onlyOwner {
        if (marginController == address(0)) {
            marginController = controller;
            emit MarginControllerUpdated(controller);
        }
    }

    /// @inheritdoc IMarginBase
    function setMarginState(MarginState newMarginState) external onlyOwner {
        marginState = newMarginState;
        emit MarginStateUpdated(newMarginState);
    }
}
