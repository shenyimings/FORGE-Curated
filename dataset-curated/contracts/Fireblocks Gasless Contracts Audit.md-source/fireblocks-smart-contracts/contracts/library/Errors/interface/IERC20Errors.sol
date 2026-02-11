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
// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/draft-IERC6093.sol)
pragma solidity 0.8.20;

/**
 * @dev Standard ERC20 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC20 tokens.
 */
interface IERC20Errors {
	/**
	 * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
	 * @param sender Address whose tokens are being transferred.
	 * @param balance Current balance for the interacting account.
	 * @param needed Minimum amount required to perform a transfer.
	 */
	error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

	/**
	 * @dev Indicates a failure with the token `sender`. Used in transfers.
	 * @param sender Address whose tokens are being transferred.
	 */
	error ERC20InvalidSender(address sender);

	/**
	 * @dev Indicates a failure with the token `receiver`. Used in transfers.
	 * @param receiver Address to which tokens are being transferred.
	 */
	error ERC20InvalidReceiver(address receiver);

	/**
	 * @dev Indicates a failure with the `spender`’s `allowance`. Used in transfers.
	 * @param spender Address that may be allowed to operate on tokens without being their owner.
	 * @param allowance Amount of tokens a `spender` is allowed to operate with.
	 * @param needed Minimum amount required to perform a transfer.
	 */
	error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

	/**
	 * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
	 * @param approver Address initiating an approval operation.
	 */
	error ERC20InvalidApprover(address approver);

	/**
	 * @dev Indicates a failure with the `spender` to be approved. Used in approvals.
	 * @param spender Address that may be allowed to operate on tokens without being their owner.
	 */
	error ERC20InvalidSpender(address spender);
}
