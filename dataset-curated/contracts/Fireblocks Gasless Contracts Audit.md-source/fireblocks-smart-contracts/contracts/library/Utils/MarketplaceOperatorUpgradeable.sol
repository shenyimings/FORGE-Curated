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
 * @title Marketplace Operator Upgradeable
 * @author Fireblocks
 * @dev This abstract contract provides internal contract logic for enabling contract editing
 * on external marketplaces like Opensea.
 */
abstract contract MarketplaceOperatorUpgradeable is Initializable, ContextUpgradeable {
	/// State

	/**
	 * @notice This field returns the address that can edit contract details on an external marketplace.
	 * @dev This state variable is queried by the owner() function.
	 */
	address internal marketplaceOperator;

	/// Events

	/**
	 * @notice This event is logged when the marketplace operator is updated.
	 *
	 * @param caller The (indexed) address of the entity that triggered the update.
	 * @param oldOperator The (indexed) address of the previous marketplace operator.
	 * @param newOperator The (indexed) address of the new marketplace operator.
	 */
	event MarketplaceOperatorUpdated(address indexed caller, address indexed oldOperator, address indexed newOperator);

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
	function __MarketplaceOperator_init(address _marketplaceOperator) internal onlyInitializing {
		_updateMarketplaceOperator(_marketplaceOperator);
	}

	/**
	 * @notice This is a function used to update the `marketplaceOperator`.
	 * @dev This function emits a {MarketplaceOperatorUpdated} event as part of {_updateMarketplaceOperator}.
	 *
	 * @param _marketplaceOperator The address of the new marketplace operator.
	 */
	function updateMarketplaceOperator(address _marketplaceOperator) external virtual {
		_authorizeMarketplaceOperatorUpdate();
		_updateMarketplaceOperator(_marketplaceOperator);
	}

	/**
	 * @notice This function returns the address that can edit contract details on an external marketplace.
	 */
	function owner() external view virtual returns (address) {
		return marketplaceOperator;
	}

	/**
	 * @notice This is a function used to update `marketplaceOperator` field.
	 * @dev This function emits a {MarketplaceOperatorUpdated} event.
	 *
	 * @param _marketplaceOperator The address of the new marketplace operator.
	 */
	function _updateMarketplaceOperator(address _marketplaceOperator) internal virtual {
		emit MarketplaceOperatorUpdated(_msgSender(), marketplaceOperator, _marketplaceOperator);
		marketplaceOperator = _marketplaceOperator;
	}

	/**
	 * @notice This function is designed to be overridden in inheriting contracts.
	 * @dev Override this function to implement RBAC control.
	 */
	function _authorizeMarketplaceOperatorUpdate() internal virtual;

	/* solhint-enable func-name-mixedcase */
	/**
	 * @dev This empty reserved space is put in place to allow future versions to add new
	 * variables without shifting down storage in the inheritance chain.
	 * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
	 */
	//slither-disable-next-line naming-convention
	uint256[49] private __gap;
}
