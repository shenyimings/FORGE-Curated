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
 * @title Token Uri Upgradeable
 * @author Fireblocks
 * @dev This abstract contract provides internal contract logic for upgrading the token URI.
 */
abstract contract TokenUriUpgradeable is Initializable, ContextUpgradeable {
	/// State

	/**
	 * @notice This field is a mapping of token IDs to their respective token URIs.
	 * @dev This internal field is used to store the token URI for each token ID.
	 */
	mapping(uint256 tokenId => string tokenUri) internal _tokenUri;

	/// Events

	/**
	 * @notice This event is logged when the token URI is updated.
	 *
	 * @param caller The (indexed) address of the entity that triggered the update.
	 * @param tokenId The (indexed) ID of the token whose URI is to be updated.
	 * @param oldUri The URI previously associated with the token.
	 * @param newUri The new URI associated with the token.
	 */
	event TokenUriUpdated(address indexed caller, uint256 indexed tokenId, string oldUri, string newUri);

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
	function __TokenUri_init() internal onlyInitializing {}

	/**
	 * @notice This is a function used to update `_tokenUri` field.
	 * @dev This function emits a {TokenUriUpdated} event as part of {_tokenUriUpdate}.
	 *
	 * @param _tokenId The ID of the token whose URI is to be updated.
	 * @param _uri A URI link pointing to the current URI associated with the token.
	 */
	function tokenUriUpdate(uint256 _tokenId, string calldata _uri) external virtual {
		_authorizeTokenUriUpdate();
		_tokenUriUpdate(_tokenId, _uri);
	}

	/**
	 * @notice This is a function used to update `_tokenUri` field.
	 * @dev This function emits a {TokenUriUpdated} event when uri is successfully updated.
	 *
	 * @param _tokenId The ID of the token whose URI is to be updated.
	 * @param _uri A URI link pointing to the current URI associated with the token.
	 */
	function _tokenUriUpdate(uint256 _tokenId, string memory _uri) internal virtual {
		emit TokenUriUpdated(_msgSender(), _tokenId, _tokenUri[_tokenId], _uri);
		_tokenUri[_tokenId] = _uri;
	}

	/**
	 * @notice This function is designed to be overridden in inheriting contracts.
	 * @dev Override this function to implement RBAC control.
	 */
	function _authorizeTokenUriUpdate() internal virtual;

	/* solhint-enable func-name-mixedcase */
	/**
	 * @dev This empty reserved space is put in place to allow future versions to add new
	 * variables without shifting down storage in the inheritance chain.
	 * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
	 */
	//slither-disable-next-line naming-convention
	uint256[49] private __gap;
}
