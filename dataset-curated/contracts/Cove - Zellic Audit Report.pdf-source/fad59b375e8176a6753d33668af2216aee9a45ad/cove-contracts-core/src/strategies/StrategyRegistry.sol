// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { WeightStrategy } from "src/strategies/WeightStrategy.sol";

/// @title StrategyRegistry
/// @notice A registry for weight strategies that allows checking if a strategy supports a specific bit flag.
/// @dev Inherits from AccessControlEnumerable for role-based access control.
/// Roles:
/// - DEFAULT_ADMIN_ROLE: The default role given to an address at creation. Can grant and revoke roles.
/// - WEIGHT_STRATEGY_ROLE: Role given to approved weight strategys.
contract StrategyRegistry is AccessControlEnumerable {
    /// @dev Role identifier for weight strategys
    bytes32 private constant _WEIGHT_STRATEGY_ROLE = keccak256("WEIGHT_STRATEGY_ROLE");

    /// @dev Error thrown when an unsupported strategy is used
    error StrategyNotSupported();

    /// @notice Constructs the StrategyRegistry contract
    /// @param admin The address that will be granted the DEFAULT_ADMIN_ROLE
    // slither-disable-next-line locked-ether
    constructor(address admin) payable {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Checks if a given weight strategy supports a specific bit flag
    /// @param bitFlag The bit flag to check support for
    /// @param weightStrategy The address of the weight strategy to check
    /// @return bool True if the strategy supports the bit flag, false otherwise
    function supportsBitFlag(uint256 bitFlag, address weightStrategy) external view returns (bool) {
        if (!hasRole(_WEIGHT_STRATEGY_ROLE, weightStrategy)) {
            revert StrategyNotSupported();
        }
        return WeightStrategy(weightStrategy).supportsBitFlag(bitFlag);
    }
}
