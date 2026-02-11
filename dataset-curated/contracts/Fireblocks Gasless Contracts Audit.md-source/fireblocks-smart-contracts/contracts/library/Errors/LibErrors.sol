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

/**
 * @title Errors Library
 * @author Fireblocks
 * @notice The Errors Library provides error messages for the Fireblocks ecosystem of smart contracts.
 */
library LibErrors {
	/// Errors

	/**
	 * @notice Thrown when the account is barred to participate in the system.
	 * @param account The account to be checked.
	 */
	error AccountUnauthorized(address account);

	/**
	 * @notice Thrown when a Renounce Role is called.
	 */
	error RenounceRoleDisabled();

	/**
	 * @dev Indicates a failure that an address is not valid.
	 */
	error InvalidAddress();

	/**
	 * @dev Indicates that there was an attempt to recover tokens from an account that can participate in the system.
	 * @param account The address from which token recovery was attempted.
	 */
	error RecoveryOnActiveAccount(address account);

	/**
	 * @dev Indicates that a contract does not implement a required interface.
	 */
	error InvalidImplementation();

	/**
	 * @dev Indicates that tokenId is not valid.
	 */
	error InvalidTokenId();

	/**
	 * @dev Indicates that the user is not allowed to perform the action for that token.
	 */
	error UnauthorizedTokenManagement();

	/**
	 * @dev Indicates a failure that a value is not valid.
	 */
	error ZeroAmount();

	/**
	 * @dev Indicates a failure while rescuing gas.
	 */
	error SalvageGasFailed();

	/**
	 * @dev Indicates a failure because "DEFAULT_ADMIN_ROLE" was tried to be revoked.
	 */
	error DefaultAdminError();

	/**
	 * @dev Indicates that registry is not set.
	 */
	error AccessRegistryNotSet();

	/**
	 * @dev Indicates that the URI has already been set.
	 * @param tokenId The id of the token.
	 */
	error URIAlreadySet(uint256 tokenId);

	/**
	 * @dev Indicates that the lengths of the arrays do not match.
	 */
	error ArrayLengthMismatch();

	/**
	 * @dev Indicates that the function is disabled.
	 */
	error FunctionDisabled();

	/**
	 * @dev Indicates that the bytecode is empty.
	 */
	error EmptyBytecode();

	/**
	 * @dev Indicates that the contract deployment failed.
	 */
	error DeploymentFailed();

	/**
	 * @dev Indicates that the call data is empty.
	 */
	error EmptyCallData();

	/**
	 * @dev Indicates that the contract is not initialized with the correct version.
	 * @param version The version that the contract should be initialized with.
	 */
	error OnlyVersion(uint8 version);
}
