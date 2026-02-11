// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

type Slot0 is bytes32;

using Slot0Library for Slot0 global;

/// @notice Library for getting and setting values in the Slot0 type
library Slot0Library {
    uint128 internal constant MASK_128_BITS = 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint32 internal constant MASK_32_BITS = 0xFFFFFFFF;
    uint24 internal constant MASK_24_BITS = 0xFFFFFF;

    uint8 internal constant LAST_UPDATED_OFFSET = 128;
    uint8 internal constant PROTOCOL_FEE_OFFSET = 160;
    uint8 internal constant LP_FEE_OFFSET = 184;
    uint8 internal constant MARGIN_FEE_OFFSET = 208;

    // #### GETTERS ####
    function totalSupply(Slot0 _packed) internal pure returns (uint128 _totalSupply) {
        assembly ("memory-safe") {
            _totalSupply := and(MASK_128_BITS, _packed)
        }
    }

    function lastUpdated(Slot0 _packed) internal pure returns (uint32 _timestampLast) {
        assembly ("memory-safe") {
            _timestampLast := and(MASK_32_BITS, shr(LAST_UPDATED_OFFSET, _packed))
        }
    }

    function protocolFee(Slot0 _packed) internal pure returns (uint24 _protocolFee) {
        assembly ("memory-safe") {
            _protocolFee := and(MASK_24_BITS, shr(PROTOCOL_FEE_OFFSET, _packed))
        }
    }

    function protocolFee(Slot0 _packed, uint24 defaultFee) internal pure returns (uint24 _protocolFee) {
        _protocolFee = protocolFee(_packed);
        _protocolFee = _protocolFee == 0 ? defaultFee : _protocolFee;
    }

    function lpFee(Slot0 _packed) internal pure returns (uint24 _lpFee) {
        assembly ("memory-safe") {
            _lpFee := and(MASK_24_BITS, shr(LP_FEE_OFFSET, _packed))
        }
    }

    function marginFee(Slot0 _packed) internal pure returns (uint24 _marginFee) {
        assembly ("memory-safe") {
            _marginFee := signextend(2, shr(MARGIN_FEE_OFFSET, _packed))
        }
    }

    // #### SETTERS ####
    function setTotalSupply(Slot0 _packed, uint128 _totalSupply) internal pure returns (Slot0 _result) {
        assembly ("memory-safe") {
            _result := or(and(not(MASK_128_BITS), _packed), and(MASK_128_BITS, _totalSupply))
        }
    }

    function setLastUpdated(Slot0 _packed, uint32 _lastUpdated) internal pure returns (Slot0 _result) {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(LAST_UPDATED_OFFSET, MASK_32_BITS)), _packed),
                    shl(LAST_UPDATED_OFFSET, and(MASK_32_BITS, _lastUpdated))
                )
        }
    }

    function setProtocolFee(Slot0 _packed, uint24 _protocolFee) internal pure returns (Slot0 _result) {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(PROTOCOL_FEE_OFFSET, MASK_24_BITS)), _packed),
                    shl(PROTOCOL_FEE_OFFSET, and(MASK_24_BITS, _protocolFee))
                )
        }
    }

    function setLpFee(Slot0 _packed, uint24 _lpFee) internal pure returns (Slot0 _result) {
        assembly ("memory-safe") {
            _result :=
                or(and(not(shl(LP_FEE_OFFSET, MASK_24_BITS)), _packed), shl(LP_FEE_OFFSET, and(MASK_24_BITS, _lpFee)))
        }
    }

    function setMarginFee(Slot0 _packed, uint24 _marginFee) internal pure returns (Slot0 _result) {
        assembly ("memory-safe") {
            _result :=
                or(
                    and(not(shl(MARGIN_FEE_OFFSET, MASK_24_BITS)), _packed),
                    shl(MARGIN_FEE_OFFSET, and(MASK_24_BITS, _marginFee))
                )
        }
    }
}
