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
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/**
 * @title Pause Upgradeable
 * @author Fireblocks
 * @dev This abstract contract provides internal contract logic for pausing and unpausing the contract.
 */
abstract contract PauseUpgradeable is Initializable, PausableUpgradeable {
	/// Functions

	/**
	 * @notice This is an initializer function for the abstract contract.
	 * @dev Standard Initializable contract behavior.
	 *
	 * Calling Conditions:
	 *
	 * - Can only be invoked by functions with the {initializer} or {reinitializer} modifiers.
	 */
	function __Pause_init() internal onlyInitializing {
		__Pausable_init();
	}

	/**
	 * @notice This is a function used to pause the contract.
	 *
	 * @dev Calling Conditions:
	 *
	 * - Contract is not paused. (checked internally by {Pausable._pause})
	 *
	 * This function emits a {Paused} event as part of {PausableUpgradeable._pause}.
	 */
	function pause() external virtual {
		_authorizePause();
		_pause();
	}

	/**
	 * @notice This is a function used to unpause the contract.
	 *
	 * @dev Calling Conditions:
	 *
	 * - Contract is paused. (checked internally by {Pausable._unpause})
	 *
	 * This function emits an {Unpaused} event as part of {PausableUpgradeable._unpause}.
	 */
	function unpause() external virtual {
		_authorizePause();
		_unpause();
	}

	/**
	 * @notice This function is designed to be overridden in inheriting contracts.
	 * @dev Override this function to implement RBAC control.
	 */
	function _authorizePause() internal virtual;

	/* solhint-enable func-name-mixedcase */
	/**
	 * @dev This empty reserved space is put in place to allow future versions to add new
	 * variables without shifting down storage in the inheritance chain.
	 * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
	 */
	//slither-disable-next-line naming-convention
	uint256[50] private __gap;
}
