// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolId} from "../types/PoolId.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IMarginBase} from "../interfaces/IMarginBase.sol";
import {Slot0, Slot0Library} from "../types/Slot0.sol";
import {Reserves, ReservesLibrary, toReserves} from "../types/Reserves.sol";
import {PoolState} from "../types/PoolState.sol";
import {PairPosition} from "./PairPosition.sol";
import {LendPosition} from "./LendPosition.sol";
import {TimeLibrary} from "./TimeLibrary.sol";
import {PositionLibrary} from "./PositionLibrary.sol";
import {InterestMath} from "./InterestMath.sol";
import {PriceMath} from "./PriceMath.sol";
import {SafeCast} from "./SafeCast.sol";

/// @title A helper library to provide state getters for a Likwid pool
/// @notice This library provides functions to read the state of a Likwid pool from storage.
library StateLibrary {
    using SafeCast for *;
    using Slot0Library for Slot0;
    using ReservesLibrary for Reserves;
    using PositionLibrary for address;
    using TimeLibrary for uint32;

    /// @notice The storage slot of the `lastStageTimestampStore` mapping in the MarginBase contract.
    /// @dev This is an assumption. If the storage layout of MarginBase changes, this value needs to be updated.
    bytes32 public constant LAST_STAGE_TIMESTAMP_STORE_SLOT = bytes32(uint256(3));
    /// @notice The storage slot of the `liquidityLockedQueue` mapping in the MarginBase contract.
    /// @dev This is an assumption. If the storage layout of MarginBase changes, this value needs to be updated.
    bytes32 public constant LIQUIDITY_LOCKED_QUEUE_SLOT = bytes32(uint256(4));

    /// @notice The storage slot of the `_pools` mapping in the LikwidVault contract.
    bytes32 public constant POOLS_SLOT = bytes32(uint256(10));

    // Offsets for fields within the Pool.State struct
    uint256 internal constant BORROW_0_CUMULATIVE_LAST_OFFSET = 1;
    uint256 internal constant BORROW_1_CUMULATIVE_LAST_OFFSET = 2;
    uint256 internal constant DEPOSIT_0_CUMULATIVE_LAST_OFFSET = 3;
    uint256 internal constant DEPOSIT_1_CUMULATIVE_LAST_OFFSET = 4;
    uint256 internal constant REAL_RESERVES_OFFSET = 5;
    uint256 internal constant MIRROR_RESERVES_OFFSET = 6;
    uint256 internal constant PAIR_RESERVES_OFFSET = 7;
    uint256 internal constant TRUNCATED_RESERVES_OFFSET = 8;
    uint256 internal constant LEND_RESERVES_OFFSET = 9;
    uint256 internal constant INTEREST_RESERVES_OFFSET = 10;
    uint256 internal constant POSITIONS_OFFSET = 11;
    uint256 internal constant LEND_POSITIONS_OFFSET = 12;

    /**
     * @notice Get the unpacked Slot0 of the pool.
     * @dev Corresponds to pools[poolId].slot0
     * @param vault The vault contract.
     * @param poolId The ID of the pool.
     * @return totalSupply The total supply of liquidity tokens.
     * @return lastUpdated The timestamp of the last update.
     * @return protocolFee The protocol fee of the pool.
     * @return lpFee The swap fee of the pool.
     * @return marginFee The margin fee of the pool.
     */
    function getSlot0(IVault vault, PoolId poolId)
        internal
        view
        returns (uint128 totalSupply, uint32 lastUpdated, uint24 protocolFee, uint24 lpFee, uint24 marginFee)
    {
        bytes32 stateSlot = _getPoolStateSlot(poolId);
        Slot0 slot0 = Slot0.wrap(vault.extsload(stateSlot));
        totalSupply = slot0.totalSupply();
        lastUpdated = slot0.lastUpdated();
        protocolFee = slot0.protocolFee();
        lpFee = slot0.lpFee();
        marginFee = slot0.marginFee();
    }

    /**
     * @notice Retrieves the cumulative borrow and deposit rates of a pool.
     * @param vault The vault contract.
     * @param poolId The ID of the pool.
     * @return borrow0CumulativeLast The cumulative borrow rate for currency 0.
     * @return borrow1CumulativeLast The cumulative borrow rate for currency 1.
     * @return deposit0CumulativeLast The cumulative deposit rate for currency 0.
     * @return deposit1CumulativeLast The cumulative deposit rate for currency 1.
     */
    function getBorrowDepositCumulative(IVault vault, PoolId poolId)
        internal
        view
        returns (
            uint256 borrow0CumulativeLast,
            uint256 borrow1CumulativeLast,
            uint256 deposit0CumulativeLast,
            uint256 deposit1CumulativeLast
        )
    {
        bytes32 stateSlot = _getPoolStateSlot(poolId);
        bytes32 startSlot = bytes32(uint256(stateSlot) + BORROW_0_CUMULATIVE_LAST_OFFSET);

        bytes32[] memory data = vault.extsload(startSlot, 4);
        assembly ("memory-safe") {
            borrow0CumulativeLast := mload(add(data, 0x20))
            borrow1CumulativeLast := mload(add(data, 0x40))
            deposit0CumulativeLast := mload(add(data, 0x60))
            deposit1CumulativeLast := mload(add(data, 0x80))
        }
    }

    /**
     * @notice Retrieves the pair reserves of a pool.
     * @param vault The vault contract.
     * @param poolId The ID of the pool.
     * @return The packed pair reserves of the pool.
     */
    function getPairReserves(IVault vault, PoolId poolId) internal view returns (Reserves) {
        bytes32 slot = bytes32(uint256(_getPoolStateSlot(poolId)) + PAIR_RESERVES_OFFSET);
        return Reserves.wrap(uint256(vault.extsload(slot)));
    }

    /**
     * @notice Retrieves the real reserves of a pool.
     * @param vault The vault contract.
     * @param poolId The ID of the pool.
     * @return The packed real reserves of the pool.
     */
    function getRealReserves(IVault vault, PoolId poolId) internal view returns (Reserves) {
        bytes32 slot = bytes32(uint256(_getPoolStateSlot(poolId)) + REAL_RESERVES_OFFSET);
        return Reserves.wrap(uint256(vault.extsload(slot)));
    }

    /**
     * @notice Retrieves the mirror reserves of a pool.
     * @param vault The vault contract.
     * @param poolId The ID of the pool.
     * @return The packed mirror reserves of the pool.
     */
    function getMirrorReserves(IVault vault, PoolId poolId) internal view returns (Reserves) {
        bytes32 slot = bytes32(uint256(_getPoolStateSlot(poolId)) + MIRROR_RESERVES_OFFSET);
        return Reserves.wrap(uint256(vault.extsload(slot)));
    }

    /**
     * @notice Retrieves the truncated reserves of a pool.
     * @param vault The vault contract.
     * @param poolId The ID of the pool.
     * @return The packed truncated reserves of the pool.
     */
    function getTruncatedReserves(IVault vault, PoolId poolId) internal view returns (Reserves) {
        bytes32 slot = bytes32(uint256(_getPoolStateSlot(poolId)) + TRUNCATED_RESERVES_OFFSET);
        return Reserves.wrap(uint256(vault.extsload(slot)));
    }

    /**
     * @notice Retrieves the lending reserves of a pool.
     * @param vault The vault contract.
     * @param poolId The ID of the pool.
     * @return The packed lending reserves of the pool.
     */
    function getLendReserves(IVault vault, PoolId poolId) internal view returns (Reserves) {
        bytes32 slot = bytes32(uint256(_getPoolStateSlot(poolId)) + LEND_RESERVES_OFFSET);
        return Reserves.wrap(uint256(vault.extsload(slot)));
    }

    /**
     * @notice Retrieves the interest reserves of a pool.
     * @param vault The vault contract.
     * @param poolId The ID of the pool.
     * @return The packed interest reserves of the pool.
     */
    function getInterestReserves(IVault vault, PoolId poolId) internal view returns (Reserves) {
        bytes32 slot = bytes32(uint256(_getPoolStateSlot(poolId)) + INTEREST_RESERVES_OFFSET);
        return Reserves.wrap(uint256(vault.extsload(slot)));
    }

    function getLastStageTimestamp(IVault vault, PoolId poolId) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), LAST_STAGE_TIMESTAMP_STORE_SLOT));
        return uint256(vault.extsload(slot));
    }

    function getPairPositionState(IVault vault, PoolId poolId, address owner, bytes32 salt)
        internal
        view
        returns (PairPosition.State memory _position)
    {
        bytes32 positionKey = owner.calculatePositionKey(salt);

        bytes32 poolStateSlot = _getPoolStateSlot(poolId);
        bytes32 positionsMappingSlot = bytes32(uint256(poolStateSlot) + POSITIONS_OFFSET);
        bytes32 positionSlot = keccak256(abi.encodePacked(positionKey, positionsMappingSlot));

        bytes32[] memory data = vault.extsload(positionSlot, 2);
        _position.liquidity = uint128(uint256(data[0]));
        _position.totalInvestment = uint256(data[1]);
    }

    function getLendPositionState(IVault vault, PoolId poolId, address owner, bool lendForOne, bytes32 salt)
        internal
        view
        returns (LendPosition.State memory _position)
    {
        bytes32 positionKey = owner.calculatePositionKey(lendForOne, salt);

        bytes32 poolStateSlot = _getPoolStateSlot(poolId);
        bytes32 positionsMappingSlot = bytes32(uint256(poolStateSlot) + LEND_POSITIONS_OFFSET);
        bytes32 positionSlot = keccak256(abi.encodePacked(positionKey, positionsMappingSlot));

        bytes32[] memory data = vault.extsload(positionSlot, 2);
        uint256 slot0 = uint256(data[0]);
        _position.lendAmount = uint128(slot0);
        _position.depositCumulativeLast = uint256(data[1]);
    }

    function getRawStageLiquidities(IVault vault, PoolId poolId) internal view returns (uint256[] memory liquidities) {
        bytes32 dequeSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), LIQUIDITY_LOCKED_QUEUE_SLOT));
        bytes32 dequeValue = vault.extsload(dequeSlot);

        uint128 front;
        uint128 back;
        assembly ("memory-safe") {
            front := and(dequeValue, 0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff)
            back := shr(128, dequeValue)
        }

        uint256 len = back - front;
        liquidities = new uint256[](len);
        bytes32 valuesSlot = bytes32(uint256(dequeSlot) + 1);

        for (uint256 i = 0; i < len; i++) {
            uint256 valueIndex = front + i;
            bytes32 valueSlot = keccak256(abi.encodePacked(valueIndex, valuesSlot));
            liquidities[i] = uint256(vault.extsload(valueSlot));
        }
    }

    /**
     * @notice Calculates the storage slot for a specific pool's state.
     * @param poolId The ID of the pool.
     * @return The storage slot of the Pool.State struct.
     */
    function _getPoolStateSlot(PoolId poolId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT));
    }

    function getCurrentState(IVault vault, PoolId poolId) internal view returns (PoolState memory state) {
        bytes32 poolStateSlot = _getPoolStateSlot(poolId);

        // 1. Get slot0
        (state.totalSupply, state.lastUpdated, state.protocolFee, state.lpFee, state.marginFee) =
            getSlot0(vault, poolId);

        // 2. Get all other data in one call
        bytes32 startSlot = bytes32(uint256(poolStateSlot) + 1); // BORROW_0_CUMULATIVE_LAST_OFFSET
        bytes32[] memory data = vault.extsload(startSlot, 10); // read 10 slots

        uint256 borrow0CumulativeBefore = uint256(data[0]);
        uint256 borrow1CumulativeBefore = uint256(data[1]);
        uint256 deposit0CumulativeBefore = uint256(data[2]);
        uint256 deposit1CumulativeBefore = uint256(data[3]);
        state.realReserves = Reserves.wrap(uint256(data[4]));
        state.mirrorReserves = Reserves.wrap(uint256(data[5]));
        state.pairReserves = Reserves.wrap(uint256(data[6]));
        Reserves _truncatedReserves = Reserves.wrap(uint256(data[7]));
        state.lendReserves = Reserves.wrap(uint256(data[8]));
        state.interestReserves = Reserves.wrap(uint256(data[9]));

        // 3. Get marginState
        state.marginState = IMarginBase(address(vault)).marginState();

        // 4. Get timeElapsed
        uint256 timeElapsed = state.lastUpdated.getTimeElapsed();

        (uint256 mirrorReserve0, uint256 mirrorReserve1) = state.mirrorReserves.reserves();
        (uint256 pairReserve0, uint256 pairReserve1) = state.pairReserves.reserves();
        (uint256 lendReserve0, uint256 lendReserve1) = state.lendReserves.reserves();
        (uint256 interestReserve0, uint256 interestReserve1) = state.interestReserves.reserves();

        (uint256 borrow0CumulativeLast, uint256 borrow1CumulativeLast) = InterestMath.getBorrowRateCumulativeLast(
            timeElapsed,
            borrow0CumulativeBefore,
            borrow1CumulativeBefore,
            state.marginState,
            state.realReserves,
            state.mirrorReserves
        );

        InterestMath.InterestUpdateParams memory params0 = InterestMath.InterestUpdateParams({
            mirrorReserve: mirrorReserve0,
            borrowCumulativeLast: borrow0CumulativeLast,
            borrowCumulativeBefore: borrow0CumulativeBefore,
            interestReserve: interestReserve0,
            pairReserve: pairReserve0,
            lendReserve: lendReserve0,
            depositCumulativeLast: deposit0CumulativeBefore,
            protocolFee: state.protocolFee
        });

        InterestMath.InterestUpdateResult memory result0 = InterestMath.updateInterestForOne(params0);
        if (result0.changed) {
            mirrorReserve0 = result0.newMirrorReserve;
            pairReserve0 = result0.newPairReserve;
            lendReserve0 = result0.newLendReserve;
            interestReserve0 = result0.newInterestReserve;
        }
        state.deposit0CumulativeLast = result0.newDepositCumulativeLast;
        state.borrow0CumulativeLast = borrow0CumulativeLast;

        InterestMath.InterestUpdateParams memory params1 = InterestMath.InterestUpdateParams({
            mirrorReserve: mirrorReserve1,
            borrowCumulativeLast: borrow1CumulativeLast,
            borrowCumulativeBefore: borrow1CumulativeBefore,
            interestReserve: interestReserve1,
            pairReserve: pairReserve1,
            lendReserve: lendReserve1,
            depositCumulativeLast: deposit1CumulativeBefore,
            protocolFee: state.protocolFee
        });

        InterestMath.InterestUpdateResult memory result1 = InterestMath.updateInterestForOne(params1);
        if (result1.changed) {
            mirrorReserve1 = result1.newMirrorReserve;
            pairReserve1 = result1.newPairReserve;
            lendReserve1 = result1.newLendReserve;
            interestReserve1 = result1.newInterestReserve;
        }
        state.borrow1CumulativeLast = borrow1CumulativeLast;
        state.deposit1CumulativeLast = result1.newDepositCumulativeLast;

        if (result0.changed || result1.changed) {
            state.mirrorReserves = toReserves(mirrorReserve0.toUint128(), mirrorReserve1.toUint128());
            state.pairReserves = toReserves(pairReserve0.toUint128(), pairReserve1.toUint128());
            state.lendReserves = toReserves(lendReserve0.toUint128(), lendReserve1.toUint128());
            state.truncatedReserves = PriceMath.transferReserves(
                _truncatedReserves, state.pairReserves, timeElapsed, state.marginState.maxPriceMovePerSecond()
            );
        } else {
            state.truncatedReserves = state.pairReserves;
        }

        state.interestReserves = toReserves(interestReserve0.toUint128(), interestReserve1.toUint128());
    }
}
