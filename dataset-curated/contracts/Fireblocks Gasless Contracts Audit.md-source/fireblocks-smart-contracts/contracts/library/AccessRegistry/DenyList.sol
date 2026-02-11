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

import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import {AccessListUpgradeable} from "./AccessListUpgradeable.sol";

/**
 * @title Denylist
 * @author Fireblocks
 * @notice The Denylist Service establishes an on-chain Denylist for the Fireblocks ecosystem of smart contracts. It
 * maintains a registry of addresses barred to participate in the system by implementing {AccessListUpgradeable} and
 * {IAccessRegistry}. Thereby allowing other contracts in the system to check if an address is allowed to participate.
 *
 * @dev Denylist Service features.
 *
 * The Denylist Service contract Role Based Access Control employs the following roles:
 *
 * - UPGRADER_ROLE (via {AccessListUpgradeable})
 * - PAUSER_ROLE (via {AccessListUpgradeable})
 * - CONTRACT_ADMIN_ROLE (via {AccessListUpgradeable})
 * - ACCESS_LIST_ADMIN_ROLE (via {AccessListUpgradeable})
 */
contract DenyList is AccessListUpgradeable {
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

	/// Functions

	/**
	 * @notice This function acts as the constructor of the contract.
	 * @dev This function disables the initializers.
	 */
	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/**
	 * @notice This function configures the Deny List contract with the initial state and granting
	 * privileged roles.
	 *
	 * @dev This function uses the {AccessListUpgradeable.__AccessList_init} function to grant roles.
	 *
	 * Calling Conditions:
	 *
	 * - Can only be invoked once (controlled via the {initializer} modifier).
	 * - Non-zero address `defaultAdmin` (checked internally by {AccessListUpgradeable.__AccessList_init}).
	 * - Non-zero address `pauser` (checked internally by {AccessListUpgradeable.__AccessList_init}).
	 * - Non-zero address `upgrader`(checked internally by {AccessListUpgradeable.__AccessList_init}).
	 *
	 * @param defaultAdmin The account to be granted the "DEFAULT_ADMIN_ROLE".
	 * @param pauser The account to be granted the "PAUSER_ROLE".
	 * @param upgrader The account to be granted the "UPGRADER_ROLE".
	 */
	function initialize(address defaultAdmin, address pauser, address upgrader) external virtual initializer {
		__AccessList_init(defaultAdmin, pauser, upgrader);
	}

	/**
	 * @notice This function checks if an address is present in the Access list. By doing so, it confirms that whether
	 * the  address is denied to participate in the system.
	 * @dev This function returns `false` if the address is present in the Denylist, otherwise it returns `true`.
	 * The parameter `data` is ignored in this implementation of the interface as it serves as a placeholder for
	 * future implementations.
	 *
	 * @param account The address to be checked.
	 * @return `false` if the address is present in the Denylist, otherwise it returns `true`.
	 */
	function hasAccess(address account, address, bytes calldata) external view virtual override returns (bool) {
		return !_accessList.contains(account);
	}
}
