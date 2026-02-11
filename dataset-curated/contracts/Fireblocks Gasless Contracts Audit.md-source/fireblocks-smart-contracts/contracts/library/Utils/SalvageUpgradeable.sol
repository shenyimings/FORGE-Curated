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

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

import {LibErrors} from "../Errors/LibErrors.sol";

/**
 * @title Salvage Upgradeable
 * @author Fireblocks
 * @dev This abstract contract provides internal contract logic for rescuing tokens and ETH.
 */
abstract contract SalvageUpgradeable is Initializable, ContextUpgradeable {
	using SafeERC20Upgradeable for IERC20Upgradeable;

	/// Events
	/**
	 * @notice This event is logged when ERC20 tokens are salvaged.
	 *
	 * @param caller The (indexed) address of the entity that triggered the salvage.
	 * @param token The (indexed) address of the ERC20 token which was salvaged.
	 * @param amount The (indexed) amount of tokens salvaged.
	 */
	event TokenSalvaged(address indexed caller, address indexed token, uint256 indexed amount);

	/**
	 * @notice This event is logged when ETH is salvaged.
	 *
	 * @param caller The (indexed) address of the entity that triggered the salvage.
	 * @param amount The (indexed) amount of ETH salvaged.
	 */
	event GasTokenSalvaged(address indexed caller, uint256 indexed amount);

	/// Functions

	/**
	 * @notice This is an initializer function for the abstract contract.
	 * @dev Standard Initializable contract behavior.
	 *
	 * Calling Conditions:
	 *
	 * - Can only be invoked by functions with the {initializer} or {reinitializer} modifiers.
	 */
	/* solhint-disable func-name-mixedcase */
	function __Salvage_init() internal onlyInitializing {}

	/**
	 * @notice A function used to salvage ERC20 tokens sent to the contract using this abstract contract.
	 * @dev Calling Conditions:
	 *
	 * - `amount` is greater than 0.
	 *
	 * This function emits a {TokenSalvaged} event, indicating that funds were salvaged.
	 *
	 * @param token The ERC20 asset which is to be salvaged.
	 * @param amount The amount to be salvaged.
	 */
	function salvageERC20(IERC20Upgradeable token, uint256 amount) external virtual {
		if (amount == 0) {
			revert LibErrors.ZeroAmount();
		}
		_authorizeSalvageERC20();
		emit TokenSalvaged(_msgSender(), address(token), amount);
		token.safeTransfer(_msgSender(), amount);
	}

	/**
	 * @notice A function used to salvage ETH sent to the contract using this abstract contract.
	 * @dev Calling Conditions:
	 *
	 * - `amount` is greater than 0.
	 *
	 * This function emits a {GasTokenSalvaged} event, indicating that funds were salvaged.
	 *
	 * @param amount The amount to be salvaged.
	 */
	function salvageGas(uint256 amount) external virtual {
		if (amount == 0) {
			revert LibErrors.ZeroAmount();
		}
		_authorizeSalvageGas();
		emit GasTokenSalvaged(_msgSender(), amount);
		(bool succeed, ) = _msgSender().call{value: amount}("");
		if (!succeed) {
			revert LibErrors.SalvageGasFailed();
		}
	}

	/**
	 * @notice This function is designed to be overridden in inheriting contracts.
	 * @dev Override this function to implement RBAC control.
	 */
	function _authorizeSalvageERC20() internal virtual;

	/**
	 * @notice This function is designed to be overridden in inheriting contracts.
	 * @dev Override this function to implement RBAC control.
	 */
	function _authorizeSalvageGas() internal virtual;

	/* solhint-enable func-name-mixedcase */
	/**
	 * @dev This empty reserved space is put in place to allow future versions to add new
	 * variables without shifting down storage in the inheritance chain.
	 * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
	 */
	//slither-disable-next-line naming-convention
	uint256[50] private __gap;
}
