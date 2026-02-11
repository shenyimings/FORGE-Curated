// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { WhitelabeledUnitUpgradeable, IERC20 } from "./unit/whitelabeled/WhitelabeledUnitUpgradeable.sol";

/**
 * @title GenericUSD
 * @notice A fully collateralized, omnichain stablecoin implementation
 * @dev GenericUSD (GUSD) is the primary stablecoin token in the Generic Protocol ecosystem.
 * It serves as a whitelabeled unit token that wraps underlying value units, enabling
 * seamless integration with the protocol's ERC-4626 vault infrastructure.
 *
 * This contract inherits wrapping/unwrapping functionality from WhitelabeledUnitUpgradeable
 * and maintains 1:1 parity with the underlying unit token through the wrap/unwrap mechanism.
 */
contract GenericUSD is WhitelabeledUnitUpgradeable {
    /**
     * @notice Initializes the GenericUSD contract with the specified underlying unit token
     * @param genericUnit The address of the underlying Generic unit token to wrap
     */
    function initialize(IERC20 genericUnit) external initializer {
        __WhitelabeledUnit_init("Generic USD", "GUSD", genericUnit);
    }
}
