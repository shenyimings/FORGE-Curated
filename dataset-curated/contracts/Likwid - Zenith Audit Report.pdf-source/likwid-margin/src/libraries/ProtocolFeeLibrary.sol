// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FeeTypes} from "../types/FeeTypes.sol";
import {Math} from "./Math.sol";
import {CustomRevert} from "./CustomRevert.sol";

/// @notice A library for handling protocol fees represented as a packed uint24 value.
library ProtocolFeeLibrary {
    using CustomRevert for bytes4;

    error InvalidProtocolFee(uint8 fee);

    // Each fee is a uint8, representing a percentage of the total fee, scaled by FEE_DENOMINATOR.
    // For example, a value of 100 means 100/200 = 50% protocol fee.
    // The maximum value of 200 represents a 100% protocol fee.
    uint8 internal constant MAX_PROTOCOL_FEE = 200;
    uint256 internal constant FEE_DENOMINATOR = 200;

    uint24 internal constant SWAP_FEE_THRESHOLD = 201;
    uint24 internal constant MARGIN_FEE_THRESHOLD = 201 << 8;
    uint24 internal constant INTEREST_FEE_THRESHOLD = 201 << 16;

    function getProtocolSwapFee(uint24 self) internal pure returns (uint8) {
        return uint8(self & 0xff);
    }

    function getProtocolMarginFee(uint24 self) internal pure returns (uint8) {
        return uint8(self >> 8);
    }

    function getProtocolInterestFee(uint24 self) internal pure returns (uint8) {
        return uint8(self >> 16);
    }

    function isValidProtocolFee(uint24 self) internal pure returns (bool valid) {
        // Equivalent to: getProtocolSwapFee(self) <= MAX_PROTOCOL_FEE && getProtocolMarginFee(self) <= MAX_PROTOCOL_FEE && getProtocolInterestFee(self) <= MAX_PROTOCOL_FEE
        assembly ("memory-safe") {
            let isProtocolSwapFeeOk := lt(and(self, 0xff), SWAP_FEE_THRESHOLD)
            let isProtocolMarginFeeOk := lt(and(self, 0xff00), MARGIN_FEE_THRESHOLD)
            let isProtocolInterestFeeOk := lt(and(self, 0xff0000), INTEREST_FEE_THRESHOLD)
            valid := and(and(isProtocolSwapFeeOk, isProtocolMarginFeeOk), isProtocolInterestFeeOk)
        }
    }

    function getProtocolFee(uint24 self, FeeTypes feeType) internal pure returns (uint8) {
        if (feeType == FeeTypes.SWAP) {
            return getProtocolSwapFee(self);
        } else if (feeType == FeeTypes.MARGIN) {
            return getProtocolMarginFee(self);
        } else if (feeType == FeeTypes.INTERESTS) {
            return getProtocolInterestFee(self);
        }
        return 0; // Default case, should not happen
    }

    function setProtocolFee(uint24 self, FeeTypes feeType, uint8 newFee) internal pure returns (uint24) {
        if (newFee > MAX_PROTOCOL_FEE) {
            InvalidProtocolFee.selector.revertWith(newFee);
        }
        if (feeType == FeeTypes.SWAP) {
            return (self & 0xffff00) | newFee; // Set swap fee
        } else if (feeType == FeeTypes.MARGIN) {
            return (self & 0xff00ff) | (uint24(newFee) << 8); // Set margin fee
        } else if (feeType == FeeTypes.INTERESTS) {
            return (self & 0x00ffff) | (uint24(newFee) << 16); // Set interest fee
        }
        return self; // Default case, should not happen
    }

    function splitFee(uint24 self, FeeTypes feeType, uint256 feeAmount)
        internal
        pure
        returns (uint256 protocolFee, uint256 remainingFee)
    {
        uint8 protocolFeePercent = getProtocolFee(self, feeType);
        if (protocolFeePercent == 0) {
            return (0, feeAmount);
        }
        protocolFee = Math.mulDiv(feeAmount, protocolFeePercent, FEE_DENOMINATOR);
        remainingFee = feeAmount - protocolFee;
    }
}
