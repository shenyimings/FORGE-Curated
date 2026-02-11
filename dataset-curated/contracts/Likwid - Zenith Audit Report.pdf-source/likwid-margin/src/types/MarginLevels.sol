// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

type MarginLevels is bytes32;

using MarginLevelsLibrary for MarginLevels global;

/// @notice Library for getting and setting values in the MarginLevels type
library MarginLevelsLibrary {
    uint24 internal constant MASK_24_BITS = 0xFFFFFF;

    uint8 internal constant MIN_BORROW_LEVEL_OFFSET = 24;
    uint8 internal constant LIQUIDATE_LEVEL_OFFSET = 48;
    uint8 internal constant LIQUIDATION_RATIO_OFFSET = 72;
    uint8 internal constant CALLER_PROFIT_OFFSET = 96;
    uint8 internal constant PROTOCOL_PROFIT_OFFSET = 120;

    function isValidMarginLevels(MarginLevels _packed) internal pure returns (bool valid) {
        uint24 _liquidateLevel = liquidateLevel(_packed);
        uint24 one = 10 ** 6;
        valid = _liquidateLevel >= one && minMarginLevel(_packed) > _liquidateLevel
            && minBorrowLevel(_packed) > _liquidateLevel && liquidationRatio(_packed) <= one;
    }

    // #### GETTERS ####
    function minMarginLevel(MarginLevels _packed) internal pure returns (uint24 _minMarginLevel) {
        assembly ("memory-safe") {
            _minMarginLevel := and(MASK_24_BITS, _packed)
        }
    }

    function minBorrowLevel(MarginLevels _packed) internal pure returns (uint24 _minBorrowLevel) {
        assembly ("memory-safe") {
            _minBorrowLevel := and(MASK_24_BITS, shr(MIN_BORROW_LEVEL_OFFSET, _packed))
        }
    }

    function liquidateLevel(MarginLevels _packed) internal pure returns (uint24 _liquidateLevel) {
        assembly ("memory-safe") {
            _liquidateLevel := and(MASK_24_BITS, shr(LIQUIDATE_LEVEL_OFFSET, _packed))
        }
    }

    function liquidationRatio(MarginLevels _packed) internal pure returns (uint24 _liquidationRatio) {
        assembly ("memory-safe") {
            _liquidationRatio := and(MASK_24_BITS, shr(LIQUIDATION_RATIO_OFFSET, _packed))
        }
    }

    function callerProfit(MarginLevels _packed) internal pure returns (uint24 _callerProfit) {
        assembly ("memory-safe") {
            _callerProfit := and(MASK_24_BITS, shr(CALLER_PROFIT_OFFSET, _packed))
        }
    }

    function protocolProfit(MarginLevels _packed) internal pure returns (uint24 _protocolProfit) {
        assembly ("memory-safe") {
            _protocolProfit := and(MASK_24_BITS, shr(PROTOCOL_PROFIT_OFFSET, _packed))
        }
    }

    // #### SETTERS ####
    function setMinMarginLevel(MarginLevels _packed, uint24 _minMarginLevel)
        internal
        pure
        returns (MarginLevels _result)
    {
        assembly ("memory-safe") {
            _result := or(and(not(MASK_24_BITS), _packed), and(MASK_24_BITS, _minMarginLevel))
        }
    }

    function setMinBorrowLevel(MarginLevels _packed, uint24 _minBorrowLevel)
        internal
        pure
        returns (MarginLevels _result)
    {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(MIN_BORROW_LEVEL_OFFSET, MASK_24_BITS)), _packed),
                    shl(MIN_BORROW_LEVEL_OFFSET, and(MASK_24_BITS, _minBorrowLevel))
                )
        }
    }

    function setLiquidateLevel(MarginLevels _packed, uint24 _liquidateLevel)
        internal
        pure
        returns (MarginLevels _result)
    {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(LIQUIDATE_LEVEL_OFFSET, MASK_24_BITS)), _packed),
                    shl(LIQUIDATE_LEVEL_OFFSET, and(MASK_24_BITS, _liquidateLevel))
                )
        }
    }

    function setLiquidationRatio(MarginLevels _packed, uint24 _liquidationRatio)
        internal
        pure
        returns (MarginLevels _result)
    {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(LIQUIDATION_RATIO_OFFSET, MASK_24_BITS)), _packed),
                    shl(LIQUIDATION_RATIO_OFFSET, and(MASK_24_BITS, _liquidationRatio))
                )
        }
    }

    function setCallerProfit(MarginLevels _packed, uint24 _callerProfit) internal pure returns (MarginLevels _result) {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(CALLER_PROFIT_OFFSET, MASK_24_BITS)), _packed),
                    shl(CALLER_PROFIT_OFFSET, and(MASK_24_BITS, _callerProfit))
                )
        }
    }

    function setProtocolProfit(MarginLevels _packed, uint24 _protocolProfit)
        internal
        pure
        returns (MarginLevels _result)
    {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(PROTOCOL_PROFIT_OFFSET, MASK_24_BITS)), _packed),
                    shl(PROTOCOL_PROFIT_OFFSET, and(MASK_24_BITS, _protocolProfit))
                )
        }
    }
}
