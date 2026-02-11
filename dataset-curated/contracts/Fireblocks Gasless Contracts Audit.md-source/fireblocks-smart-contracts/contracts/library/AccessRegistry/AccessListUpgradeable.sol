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
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import {IERC1822ProxiableUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/draft-IERC1822Upgradeable.sol";
import {IERC1967Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC1967Upgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {IAccessRegistry} from "./interface/IAccessRegistry.sol";
import {ContractUriUpgradeable} from "../Utils/ContractUriUpgradeable.sol";
import {PauseUpgradeable} from "../Utils/PauseUpgradeable.sol";
import {RoleAccessUpgradeable} from "../Utils/RoleAccessUpgradeable.sol";
import {LibErrors} from "../Errors/LibErrors.sol";

/**
 * @title AccessList Upgradeable
 * @author Fireblocks
 * @notice The AccessList Upgradeable establishes an on-chain AccessList for the Fireblocks ecosystem of smart contracts.
 * It maintains a registry of addresses allowed to participate in the system. It is also capable of verifying more
 * complex conditions using the data provided from the function call.
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
abstract contract AccessListUpgradeable is
	Initializable,
	IAccessRegistry,
	ContractUriUpgradeable,
	PauseUpgradeable,
	RoleAccessUpgradeable,
	MulticallUpgradeable,
	UUPSUpgradeable
{
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

	/// Constants

	/**
	 * @notice The Access Control identifier for the Upgrader Role.
	 * An account with "UPGRADER_ROLE" can upgrade the implementation contract address.
	 *
	 * @dev This constant holds the hash of the string "UPGRADER_ROLE".
	 */
	bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

	/**
	 * @notice The Access Control identifier for the Pauser Role.
	 * An account with "PAUSER_ROLE" can pause and unpause the {AccessLis} contract.
	 *
	 * @dev This constant holds the hash of the string "PAUSER_ROLE".
	 */
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

	/**
	 * @notice The Access Control identifier for the Contract Admin Role.
	 * An account with "CONTRACT_ADMIN_ROLE" can upgrade the contract uri.
	 *
	 * @dev This constant holds the hash of the string "CONTRACT_ADMIN_ROLE".
	 */
	bytes32 public constant CONTRACT_ADMIN_ROLE = keccak256("CONTRACT_ADMIN_ROLE");

	/**
	 * @notice The Access Control identifier for the Access List Admin Role.
	 * An account with "ACCESS_LIST_ADMIN_ROLE" can add or remove addresses from the Access List.
	 *
	 * @dev This constant holds the hash of the string "ACCESS_LIST_ADMIN_ROLE".
	 */
	bytes32 public constant ACCESS_LIST_ADMIN_ROLE = keccak256("ACCESS_LIST_ADMIN_ROLE");

	/// State

	/**
	 * @notice A set that tracks address Access List membership.
	 * @dev Default `false` indicates that an address is not in the Access List. A value of `true`
	 * indicates the address is in the Access List.
	 */
	EnumerableSetUpgradeable.AddressSet internal _accessList;

	/// Events

	/**
	 * @notice This event is logged when an address is added to the Access list.
	 *
	 * @dev Notifies that the ability of logged address to participant is changed as per the implementation contract.
	 *
	 * @param caller The (indexed) account which called the {accessListAdd} function to add the address to the
	 * `_accessList`.
	 * @param account The (indexed) address which was added to the Access list.
	 */
	event AccessListAddressAdded(address indexed caller, address indexed account);

	/**
	 * @notice This event is logged when an address is removed from the Access list.
	 * @dev Notifies that the ability of logged address to participant is changed as per the implementation contract.
	 *
	 * @param caller The (indexed) account which called the {accessListRemove} function to remove the address from the
	 * `_accessList`.
	 * @param account The (indexed) address which was removed from the Access list.
	 */
	event AccessListAddressRemoved(address indexed caller, address indexed account);

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
	 */
	/* solhint-disable func-name-mixedcase */
	function __AccessList_init(address defaultAdmin, address pauser, address upgrader) internal virtual onlyInitializing {
		if (defaultAdmin == address(0) || pauser == address(0) || upgrader == address(0)) {
			revert LibErrors.InvalidAddress();
		}

		__Pausable_init();
		__ContractUri_init("");
		__Multicall_init();
		__Pausable_init();
		__RoleAccess_init();
		__UUPSUpgradeable_init();

		_grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
		_grantRole(UPGRADER_ROLE, upgrader);
		_grantRole(PAUSER_ROLE, pauser);
	}

	/**
	 * @notice This function adds a list of given address to the AccessList. This will allow the specified addresses
	 * to interact with other contracts within the Fireblocks ecosystem of smart contracts. The function can be
	 * called by the address which has the "ACCESS_LIST_ADMIN_ROLE".
	 *
	 * @dev Calling Conditions:
	 *
	 * - {AccessListUpgradeable} is not paused.
	 * - The caller must hold the "ACCESS_LIST_ADMIN_ROLE" role.
	 * - All the addresses in the`accounts` array must be a non-zero address.
	 *
	 * This function emits a {AccessListAddressAdded} event only when it successfully adds an address to
	 * the `_accessList` mapping, given that the address was previously not present on AccessList.
	 *
	 * @param accounts The list addresses to be added to the AccessList.
	 */
	function accessListAdd(address[] calldata accounts) external virtual whenNotPaused onlyRole(ACCESS_LIST_ADMIN_ROLE) {
		uint256 length = accounts.length;
		for (uint256 i = 0; i < length; ++i) {
			if (accounts[i] == address(0)) {
				revert LibErrors.InvalidAddress();
			}
			if (_accessList.add(accounts[i])) {
				emit AccessListAddressAdded(_msgSender(), accounts[i]);
			}
		}
	}

	/**
	 * @notice This function removes a list of given address from the AccessList. The function can be
	 * called by the address which has the "ACCESS_LIST_ADMIN_ROLE".
	 *
	 * @dev Calling Conditions:
	 *
	 * - {AccessListUpgradeable} is not paused.
	 * - The caller must hold the "ACCESS_LIST_ADMIN_ROLE" role.
	 *
	 * This function emits a {AccessListAddressRemoved} event only when it successfully removes an address from
	 * the `_accessList` mapping, given that the address was previously present on AccessList.
	 *
	 * @param accounts The list addresses to be removed from the AccessList.
	 */
	function accessListRemove(
		address[] calldata accounts
	) external virtual whenNotPaused onlyRole(ACCESS_LIST_ADMIN_ROLE) {
		uint256 length = accounts.length;
		for (uint256 i = 0; i < length; ++i) {
			if (_accessList.remove(accounts[i])) {
				emit AccessListAddressRemoved(_msgSender(), accounts[i]);
			}
		}
	}

	/**
	 * @notice This function returns the list of addresses that are in the access list.
	 *
	 * @dev This function returns the list of addresses that are in the `_accessList`.
	 *
	 * Note: This is designed to be a helper function that is called from off-chain.
	 * If the `_accessList` is large, this function will consume a lot of gas or revert.
	 *
	 * @return The list of addresses that are in the access list.
	 */
	function getAccessList() external view virtual returns (address[] memory) {
		return _accessList.values();
	}

	/**
	 * @notice This function informs about the address's access to the system.
	 *
	 * @dev This function returns `true` if the address is allowed, otherwise it returns `false`.
	 * The parameter `data` is ignored in this implementation of the interface as it serves as a placeholder for
	 * future implementations.
	 *
	 * @param account The address to be checked.
	 * @param caller The address calling the function requiring an access check.
	 * @param data The data associated with the function call
	 * @return `true` if the address is allowed, otherwise it returns `false`.
	 */
	function hasAccess(
		address account,
		address caller,
		bytes calldata data
	) external view virtual override returns (bool);

	/**
	 * @notice This is a function used to get the version of the contract.
	 * @dev This function get the latest deployment version from the {Initializable}.{_getInitializedVersion}.
	 * With every new deployment, the version number will be incremented.
	 * @return The version of the contract.
	 */
	function version() external view virtual returns (uint64) {
		return uint64(super._getInitializedVersion());
	}

	/**
	 * @notice Returns true if this contract implements the interface defined by `interfaceId`. See the corresponding
	 * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section] to learn more about
	 * how these ids are created.
	 *
	 * @dev This function verifies that the {AccessList} implements {IAccessRegistry} and parent interfaces.
	 * @param interfaceId The interface identifier, as specified in ERC-165
	 * @return `true` if the contract implements `interfaceID` , `false` otherwise
	 */
	function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
		return
			interfaceId == type(IAccessRegistry).interfaceId ||
			interfaceId == type(IERC1967Upgradeable).interfaceId ||
			interfaceId == type(IERC1822ProxiableUpgradeable).interfaceId ||
			super.supportsInterface(interfaceId);
	}

	/**
	 * @notice This is a function that applies any validations required to allow upgrade operations.
	 *
	 * @dev Reverts when the caller does not have the "UPGRADER_ROLE".
	 *
	 * Calling Conditions:
	 *
	 * - Only the "UPGRADER_ROLE" can execute.
	 *
	 * @param newImplementation The address of the new logic contract.
	 */
	/* solhint-disable no-empty-blocks */
	function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(UPGRADER_ROLE) {}

	/**
	 * @notice This is a function that applies any validations required to allow Contract Uri updates.
	 *
	 * @dev Reverts when the caller does not have the "CONTRACT_ADMIN_ROLE".
	 *
	 * Calling Conditions:
	 *
	 * - Only the "CONTRACT_ADMIN_ROLE" can execute.
	 */
	/* solhint-disable no-empty-blocks */
	function _authorizeContractUriUpdate() internal virtual override whenNotPaused onlyRole(CONTRACT_ADMIN_ROLE) {}

	/**
	 * @notice This is a function that applies any validations required to allow Pause operations (like pause or unpause) to be executed.
	 *
	 * @dev Reverts when the caller does not have the "PAUSER_ROLE".
	 *
	 * Calling Conditions:
	 *
	 * - Only the "PAUSER_ROLE" can execute.
	 */
	/* solhint-disable no-empty-blocks */
	function _authorizePause() internal virtual override onlyRole(PAUSER_ROLE) {}

	/**
	 * @notice This is a function that applies any validations required to allow Role Access operation (like grantRole or revokeRole ) to be executed.
	 *
	 * @dev Reverts when the contract is paused.
	 */
	/* solhint-disable no-empty-blocks */
	function _authorizeRoleAccess() internal virtual override whenNotPaused {}

	/* solhint-enable func-name-mixedcase */
	/**
	 * @dev This empty reserved space is put in place to allow future versions to add new
	 * variables without shifting down storage in the inheritance chain.
	 * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
	 */
	//slither-disable-next-line naming-convention
	uint256[48] private __gap;
}
