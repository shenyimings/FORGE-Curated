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

import {ERC2771ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {LibErrors} from "../Errors/LibErrors.sol";

/**
 * @title ERC2771 Context Initializable Upgradeable
 * @author Fireblocks
 * @notice This contract provides a context for ERC2771 meta-transactions.
 * @dev This abstract contract provides internal contract logic for ERC2771 context. This implementation brings the
 * {ERC2771ContextUpgradeable} contract from OpenZeppelin closer to the initializable pattern.
 */
abstract contract ERC2771ContextInitializableUpgradeable is ERC2771ContextUpgradeable {
	/// State

	/**
	 * @notice This field stores the address of the trusted forwarder.
	 * @dev This state variable is queried by the {isTrustedForwarder} to get informed if the forwarder is the trusted
	 * forwarder.
	 */
	address internal trustedForwarder_;

	/// Events

	/**
	 * @notice This event is emitted when the trusted forwarder is set.
	 * @dev This event is emitted by the {_updateTrustedForwarder} function.
	 *
	 * @param caller The (indexed) address of the account that updated the trusted forwarder.
	 * @param oldTrustedForwarder The (indexed) address of the old trusted forwarder.
	 * @param newTrustedForwarder The (indexed) address of the new trusted forwarder.
	 */
	event TrustedForwarderUpdated(
		address indexed caller,
		address indexed oldTrustedForwarder,
		address indexed newTrustedForwarder
	);

	/// Functions

	/**
	 * @notice This function acts as the constructor of the contract. The constructor of the parent class
	 * {ERC2771ContextInitializableUpgradeable} is initialized with the zero address. This is done because the trusted
	 * forwarder will be set during the contract's initialization through the
	 * {__ERC2771ContextInitializableUpgradeable_init} function.
	 */
	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() ERC2771ContextUpgradeable(address(0)) {}

	/**
	 * @notice This is an initializer function that initializes the state of this contract.
	 * @dev Standard Initializable contract behavior.
	 *
	 * Calling Conditions:
	 *
	 * - Can only be invoked by functions with the {initializer} or {reinitializer} modifiers.
	 *
	 * @param trustedForwarder The address of the trusted forwarder.
	 */
	/* solhint-disable func-name-mixedcase */
	function __ERC2771ContextInitializableUpgradeable_init(address trustedForwarder) internal virtual onlyInitializing {
		_updateTrustedForwarder(trustedForwarder);
	}

	/**
	 * @notice This function is used to update the trusted forwarder.
	 * @dev This function emits a {TrustedForwarderUpdated} event as part of {_updateTrustedForwarder} when the trusted
	 * forwarder is successfully updated.
	 *
	 * Calling Conditions:
	 *
	 * - The caller must be authorized to update the trusted forwarder.
	 *
	 * @param trustedForwarder The address of the new trusted forwarder.
	 */
	function updateTrustedForwarder(address trustedForwarder) external virtual {
		_authorizeTrustedForwarderUpdate();
		_updateTrustedForwarder(trustedForwarder);
	}

	/**
	 * @notice This function is used to get the trusted forwarder.
	 * @dev This function returns the address of the trusted forwarder.
	 * @return The address of the trusted forwarder.
	 */
	function getTrustedForwarder() external view virtual returns (address) {
		return trustedForwarder_;
	}

	/**
	 * @notice This function is used to check if the forwarder is the trusted forwarder.
	 * @dev This function is an override of the {isTrustedForwarder} function from the {ERC2771ContextUpgradeable}
	 * contract. It evaluates the forwarder address against the state variable `trustedForwarder_` and returns `true`
	 * if the forwarder address is the trusted forwarder.
	 *
	 * @param forwarder The address of the forwarder.
	 * @return Returns `true` if the forwarder is the trusted forwarder.
	 */
	function isTrustedForwarder(address forwarder) public view virtual override returns (bool) {
		return forwarder == trustedForwarder_;
	}

	/**
	 * @notice This function is used to update the trusted forwarder.
	 * @dev This function emits a {TrustedForwarderUpdated} event when the trusted forwarder is successfully updated.
	 * Note that, it is possible to set the trusted forwarder to the zero address in case user does not want to use
	 * the gasless feature.
	 *
	 * @param trustedForwarder The address of the new trusted forwarder.
	 */
	function _updateTrustedForwarder(address trustedForwarder) internal virtual {
		emit TrustedForwarderUpdated(_msgSender(), trustedForwarder_, trustedForwarder);
		trustedForwarder_ = trustedForwarder;
	}

	/**
	 * @notice This function is used to authorize the update of the trusted forwarder. This function is meant to be
	 * overridden in derived contracts.
	 * @dev This function is called by the {updateTrustedForwarder} function to check if the caller is authorized to
	 * update the trusted forwarder. Override this function to implement RBAC control.
	 */
	function _authorizeTrustedForwarderUpdate() internal virtual;

	/* solhint-enable func-name-mixedcase */
	/**
	 * @dev This empty reserved space is put in place to allow future versions to add new
	 * variables without shifting down storage in the inheritance chain.
	 * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
	 */
	//slither-disable-next-line naming-convention
	uint256[49] private __gap;
}
