// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

type MarginState is bytes32;

using MarginStateLibrary for MarginState global;

/// @notice Library for getting and setting values in the MarginState type
library MarginStateLibrary {
    uint24 internal constant MASK_24_BITS = 0xFFFFFF;

    uint8 internal constant USE_MIDDLE_LEVEL_OFFSET = 24;
    uint8 internal constant USE_HIGH_LEVEL_OFFSET = 48;
    uint8 internal constant M_LOW_OFFSET = 72;
    uint8 internal constant M_MIDDLE_OFFSET = 96;
    uint8 internal constant M_HIGH_OFFSET = 120;
    uint8 internal constant MAX_PRICE_MOVE_PER_SECOND_OFFSET = 144;
    uint8 internal constant STAGE_DURATION = 168;
    uint8 internal constant STAGE_SIZE = 192;
    uint8 internal constant STAGE_LEAVE_PART = 216;

    // #### GETTERS ####
    function rateBase(MarginState _packed) internal pure returns (uint24 _rateBase) {
        assembly ("memory-safe") {
            _rateBase := and(MASK_24_BITS, _packed)
        }
    }

    function useMiddleLevel(MarginState _packed) internal pure returns (uint24 _useMiddleLevel) {
        assembly ("memory-safe") {
            _useMiddleLevel := and(MASK_24_BITS, shr(USE_MIDDLE_LEVEL_OFFSET, _packed))
        }
    }

    function useHighLevel(MarginState _packed) internal pure returns (uint24 _useHighLevel) {
        assembly ("memory-safe") {
            _useHighLevel := and(MASK_24_BITS, shr(USE_HIGH_LEVEL_OFFSET, _packed))
        }
    }

    function mLow(MarginState _packed) internal pure returns (uint24 _mLow) {
        assembly ("memory-safe") {
            _mLow := and(MASK_24_BITS, shr(M_LOW_OFFSET, _packed))
        }
    }

    function mMiddle(MarginState _packed) internal pure returns (uint24 _mMiddle) {
        assembly ("memory-safe") {
            _mMiddle := and(MASK_24_BITS, shr(M_MIDDLE_OFFSET, _packed))
        }
    }

    function mHigh(MarginState _packed) internal pure returns (uint24 _mHigh) {
        assembly ("memory-safe") {
            _mHigh := and(MASK_24_BITS, shr(M_HIGH_OFFSET, _packed))
        }
    }

    function maxPriceMovePerSecond(MarginState _packed) internal pure returns (uint24 _maxPriceMovePerSecond) {
        assembly ("memory-safe") {
            _maxPriceMovePerSecond := and(MASK_24_BITS, shr(MAX_PRICE_MOVE_PER_SECOND_OFFSET, _packed))
        }
    }

    function stageDuration(MarginState _packed) internal pure returns (uint24 _stageDuration) {
        assembly ("memory-safe") {
            _stageDuration := and(MASK_24_BITS, shr(STAGE_DURATION, _packed))
        }
    }

    function stageSize(MarginState _packed) internal pure returns (uint24 _stageSize) {
        assembly ("memory-safe") {
            _stageSize := and(MASK_24_BITS, shr(STAGE_SIZE, _packed))
        }
    }

    function stageLeavePart(MarginState _packed) internal pure returns (uint24 _stageLeavePart) {
        assembly ("memory-safe") {
            _stageLeavePart := and(MASK_24_BITS, shr(STAGE_LEAVE_PART, _packed))
        }
    }

    // #### SETTERS ####
    function setRateBase(MarginState _packed, uint24 _rateBase) internal pure returns (MarginState _result) {
        assembly ("memory-safe") {
            _result := or(and(not(MASK_24_BITS), _packed), and(MASK_24_BITS, _rateBase))
        }
    }

    function setUseMiddleLevel(MarginState _packed, uint24 _useMiddleLevel)
        internal
        pure
        returns (MarginState _result)
    {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(USE_MIDDLE_LEVEL_OFFSET, MASK_24_BITS)), _packed),
                    shl(USE_MIDDLE_LEVEL_OFFSET, and(MASK_24_BITS, _useMiddleLevel))
                )
        }
    }

    function setUseHighLevel(MarginState _packed, uint24 _useHighLevel) internal pure returns (MarginState _result) {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(USE_HIGH_LEVEL_OFFSET, MASK_24_BITS)), _packed),
                    shl(USE_HIGH_LEVEL_OFFSET, and(MASK_24_BITS, _useHighLevel))
                )
        }
    }

    function setMLow(MarginState _packed, uint24 _mLow) internal pure returns (MarginState _result) {
        assembly ("memory-safe") {
            _result :=
                or(and(not(shl(M_LOW_OFFSET, MASK_24_BITS)), _packed), shl(M_LOW_OFFSET, and(MASK_24_BITS, _mLow)))
        }
    }

    function setMMiddle(MarginState _packed, uint24 _mMiddle) internal pure returns (MarginState _result) {
        assembly ("memory-safe") {
            _result :=
                or(and(not(shl(M_MIDDLE_OFFSET, MASK_24_BITS)), _packed), shl(M_MIDDLE_OFFSET, and(MASK_24_BITS, _mMiddle)))
        }
    }

    function setMHigh(MarginState _packed, uint24 _mHigh) internal pure returns (MarginState _result) {
        assembly ("memory-safe") {
            _result :=
                or(and(not(shl(M_HIGH_OFFSET, MASK_24_BITS)), _packed), shl(M_HIGH_OFFSET, and(MASK_24_BITS, _mHigh)))
        }
    }

    function setMaxPriceMovePerSecond(MarginState _packed, uint24 _maxPriceMovePerSecond)
        internal
        pure
        returns (MarginState _result)
    {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(MAX_PRICE_MOVE_PER_SECOND_OFFSET, MASK_24_BITS)), _packed),
                    shl(MAX_PRICE_MOVE_PER_SECOND_OFFSET, and(MASK_24_BITS, _maxPriceMovePerSecond))
                )
        }
    }

    function setStageDuration(MarginState _packed, uint24 _stageDuration) internal pure returns (MarginState _result) {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(STAGE_DURATION, MASK_24_BITS)), _packed),
                    shl(STAGE_DURATION, and(MASK_24_BITS, _stageDuration))
                )
        }
    }

    function setStageSize(MarginState _packed, uint24 _stageSize) internal pure returns (MarginState _result) {
        assembly ("memory-safe") {
            _result :=
                or(and(not(shl(STAGE_SIZE, MASK_24_BITS)), _packed), shl(STAGE_SIZE, and(MASK_24_BITS, _stageSize)))
        }
    }

    function setStageLeavePart(MarginState _packed, uint24 _stageLeavePart)
        internal
        pure
        returns (MarginState _result)
    {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(STAGE_SIZE, STAGE_LEAVE_PART)), _packed),
                    shl(STAGE_LEAVE_PART, and(MASK_24_BITS, _stageLeavePart))
                )
        }
    }
}
