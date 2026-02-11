// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

/**
 * @notice This library defines immutable constants used throughout the system
 * @dev These constants must never be changed once deployed. Only new constants can be added.
 * Modifying existing constants would break compatibility and potentially cause
 * security vulnerabilities in dependent contracts.
 *
 * @custom:security-note Changing any existing constant values is strictly prohibited.
 * New constants may be added but existing ones are immutable.
 */
library BridgeTypes {
    uint16 constant LAYER_ZERO = 1;
    uint16 constant LINEA = 2;
}
