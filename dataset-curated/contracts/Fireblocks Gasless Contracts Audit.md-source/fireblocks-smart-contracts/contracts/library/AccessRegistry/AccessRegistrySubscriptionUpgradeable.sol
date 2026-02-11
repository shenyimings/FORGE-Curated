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

import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC165Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {IAccessRegistry} from "./interface/IAccessRegistry.sol";
import {LibErrors} from "../Errors/LibErrors.sol";

/**
 * @title Access Registry Subscription Upgradeable
 * @author Fireblocks
 * @dev This abstract contract provides internal contract logic for subscribing to an Access Registry contract.
 */
abstract contract AccessRegistrySubscriptionUpgradeable is Initializable, ContextUpgradeable {
	/// State

	/**
	 * @notice This field is the address of the {AccessRegistry} contract.
	 */
	IAccessRegistry public accessRegistry;

	/// Events

	/**
	 * @notice This event is emitted when the {AccessRegistry} contract address is updated.
	 * @dev This event is emitted by the {_updateAccessRegistry} function.
	 *
	 * @param caller The address of the account that updated the {AccessRegistry} contract address.
	 * @param oldAccessRegistry The address of the old {AccessRegistry} contract.
	 * @param newAccessRegistry The address of the new {AccessRegistry} contract.
	 */
	event AccessRegistryUpdated(
		address indexed caller,
		address indexed oldAccessRegistry,
		address indexed newAccessRegistry
	);

	/// Functions

	/**
	 * @notice This is an initializer function for the abstract contract.
	 * @dev Standard Initializable contract behavior.
	 *
	 * Calling Conditions:
	 *
	 * - Can only be invoked by functions with the {initializer} or {reinitializer} modifiers.
	 * @param _accessRegistry The address of the contract that implements {IAccessRegistry}.
	 */
	function __AccessRegistrySubscription_init(address _accessRegistry) internal onlyInitializing {
		_accessRegistryUpdate(_accessRegistry);
	}

	/**
	 * @notice This is a function used to update `accessRegistry` field.
	 * @dev This function emits a {AccessRegistryUpdated} event as part of {_accessRegistryUpdate}
	 * when the access registry address is successfully updated.
	 *
	 * @param _accessRegistry The address of the contract that implements {IAccessRegistry}.
	 */
	function accessRegistryUpdate(address _accessRegistry) external virtual {
		_authorizeAccessRegistryUpdate();
		_accessRegistryUpdate(_accessRegistry);
	}

	/**
	 * @notice This function updates the address of the implementation of {IAccessRegistry} contract by updating the
	 * `accessRegistry` field.
	 *
	 * @dev Calling Conditions:
	 *
	 * - `_accessRegistry` must implement IAccessRegistry interface.
	 *
	 * @param _accessRegistry The address of the contract that implements {IAccessRegistry}.
	 */
	function _accessRegistryUpdate(address _accessRegistry) internal virtual {
		if (
			_accessRegistry != address(0) &&
			(!IERC165Upgradeable(_accessRegistry).supportsInterface(type(IAccessRegistry).interfaceId))
		) {
			revert LibErrors.InvalidImplementation();
		}

		emit AccessRegistryUpdated(_msgSender(), address(accessRegistry), _accessRegistry);
		accessRegistry = IAccessRegistry(_accessRegistry);
	}

	/**
	 * @notice This function is designed to be overridden in inheriting contracts.
	 * @dev Override this function to implement RBAC control.
	 */
	function _authorizeAccessRegistryUpdate() internal virtual;

	/* solhint-enable func-name-mixedcase */
	/**
	 * @dev This empty reserved space is put in place to allow future versions to add new
	 * variables without shifting down storage in the inheritance chain.
	 * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
	 */
	//slither-disable-next-line naming-convention
	uint256[49] private __gap;
}
