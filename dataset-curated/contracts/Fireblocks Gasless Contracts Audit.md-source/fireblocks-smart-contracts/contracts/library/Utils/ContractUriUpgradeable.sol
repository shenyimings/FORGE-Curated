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

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

/**
 * @title Contract Uri Upgradeable
 * @author Fireblocks
 * @dev This abstract contract provides internal contract logic for upgrading the contract URI.
 */
abstract contract ContractUriUpgradeable is Initializable, ContextUpgradeable {
	/// State

	/**
	 * @notice This field is a URI (Uniform Resource Identifier) that points to a JSON file with metadata about the contract.
	 * @dev This state variable is queried by the contractUri() function.
	 */
	string public contractUri;

	/// Events

	/**
	 * @notice This event is logged when the contract URI is updated.
	 *
	 * @param caller The (indexed) address of the entity that triggered the update.
	 * @param oldUri The URI previously associated with the contract.
	 * @param newUri The new URI associated with the contract.
	 */
	event ContractUriUpdated(address indexed caller, string oldUri, string newUri);

	// Functions

	/**
	 * @notice This is an initializer function for the abstract contract.
	 * @dev Standard Initializable contract behavior.
	 *
	 * Calling Conditions:
	 *
	 * - Can only be invoked by functions with the {initializer} or {reinitializer} modifiers.
	 */
	/* solhint-disable func-name-mixedcase */
	function __ContractUri_init(string memory _uri) internal onlyInitializing {
		_updateContractUri(_uri);
	}

	/**
	 * @notice This is a function used to update `contractUri` field.
	 * @dev This function emits a {ContractUriUpdated} event.
	 *
	 * @param _uri A URI link pointing to the current URI associated with the contract.
	 */
	function contractUriUpdate(string calldata _uri) external virtual {
		_authorizeContractUriUpdate();
		_updateContractUri(_uri);
	}

	/**
	 * @notice This is a function used to update `contractUri` field.
	 * @dev This function emits a {ContractUriUpdated} event.
	 *
	 * @param _uri A URI link pointing to the current URI associated with the contract.
	 */
	function _updateContractUri(string memory _uri) internal virtual {
		emit ContractUriUpdated(_msgSender(), contractUri, _uri);
		contractUri = _uri;
	}

	/**
	 * @notice This function is designed to be overridden in inheriting contracts.
	 * @dev Override this function to implement RBAC control.
	 */
	function _authorizeContractUriUpdate() internal virtual;

	/* solhint-enable func-name-mixedcase */
	/**
	 * @dev This empty reserved space is put in place to allow future versions to add new
	 * variables without shifting down storage in the inheritance chain.
	 * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
	 */
	//slither-disable-next-line naming-convention
	uint256[49] private __gap;
}
