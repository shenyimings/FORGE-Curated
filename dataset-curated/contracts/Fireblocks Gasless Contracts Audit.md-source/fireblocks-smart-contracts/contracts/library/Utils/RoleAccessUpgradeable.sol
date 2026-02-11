// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2024 Fireblocks <support@fireblocks.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity 0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

import {LibErrors} from "../Errors/LibErrors.sol";

/**
 * @title Role Access Upgradeable
 * @author Fireblocks
 * @dev This abstract contract provides internal contract logic for managing access control roles.
 */
abstract contract RoleAccessUpgradeable is Initializable, AccessControlUpgradeable {
	/// Functions

	/**
	 * @notice This is an initializer function for the abstract contract.
	 * @dev Standard Initializable contract behavior.
	 *
	 * Calling Conditions:
	 *
	 * - Can only be invoked by functions with the {initializer} or {reinitializer} modifiers.
	 */
	function __RoleAccess_init() internal onlyInitializing {
		__AccessControl_init();
	}

	/**
	 * @notice This function revokes an Access Control role from an account
	 * @dev Calling Conditions:
	 *
	 * - Caller must be the role admin of the `role`.
	 * - Non-zero address `account`.
	 *
	 * This function emits a {RoleRevoked} event as part of {AccessControlUpgradeable._revokeRole}.
	 *
	 * @param role The role that will be revoked.
	 * @param account The address from which role is revoked
	 */
	function revokeRole(bytes32 role, address account) public virtual override {
		if (role == DEFAULT_ADMIN_ROLE && account == _msgSender()) {
			revert LibErrors.DefaultAdminError();
		}

		_authorizeRoleAccess();
		super.revokeRole(role, account); // In {AccessControlUpgradeable}
	}

	/**
	 * @notice  This function renounces an Access Control role from an account, except for the "DEFAULT_ADMIN_ROLE".
	 *
	 * @dev Only the account itself can renounce its own roles, and not any other account.
	 * Calling Conditions:
	 * - Cannot renounce DEFAULT_ADMIN_ROLE.
	 * - 'account' is the caller of the transaction.
	 */
	function renounceRole(bytes32 role, address account) public virtual override {
		if (role == DEFAULT_ADMIN_ROLE) {
			revert LibErrors.DefaultAdminError();
		}
		_authorizeRoleAccess();
		super.renounceRole(role, account); // In {AccessControlUpgradeable}
	}

	/**
	 * @notice This function grants an Access Control role to an account
	 * @dev Calling Conditions:
	 *
	 * - Caller must be the role admin of the `role`.
	 * - Non-zero address `account`.
	 *
	 * This function emits a {RoleGranted} event as part of {AccessControlUpgradeable._grantRole}.
	 *
	 * @param role The role that will be granted.
	 * @param account The address to which role is granted
	 */
	function grantRole(bytes32 role, address account) public virtual override {
		_authorizeRoleAccess();
		super.grantRole(role, account); // In {AccessControlUpgradeable}
	}

	/**
	 * @notice This function is designed to be overridden in inheriting contracts.
	 * @dev Override this function to implement RBAC control.
	 */
	function _authorizeRoleAccess() internal virtual;

	/* solhint-enable func-name-mixedcase */
	/**
	 * @dev This empty reserved space is put in place to allow future versions to add new
	 * variables without shifting down storage in the inheritance chain.
	 * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
	 */
	//slither-disable-next-line naming-convention
	uint256[50] private __gap;
}
