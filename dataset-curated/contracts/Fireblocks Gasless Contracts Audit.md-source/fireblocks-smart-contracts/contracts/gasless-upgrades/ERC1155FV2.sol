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
import {ERC1155F} from "../ERC1155F.sol";
import {LibErrors} from "../library/Errors/LibErrors.sol";
import {ERC2771ContextInitializableUpgradeable} from "../library/MetaTx/ERC2771ContextInitializableUpgradeable.sol";

/**
 * @title ERC1155F V2
 * @notice This contract represents a fungible token within the Fireblocks ecosystem of contracts.
 *
 * ERC1155F V2 builds upon the original version by introducing a new feature. It maintains its core functionality by
 * inheriting from the original ERC1155F contract and adds the gasless meta-transaction feature by inheriting from the
 * ERC2771ContextInitializableUpgradeable contract. It maintains upgradability through the UUPS (Universal Upgradeable
 * Proxy Standard) pattern. This upgrade mechanism preserves the existing state and storage, ensuring a safe transition
 * for existing users while allowing new users to initialize the contract.
 *
 * In addition to the original version, ERC1155F V2 supports ERC2771 meta-transactions, implemented through a custom
 * version of the OpenZeppelin {ERC2771ContextUpgradeable} contract, named {ERC2771ContextInitializableUpgradeable}.
 * This ensures that the trusted forwarder address can be set during the contract's initialization, adhering to the
 * initializable pattern.
 *
 * The following roles are employed in ERC1155F V2, consistent with V1:
 *
 *  - UPGRADER_ROLE
 *  - PAUSER_ROLE
 *  - CONTRACT_ADMIN_ROLE
 *  - MINTER_ROLE
 *  - BURNER_ROLE
 *  - RECOVERY_ROLE
 *  - SALVAGE_ROLE
 *
 * Additionally, ERC1155F V2 continues to utilize an Access Registry contract to determine whether an account is authorized
 * to interact with the system, ensuring robust access control.
 *
 * @dev This version introduces the following changes:
 *
 * - Adds the {ERC2771ContextInitializableUpgradeable} contract to support gasless meta-transactions
 * - Adds an initializer function to set the trusted forwarder address
 * - Inherits from the original ERC1155F contract to maintain core functionality
 * - Inherits from the ERC2771ContextInitializableUpgradeable contract to support gasless meta-transactions
 * - Maintains upgradability through the UUPS pattern
 * - Preserves the existing state and storage during upgrades
 * - Maintains the existing roles and access control mechanisms
 *
 * @custom:version 2.0.0
 */
contract ERC1155FV2 is ERC1155F, ERC2771ContextInitializableUpgradeable {
	/// modifiers

	/**
	 * @notice This modifier is used to restrict the execution of functions based on the version of the contract.
	 * @dev This modifier uses the {_getInitializedVersion} function to check the version of the contract. If the version
	 * does not matches the provided version, it reverts with the error message `OnlyVersion`.
	 * @param _version The version to compare with the initialized version.
	 */
	modifier onlyVersion(uint8 _version) virtual {
		if (_getInitializedVersion() != _version) {
			revert LibErrors.OnlyVersion(_version);
		}
		_;
	}

	/// functions

	/**
	 * @notice This function configures the ERC1155F contract with the initial state and granting
	 * privileged roles.
	 *
	 * @dev Calling Conditions:
	 *
	 * - Can only be invoked once (controlled via the {reinitializer} modifier).
	 *
	 * @param trustedForwarder The address of the trusted forwarder.
	 */
	function initializeV2(address trustedForwarder) external virtual onlyVersion(1) reinitializer(2) {
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
	 * - {ERC1155FV2} is not paused.
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
}
