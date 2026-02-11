// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ILender } from "../../../interfaces/ILender.sol";

/// @title AgentConfiguration library
/// @author kexley
/// @notice Implements the bitmap logic to handle the agent configuration
library AgentConfiguration {
    /// @dev Invalid reserve index
    error InvalidReserveIndex();

    /// @notice Sets if the user is borrowing the reserve identified by reserveIndex
    /// @param self The configuration object
    /// @param reserveIndex The index of the reserve in the bitmap
    /// @param borrowing True if the user is borrowing the reserve, false otherwise
    function setBorrowing(ILender.AgentConfigurationMap storage self, uint256 reserveIndex, bool borrowing) internal {
        unchecked {
            if (reserveIndex >= 256) revert InvalidReserveIndex();
            uint256 bit = 1 << (reserveIndex << 1);
            if (borrowing) {
                self.data |= bit;
            } else {
                self.data &= ~bit;
            }
        }
    }

    /// @notice Validate a user has been using the reserve for borrowing
    /// @param self The configuration object
    /// @param reserveIndex The index of the reserve in the bitmap
    /// @return True if the user has been using a reserve for borrowing, false otherwise
    function isBorrowing(ILender.AgentConfigurationMap memory self, uint256 reserveIndex)
        internal
        pure
        returns (bool)
    {
        unchecked {
            if (reserveIndex >= 256) revert InvalidReserveIndex();
            return (self.data >> (reserveIndex << 1)) & 1 != 0;
        }
    }
}
