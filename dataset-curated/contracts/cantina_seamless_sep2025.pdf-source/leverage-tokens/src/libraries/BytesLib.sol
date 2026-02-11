// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

/// @notice Library exposing bytes manipulation.
/// @dev This library was copied from Morpho https://github.com/morpho-org/bundler3/blob/4887f33299ba6e60b54a51237b16e7392dceeb97/src/libraries/BytesLib.sol
/// @custom:contact security@seamlessprotocol.com
library BytesLib {
    /// @notice Thrown when the offset is out of bounds
    error InvalidOffset(uint256 offset);

    /// @notice Reads 32 bytes at offset `offset` of memory bytes `data`.
    function get(bytes memory data, uint256 offset) internal pure returns (uint256 currentValue) {
        if (offset > data.length - 32) {
            revert InvalidOffset(offset);
        }
        assembly ("memory-safe") {
            currentValue := mload(add(32, add(data, offset)))
        }
    }

    /// @notice Writes `value` at offset `offset` of memory bytes `data`.
    function set(bytes memory data, uint256 offset, uint256 value) internal pure {
        if (offset > data.length - 32) {
            revert InvalidOffset(offset);
        }
        assembly ("memory-safe") {
            mstore(add(32, add(data, offset)), value)
        }
    }
}
