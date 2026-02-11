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

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC2771ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {AccessListUpgradeable} from "../../library/AccessRegistry/AccessListUpgradeable.sol";
import {ERC2771ContextInitializableUpgradeable} from "../../library/MetaTx/ERC2771ContextInitializableUpgradeable.sol";
import {LibErrors} from "../../library/Errors/LibErrors.sol";

/**
 * @title AccessList Upgradeable Gasless
 * @author Fireblocks
 * @notice The AccessList Upgradeable establishes an on-chain AccessList for the Fireblocks ecosystem of smart contracts.
 * It maintains a registry of addresses allowed to participate in the system. It is also capable of verifying more
 * complex conditions using the data provided from the function call.
 *
 * The contract also supports ERC2771 meta-transactions, implemented through a custom version of the OpenZeppelin
 * {ERC2771ContextUpgradeable} contract, named {ERC2771ContextInitializableUpgradeable}. This customized implementation
 * enables the trusted forwarder address to be set during the contract's initialization, ensuring stricter adherence to
 * the initializable pattern.
 *
 * @dev AccessList Service features.
 *
 * The AccessList Service contract Role Based Access Control employs the following roles:
 *
 * - UPGRADER_ROLE
 * - PAUSER_ROLE
 * - CONTRACT_ADMIN_ROLE
 * - ACCESS_LIST_ADMIN_ROLE
 */
abstract contract AccessListUpgradeableGasless is AccessListUpgradeable, ERC2771ContextInitializableUpgradeable {
	/// Functions

	/**
	 * @notice Assigns Admin roles for the AccessList, initializes the contract and its inherited base contracts.
	 *
	 * @dev  Calling Conditions:
	 *
	 * - Can only be invoked by functions with the {initializer} or {reinitializer} modifiers.
	 * - Non-zero address `defaultAdmin`.
	 * - Non-zero address `pauser`.
	 * - Non-zero address `upgrader`.
	 *
	 * @param defaultAdmin The account to be granted the "DEFAULT_ADMIN_ROLE".
	 * @param pauser The account to be granted the "PAUSER_ROLE".
	 * @param upgrader Account to be granted the "UPGRADER_ROLE".
	 * @param trustedForwarder The address of the trusted forwarder.
	 */
	/* solhint-disable func-name-mixedcase */
	function __AccessList_init(
		address defaultAdmin,
		address pauser,
		address upgrader,
		address trustedForwarder
	) internal virtual onlyInitializing {
		__AccessList_init(defaultAdmin, pauser, upgrader);
		__ERC2771ContextInitializableUpgradeable_init(trustedForwarder);
	}

	/**
	 * @notice The multicall function has been intentionally disabled to prevent use with gasless operations.
	 *
	 * @dev OpenZeppelin library needs to be upgraded to V4.9.5 or higher if you consider using multicall along with
	 * gasless feature.
	 * @custom:deprecated This function is deprecated and should not be used.
	 */
	function multicall(bytes[] calldata) external virtual override returns (bytes[] memory) {
		revert LibErrors.FunctionDisabled();
	}

	/**
	 * @notice This is a function that applies any validations required to update the trusted forwarder.
	 *
	 * @dev Reverts when the caller does not have the "CONTRACT_ADMIN_ROLE".
	 *
	 * Calling Conditions:
	 *
	 * - Only the "CONTRACT_ADMIN_ROLE" can execute.
	 * - {AccessListUpgradeable} is not paused.
	 */
	function _authorizeTrustedForwarderUpdate() internal virtual override whenNotPaused onlyRole(CONTRACT_ADMIN_ROLE) {}

	/**
	 * @notice This function is used to retrieve the sender of the transaction.
	 * @dev This function is an override of the logic provided by {ContextUpgradeable} function. Instead it uses the
	 * {ERC2771ContextUpgradeable}.{_msgSender} function to retrieve the sender.
	 * @return The address of the sender.
	 */
	function _msgSender()
		internal
		view
		virtual
		override(ContextUpgradeable, ERC2771ContextUpgradeable)
		returns (address)
	{
		return super._msgSender();
	}

	/**
	 * @notice This function is used to retrieve the data of the transaction.
	 * @dev This function is an override of the logic provided by {ContextUpgradeable} function. Instead it uses the
	 * {ERC2771ContextUpgradeable}.{_msgData} function to retrieve the data.
	 * @return The data of the transaction.
	 */
	function _msgData()
		internal
		view
		virtual
		override(ContextUpgradeable, ERC2771ContextUpgradeable)
		returns (bytes calldata)
	{
		return super._msgData();
	}

	/* solhint-enable func-name-mixedcase */
	/**
	 * @dev This empty reserved space is put in place to allow future versions to add new
	 * variables without shifting down storage in the inheritance chain.
	 * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
	 */
	//slither-disable-next-line naming-convention
	uint256[50] private __gap;
}
