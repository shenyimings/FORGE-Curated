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
import {ERC20F} from "../ERC20F.sol";
import {LibErrors} from "../library/Errors/LibErrors.sol";
import {ERC2771ContextInitializableUpgradeable} from "../library/MetaTx/ERC2771ContextInitializableUpgradeable.sol";

/**
 * @title ERC20F Gasless
 * @author Fireblocks
 * @notice This contract represents a fungible token within the Fireblocks ecosystem of contracts.
 *
 * The contract utilizes the UUPS (Universal Upgradeable Proxy Standard) for seamless upgradability. This standard
 * enables the contract to be easily upgraded without disrupting its state. By following the UUPS proxy pattern, the
 * ERC20F logic is separated from the storage, allowing upgrades while preserving the existing data. This
 * approach ensures that the contract can adapt and evolve over time, incorporating improvements and new features and
 * mitigating potential attack vectors in future.
 *
 * The contract also supports ERC2771 meta-transactions, implemented through a custom version of the OpenZeppelin
 * {ERC2771ContextUpgradeable} contract, named {ERC2771ContextInitializableUpgradeable}. This customized implementation
 * enables the trusted forwarder address to be set during the contract's initialization, ensuring stricter adherence to
 * the initializable pattern.
 *
 * The ERC20F contract Role Based Access Control employs following roles:
 *
 *  - UPGRADER_ROLE
 *  - PAUSER_ROLE
 *  - CONTRACT_ADMIN_ROLE
 *  - MINTER_ROLE
 *  - BURNER_ROLE
 *  - RECOVERY_ROLE
 *  - SALVAGE_ROLE
 *
 * The ERC20F Token contract can utilize an Access Registry contract to retrieve information on whether an account
 * is authorized to interact with the system.
 */
contract ERC20FGasless is ERC20F, ERC2771ContextInitializableUpgradeable {
	/// Functions

	/**
	 * @notice This function configures the ERC20F contract with the initial state and granting
	 * privileged roles.
	 *
	 * @dev Calling Conditions:
	 *
	 * - Can only be invoked once (controlled via the {initializer} modifier).
	 * - Non-zero address `defaultAdmin`.
	 * - Non-zero address `minter`.
	 * - Non-zero address `pauser`.
	 *
	 * @param _name The name of the token.
	 * @param _symbol The symbol of the token.
	 * @param defaultAdmin The account to be granted the "DEFAULT_ADMIN_ROLE".
	 * @param minter The account to be granted the "MINTER_ROLE".
	 * @param pauser The account to be granted the "PAUSER_ROLE".
	 * @param trustedForwarder The address of the trusted forwarder.
	 */
	function initialize(
		string calldata _name,
		string calldata _symbol,
		address defaultAdmin,
		address minter,
		address pauser,
		address trustedForwarder
	) external virtual initializer {
		if (defaultAdmin == address(0) || pauser == address(0) || minter == address(0)) {
			revert LibErrors.InvalidAddress();
		}
		__ERC2771ContextInitializableUpgradeable_init(trustedForwarder);
		__UUPSUpgradeable_init();
		__ERC20_init(_name, _symbol);
		__ERC20Permit_init(_name);
		__Multicall_init();
		__AccessRegistrySubscription_init(address(0));
		__Salvage_init();
		__ContractUri_init("");
		__Pause_init();
		__RoleAccess_init();

		_grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
		_grantRole(MINTER_ROLE, minter);
		_grantRole(PAUSER_ROLE, pauser);
	}

	/**
	 * @notice This function is disabled in favor of the new {initialize} function.
	 * @dev This function was originally intended to initialize the contract with specific parameters. However, it is now
	 * deprecated, and replaced by a new implementation of the {initialize} function. As a result, this function is
	 * disabled, any attempt to call it will revert with a `FunctionDisabled` error.
	 *
	 * @custom:deprecated This function is deprecated and should not be used. Please use the new {initialize} function
	 * instead.
	 */
	function initialize(string calldata, string calldata, address, address, address) external pure virtual override {
		revert LibErrors.FunctionDisabled();
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
	 * - {ERC20F} is not paused.
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
