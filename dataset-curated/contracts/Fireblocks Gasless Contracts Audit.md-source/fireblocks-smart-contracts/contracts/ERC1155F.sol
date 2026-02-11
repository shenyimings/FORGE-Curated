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

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155SupplyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC1822ProxiableUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/draft-IERC1822Upgradeable.sol";
import {IERC1967Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC1967Upgradeable.sol";
import {IERC1155Errors} from "./library/Errors/interface/IERC1155Errors.sol";

import {LibErrors} from "./library/Errors/LibErrors.sol";
import {AccessRegistrySubscriptionUpgradeable} from "./library/AccessRegistry/AccessRegistrySubscriptionUpgradeable.sol";
import {SalvageUpgradeable} from "./library/Utils/SalvageUpgradeable.sol";
import {ContractUriUpgradeable} from "./library/Utils/ContractUriUpgradeable.sol";
import {TokenUriUpgradeable} from "./library/Utils/TokenUriUpgradeable.sol";
import {PauseUpgradeable} from "./library/Utils/PauseUpgradeable.sol";
import {RoleAccessUpgradeable} from "./library/Utils/RoleAccessUpgradeable.sol";
import {MarketplaceOperatorUpgradeable} from "./library/Utils/MarketplaceOperatorUpgradeable.sol";

/**
 * @title ERC1155F
 * @author Fireblocks
 * @notice This contract represents a modified ERC1155 token within the Fireblocks ecosystem of contracts.
 *
 * The contract utilizes the UUPS (Universal Upgradeable Proxy Standard) for seamless upgradability. This standard
 * enables the contract to be easily upgraded without disrupting its state. By following the UUPS proxy pattern, the
 * ERC1155F logic is separated from the storage, allowing upgrades while preserving the existing data. This
 * approach ensures that the contract can adapt and evolve over time, incorporating improvements and new features and
 * mitigating potential attack vectors in future.
 *
 * The ERC1155F contract Role Based Access Control employs following roles:
 *
 *  - UPGRADER_ROLE
 *  - PAUSER_ROLE
 *  - CONTRACT_ADMIN_ROLE
 *  - MINTER_ROLE
 *  - BURNER_ROLE
 *  - RECOVERY_ROLE
 *  - SALVAGE_ROLE
 *
 * The ERC1155F Token contract can utilize an Access Registry contract to retrieve information on whether an account
 * is authorized to interact with the system.
 */
contract ERC1155F is
	Initializable,
	ERC1155Upgradeable,
	ERC1155SupplyUpgradeable,
	AccessRegistrySubscriptionUpgradeable,
	MulticallUpgradeable,
	SalvageUpgradeable,
	ContractUriUpgradeable,
	TokenUriUpgradeable,
	PauseUpgradeable,
	RoleAccessUpgradeable,
	MarketplaceOperatorUpgradeable,
	IERC1155Errors,
	UUPSUpgradeable
{
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
	 * An account with "PAUSER_ROLE" can pause the contract.
	 *
	 * @dev This constant holds the hash of the string "PAUSER_ROLE".
	 */
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

	/**
	 * @notice The Access Control identifier for the Contract Admin Role.
	 * An account with "CONTRACT_ADMIN_ROLE" can update the contract URI.
	 *
	 * @dev This constant holds the hash of the string "CONTRACT_ADMIN_ROLE".
	 */
	bytes32 public constant CONTRACT_ADMIN_ROLE = keccak256("CONTRACT_ADMIN_ROLE");

	/**
	 * @notice The Access Control identifier for the Minter Role.
	 * An account with "MINTER_ROLE" can mint tokens.
	 *
	 * @dev This constant holds the hash of the string "MINTER_ROLE".
	 */
	bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

	/**
	 * @notice The Access Control identifier for the Burner Role.
	 * An account with "BURNER_ROLE" can burn tokens.
	 *
	 * @dev This constant holds the hash of the string "BURNER_ROLE".
	 */
	bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

	/**
	 * @notice The Access Control identifier for the Recovery Role.
	 * An account with "RECOVERY_ROLE" can recover tokens.
	 *
	 * @dev This constant holds the hash of the string "RECOVERY_ROLE".
	 */
	bytes32 public constant RECOVERY_ROLE = keccak256("RECOVERY_ROLE");

	/**
	 * @notice The Access Control identifier for the Salvager Role.
	 * An account with "SALVAGE_ROLE" can salvage tokens and gas.
	 *
	 * @dev This constant holds the hash of the string "SALVAGE_ROLE".
	 */
	bytes32 public constant SALVAGE_ROLE = keccak256("SALVAGE_ROLE");

	/**
	 * @notice The name of the token.
	 */
	string public name;

	/**
	 * @notice The symbol of the token.
	 */
	string public symbol;

	/// Events

	/**
	 * @notice This event is logged when the tokens are recovered from an address that is not allowed
	 * to participate in the system.
	 *
	 * @param caller The (indexed) address of the caller.
	 * @param account The (indexed) account the tokens were recovered from.
	 * @param tokenId The (indexed) ID of the token recovered.
	 * @param amount The number of tokens recovered.
	 * @param data Additional data with no specified format.
	 */
	event TokensRecovered(
		address indexed caller,
		address indexed account,
		uint256 indexed tokenId,
		uint256 amount,
		bytes data
	);

	/// Functions

	/**
	 * @notice This function acts as the constructor of the contract.
	 * @dev This function disables the initializers.
	 */
	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/**
	 * @notice This function configures the ERC1155F contract with the initial state and granting
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
	 */
	function initialize(
		string calldata _name,
		string calldata _symbol,
		address defaultAdmin,
		address minter,
		address pauser
	) external virtual initializer {
		if (defaultAdmin == address(0) || pauser == address(0) || minter == address(0)) {
			revert LibErrors.InvalidAddress();
		}
		__ERC1155_init("");
		__ERC1155Supply_init();
		__Multicall_init();
		__AccessRegistrySubscription_init(address(0));
		__Salvage_init();
		__ContractUri_init("");
		__TokenUri_init();
		__Pause_init();
		__RoleAccess_init();
		__MarketplaceOperator_init(defaultAdmin);
		__UUPSUpgradeable_init();

		_grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
		_grantRole(MINTER_ROLE, minter);
		_grantRole(PAUSER_ROLE, pauser);

		name = _name;
		symbol = _symbol;
	}

	/**
	 * @notice This is a function used to recover an ERC1155 token from an address not on the Allowlist.
	 *
	 * @dev Calling Conditions:
	 *
	 * - `caller` of this function must have the "RECOVERY_ROLE".
	 * - {ERC1155F} is not paused.(checked internally by {_beforeTokenTransfer}).
	 * - `accessRegistry` must be set.
	 * - `account` address must be not be allowed to hold tokens.
	 * - `account` must be a non-zero address. (checked internally in {ERC1155Upgradeable._safeTransferFrom})
	 *
	 * This function emits a {TokensRecovered} event, signalling that the token of the given address were recovered.
	 *
	 * @param account The address to recover the token from.
	 * @param tokenId The ID of the token to be recovered.
	 * @param amount The amount of tokens to be recovered.
	 * @param data Additional data with no specified format, sent in call to `_safeTransferFrom`.
	 */
	function recoverTokens(
		address account,
		uint256 tokenId,
		uint256 amount,
		bytes calldata data
	) external virtual onlyRole(RECOVERY_ROLE) {
		if (address(accessRegistry) == address(0)) revert LibErrors.AccessRegistryNotSet();
		if (accessRegistry.hasAccess(account, _msgSender(), _msgData())) revert LibErrors.RecoveryOnActiveAccount(account);
		emit TokensRecovered(_msgSender(), account, tokenId, amount, data);
		_safeTransferFrom(account, _msgSender(), tokenId, amount, data);
	}

	/**
	 * @notice This is a function used to issue new ERC1155 tokens.
	 * The caller will issue a token to the `account` address.
	 *
	 * Note:
	 *  - If the URI for a token `id` has already been set, you must pass an
	 * empty `_uri`.
	 *
	 * @dev Calling Conditions:
	 *
	 * - Can only be invoked by the address that has the role "MINTER_ROLE".
	 * - {ERC1155F} is not paused. (checked internally by {_beforeTokenTransfer})
	 * - `account` is a non-zero address. (checked internally by {ERC1155Upgradeable}.{_mint})
	 * - `account` is allowed to receive tokens.
	 *
	 * This function emits a {Transfer} event as part of {ERC1155Upgradeable._mint}.
	 * This function emits a {TokenUriUpdated} event as part of {TokenUriUpgradeable._tokenUriUpdate}.
	 *
	 * @param account The address that will receive the issued tokens.
	 * @param id The ID of the tokens to be issued.
	 * @param amount The amount of tokens to be issued.
	 * @param _uri A URI link pointing to the current URI associated with the token.
	 * @param data Additional data with no specified format, sent in call to `_mint`.
	 */
	function mint(
		address account,
		uint256 id,
		uint256 amount,
		string calldata _uri,
		bytes calldata data
	) external virtual onlyRole(MINTER_ROLE) {
		_requireHasAccess(account, false);
		// Revert if the URI is already set and a new URI is passed.
		if (bytes(_uri).length != 0) {
			if (bytes(_tokenUri[id]).length == 0) {
				_tokenUriUpdate(id, _uri);
			} else {
				revert LibErrors.URIAlreadySet(id);
			}
		}
		_mint(account, id, amount, data);
	}

	/**
	 * @notice This is a function used to burn an ERC1155 token.
	 * The caller will burn a token from their own address.
	 *
	 * @dev Calling Conditions:
	 *
	 * - Can only be invoked by the address that has the role "BURNER_ROLE".
	 * - {ERC1155F} is not paused. (checked internally by {_beforeTokenTransfer})
	 * - `amount` is less than or equal to the caller's balance. (checked internally by {ERC1155Upgradeable}.{_burn})
	 * - `amount` is greater than 0.
	 * - `caller` is allowed to hold tokens.
	 *
	 * This function emits a {Transfer} event as part of {ERC1155Upgradeable._burn}.
	 *
	 * @param id The ID of the token to be burned.
	 * @param amount The amount of tokens to be burned.
	 */
	function burn(uint256 id, uint256 amount) external virtual onlyRole(BURNER_ROLE) {
		if (amount == 0) revert LibErrors.ZeroAmount();
		_requireHasAccess(_msgSender(), true);
		_burn(_msgSender(), id, amount);
	}

	/**
	 * @notice This is a function used to issue a batch of new ERC1155 tokens.
	 * The caller will issue a token to the `account` address.
	 *
	 * @dev Calling Conditions:
	 *
	 * - Can only be invoked by the address that has the role "MINTER_ROLE".
	 * - {ERC1155F} is not paused. (checked internally by {_beforeTokenTransfer})
	 * - `to` is a non-zero address. (checked internally by {ERC1155Upgradeable}.{_mintBatch})
	 * - `to` is allowed to receive tokens.
	 * - `amount` length and `ids` length must be equal.  (checked internally by {ERC1155Upgradeable}.{_mintBatch})
	 *
	 * This function emits a {TransferBatch} event as part of {ERC1155Upgradeable._mintBatch}.
	 * This function emits a {TokenUriUpdated} event as part of {TokenUriUpgradeable._tokenUriUpdate}. For every
	 * token ID that is issued.
	 *
	 * @param to The address that will receive the issued tokens.
	 * @param ids The array of IDs of the tokens to be issued.
	 * @param amounts The array amounts of tokens to be issued.
	 * @param uris An array of URI links pointing to the current URI associated with the tokens.
	 * @param data Additional data with no specified format, sent in call to `_mint`.
	 */
	function mintBatch(
		address to,
		uint256[] calldata ids,
		uint256[] calldata amounts,
		string[] calldata uris,
		bytes calldata data
	) external virtual onlyRole(MINTER_ROLE) {
		_requireHasAccess(to, false);
		uint256 length = ids.length;
		if (length != uris.length) revert LibErrors.ArrayLengthMismatch();
		for (uint256 i = 0; i < length; ++i) {
			string memory _uri = uris[i];
			uint256 id = ids[i];
			// Revert if the URI is already set and a new URI is passed.
			if (bytes(_uri).length != 0) {
				if (bytes(_tokenUri[id]).length == 0) {
					_tokenUriUpdate(id, _uri);
				} else {
					revert LibErrors.URIAlreadySet(id);
				}
			}
		}
		_mintBatch(to, ids, amounts, data);
	}

	/**
	 * @notice This is a function used to burn a batch of ERC1155 tokens.
	 * The caller will burn a token from their own address.
	 *
	 * @dev Calling Conditions:
	 *
	 * - Can only be invoked by the address that has the role "BURNER_ROLE".
	 * - {ERC1155F} is not paused. (checked internally by {_beforeTokenTransfer})
	 * - `amount` is less than or equal to the caller's balance.
	 * (checked internally by {ERC1155Upgradeable}.{_burnBatch})
	 * - `caller` is allowed to hold tokens.
	 * - `amount` length and `ids` length must be equal.  (checked internally by {ERC1155Upgradeable}.{_burnBatch})
	 *
	 * This function emits a {TransferBatch} event as part of {ERC1155Upgradeable._burnBatch}.
	 *
	 * Note: Burning zero amounts are not checked in the batch function to save gas and preserve code hygiene
	 *
	 * @param ids An array of IDs of the tokens to be burned.
	 * @param amounts An array of amounts of tokens to be burned.
	 */
	function burnBatch(uint256[] calldata ids, uint256[] calldata amounts) external virtual onlyRole(BURNER_ROLE) {
		_requireHasAccess(_msgSender(), true);
		_burnBatch(_msgSender(), ids, amounts);
	}

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
	 * @notice This is a function used to transfer tokens on behalf of the `from` address to
	 * the `to` address.
	 *
	 * This function emits an {Approval} event as part of {ERC1155Upgradeable._approve}.
	 * This function emits a {TransferSingle} event as part of {ERC1155Upgradeable._safeTransferFrom}.
	 *
	 * @dev Calling Conditions:
	 *
	 * - {ERC1155F} is not paused. (checked internally by {_beforeTokenTransfer})
	 * - The `from` is allowed to send the token.
	 * - The `to` is allowed to receive the token.
	 * - `from` is a non-zero address. (checked internally by {ERC1155Upgradeable}.{_safeTransferFrom})
	 * - `to` is a non-zero address. (checked internally by {ERC1155Upgradeable}.{_safeTransferFrom})
	 * - `amount` is not greater than `from`'s balance or caller's allowance of `from`'s funds. (checked internally
	 *   by {ERC1155Upgradeable}.{safeTransferFrom})
	 *
	 * @param from The address that tokens will be transferred on behalf of.
	 * @param to The address that will receive the tokens.
	 * @param id The ID of the token to be transferred.
	 * @param amount The amount of tokens to be transferred.
	 * @param data Additional data with no specified format, sent in call to `_safeTransferFrom`.
	 */
	function safeTransferFrom(
		address from,
		address to,
		uint256 id,
		uint256 amount,
		bytes memory data
	) public virtual override {
		_requireHasAccess(from, true);
		_requireHasAccess(to, false);
		super.safeTransferFrom(from, to, id, amount, data);
	}

	/**
	 * @notice This is a function used to transfer a batch tokens on behalf of the `from` address to
	 * the `to` address.
	 *
	 * This function emits an {Approval} event as part of {ERC1155Upgradeable._approve}.
	 * This function emits a {TransferBatch} event as part of {ERC1155Upgradeable._safeBatchTransferFrom}.
	 *
	 * @dev Calling Conditions:
	 *
	 * - {ERC1155F} is not paused. (checked internally by {_beforeTokenTransfer})
	 * - The `from` is allowed to send the token.
	 * - The `to` is allowed to receive the token.
	 * - `from` is a non-zero address. (checked internally by {ERC1155Upgradeable}.{_safeBatchTransferFrom})
	 * - `to` is a non-zero address. (checked internally by {ERC1155Upgradeable}.{_safeBatchTransferFrom})
	 * - `amount` is not greater than `from`'s balance or caller's allowance of `from`'s funds. (checked internally
	 *   by {ERC1155Upgradeable}.{safeTransferFrom})
	 *
	 * @param from The address that tokens will be transferred on behalf of.
	 * @param to The address that will receive the tokens.
	 * @param ids An array of IDs of the tokens to be transferred.
	 * @param amounts An array of amounts of the tokens to be transferred.
	 * @param data Additional data with no specified format, sent in call to `_safeBatchTransferFrom`.
	 */
	function safeBatchTransferFrom(
		address from,
		address to,
		uint256[] memory ids,
		uint256[] memory amounts,
		bytes memory data
	) public virtual override {
		_requireHasAccess(from, true);
		_requireHasAccess(to, false);
		super.safeBatchTransferFrom(from, to, ids, amounts, data);
	}

	/**
	 * @notice This function allows the owner of some ERC1155 tokens to authorize another address to operate all
	 * of those tokens. The `operator` parameter is the address that is being authorized to operate the tokens.
	 *
	 * @dev Calling Conditions:
	 *
	 * - {ERC1155F} is not paused.
	 *
	 * Upon successful execution function emits an {ApprovalForAll} event as part of
	 * {ERC1155Upgradeable._setApprovalForAll}.
	 *
	 * @param operator The address getting an allowance.
	 * @param approved The boolean value indicating whether the `operator` is being authorized or not.
	 */
	function setApprovalForAll(address operator, bool approved) public virtual override whenNotPaused {
		super.setApprovalForAll(operator, approved);
	}

	/**
	 * @notice This function returns the URI associated with a given token.
	 *
	 * @dev This function is an override of the {ERC1155Upgradeable.uri} function.
	 * Calling Conditions:
	 *
	 * - `id` must exist.
	 *
	 * @param id The ID of the token whose URI is to be returned.
	 * @return The URI associated with the given `id`.
	 */
	function uri(uint256 id) public view virtual override returns (string memory) {
		if (totalSupply(id) == 0) revert LibErrors.InvalidTokenId();
		return _tokenUri[id];
	}

	/**
	 * @notice This is a function used to check if an interface is supported by this contract.
	 * @dev This function returns `true` if the interface is supported, otherwise it returns `false`.
	 * @return `true` if the interface is supported, otherwise it returns `false`.
	 */
	function supportsInterface(
		bytes4 interfaceId
	) public view virtual override(ERC1155Upgradeable, AccessControlUpgradeable) returns (bool) {
		return
			interfaceId == type(IERC1967Upgradeable).interfaceId ||
			interfaceId == type(IERC1822ProxiableUpgradeable).interfaceId ||
			super.supportsInterface(interfaceId);
	}

	/**
	 * @notice This function works as a middle layer and performs some checks before
	 * it allows a transfer to operate.
	 *
	 * @dev A hook inherited from ERC1155Upgradeable.
	 *
	 * This function performs the following checks, and reverts when not met:
	 *
	 * - {ERC1155F} is not paused.
	 *
	 * @param operator The address that is performing the transfer.
	 * @param from The address that sent the tokens.
	 * @param to The address that receives the transfer `ids`.
	 * @param ids An array of token IDs to be transferred.
	 * @param amounts An array of amounts of tokens to be transferred.
	 * @param data Additional data with no specified format.
	 */
	function _beforeTokenTransfer(
		address operator,
		address from,
		address to,
		uint256[] memory ids,
		uint256[] memory amounts,
		bytes memory data
	) internal virtual override(ERC1155Upgradeable, ERC1155SupplyUpgradeable) whenNotPaused {
		super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
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
	 * @notice This is a function that applies any validations required to allow salvage operations (like salvageERC20).
	 *
	 * @dev Reverts when the caller does not have the "SALVAGE_ROLE".
	 *
	 * Calling Conditions:
	 *
	 * - Only the "SALVAGE_ROLE" can execute.
	 * - {ERC1155F} is not paused.
	 */
	/* solhint-disable no-empty-blocks */
	function _authorizeSalvageERC20() internal virtual override whenNotPaused onlyRole(SALVAGE_ROLE) {}

	/**
	 * @notice This is a function that applies any validations required to allow salvage operations (like salvageGas).
	 *
	 * @dev Reverts when the caller does not have the "SALVAGE_ROLE".
	 *
	 * Calling Conditions:
	 *
	 * - Only the "SALVAGE_ROLE" can execute.
	 * - {ERC1155F} is not paused.
	 */
	/* solhint-disable no-empty-blocks */
	function _authorizeSalvageGas() internal virtual override whenNotPaused onlyRole(SALVAGE_ROLE) {}

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
	 * @notice This is a function that applies any validations required to allow Contract Uri updates.
	 *
	 * @dev Reverts when the caller does not have the "CONTRACT_ADMIN_ROLE".
	 *
	 * Calling Conditions:
	 *
	 * - Only the "CONTRACT_ADMIN_ROLE" can execute.
	 * - {ERC1155F} is not paused.
	 */
	/* solhint-disable no-empty-blocks */
	function _authorizeContractUriUpdate() internal virtual override whenNotPaused onlyRole(CONTRACT_ADMIN_ROLE) {}

	/**
	 * @notice This is a function that applies any validations required to allow Token Uri updates.
	 *
	 * @dev Reverts when the caller does not have the "CONTRACT_ADMIN_ROLE".
	 *
	 * Calling Conditions:
	 *
	 * - Only the "CONTRACT_ADMIN_ROLE" can execute.
	 * - {ERC1155F} is not paused.
	 */
	/* solhint-disable no-empty-blocks */
	function _authorizeTokenUriUpdate() internal virtual override whenNotPaused onlyRole(CONTRACT_ADMIN_ROLE) {}

	/**
	 * @notice This is a function that applies any validations required to allow Access Registry updates.
	 *
	 * @dev Reverts when the caller does not have the "CONTRACT_ADMIN_ROLE".
	 *
	 * Calling Conditions:
	 *
	 * - Only the "CONTRACT_ADMIN_ROLE" can execute.
	 * - {ERC1155F} is not paused.
	 */
	/* solhint-disable no-empty-blocks */
	function _authorizeAccessRegistryUpdate() internal virtual override whenNotPaused onlyRole(CONTRACT_ADMIN_ROLE) {}

	/**
	 * @notice This is a function that applies any validations required to allow Role Access operation (like grantRole or revokeRole ) to be executed.
	 *
	 * @dev Reverts when the {ERC1155F} contract is paused.
	 *
	 * Calling Conditions:
	 *
	 * - {ERC1155F} is not paused.
	 */
	/* solhint-disable no-empty-blocks */
	function _authorizeRoleAccess() internal virtual override whenNotPaused {}

	/**
	 * @notice This is a function that applies any validations required to allow Marketplace Operator updates.
	 *
	 * @dev Reverts when the caller does not have the "CONTRACT_ADMIN_ROLE".
	 *
	 * Calling Conditions:
	 *
	 * - Only the "CONTRACT_ADMIN_ROLE" can execute.
	 * - {ERC1155F} is not paused.
	 */
	function _authorizeMarketplaceOperatorUpdate()
		internal
		virtual
		override
		whenNotPaused
		onlyRole(CONTRACT_ADMIN_ROLE)
	{}

	/**
	 * @notice This function checks that an account can have access to this token.
	 * The function will revert if the account does not have access.
	 *
	 * @param account The address to check has access.
	 * @param isSender Value indicating if the sender or receiver is being checked.
	 */
	function _requireHasAccess(address account, bool isSender) internal view virtual {
		if (address(accessRegistry) != address(0)) {
			if (!accessRegistry.hasAccess(account, _msgSender(), _msgData())) {
				if (isSender) {
					revert ERC1155InvalidSender(account);
				} else {
					revert ERC1155InvalidReceiver(account);
				}
			}
		}
	}
}
