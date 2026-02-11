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

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC1822ProxiableUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/draft-IERC1822Upgradeable.sol";
import {IERC1967Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC1967Upgradeable.sol";
import {IERC721Errors} from "./library/Errors/interface/IERC721Errors.sol";

import {LibErrors} from "./library/Errors/LibErrors.sol";
import {AccessRegistrySubscriptionUpgradeable} from "./library/AccessRegistry/AccessRegistrySubscriptionUpgradeable.sol";
import {ContractUriUpgradeable} from "./library/Utils/ContractUriUpgradeable.sol";
import {SalvageUpgradeable} from "./library/Utils/SalvageUpgradeable.sol";
import {PauseUpgradeable} from "./library/Utils/PauseUpgradeable.sol";
import {RoleAccessUpgradeable} from "./library/Utils/RoleAccessUpgradeable.sol";
import {TokenUriUpgradeable} from "./library/Utils/TokenUriUpgradeable.sol";
import {MarketplaceOperatorUpgradeable} from "./library/Utils/MarketplaceOperatorUpgradeable.sol";

/**
 * @title ERC721F
 * @author Fireblocks
 * @notice This contract represents a non-fungible token within the Fireblocks ecosystem of contracts.
 *
 * The contract utilizes the UUPS (Universal Upgradeable Proxy Standard) for seamless upgradability. This standard
 * enables the contract to be easily upgraded without disrupting its state. By following the UUPS proxy pattern, the
 * ERC721F logic is separated from the storage, allowing upgrades while preserving the existing data. This
 * approach ensures that the contract can adapt and evolve over time, incorporating improvements and new features and
 * mitigating potential attack vectors in future.
 *
 * The ERC721F contract Role Based Access Control employs following roles:
 *
 *  - UPGRADER_ROLE
 *  - PAUSER_ROLE
 *  - CONTRACT_ADMIN_ROLE
 *  - MINTER_ROLE
 *  - BURNER_ROLE
 *  - RECOVERY_ROLE
 *  - SALVAGE_ROLE
 *
 * The ERC721F Token contract can utilize an Access Registry contract to retrieve information on whether an account
 * is authorized to interact with the system.
 */
contract ERC721F is
	Initializable,
	ERC721Upgradeable,
	AccessRegistrySubscriptionUpgradeable,
	MulticallUpgradeable,
	SalvageUpgradeable,
	ContractUriUpgradeable,
	TokenUriUpgradeable,
	PauseUpgradeable,
	RoleAccessUpgradeable,
	MarketplaceOperatorUpgradeable,
	IERC721Errors,
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

	/// Events

	/**
	 * @notice This event is logged when the tokens are recovered from an address that is not allowed
	 * to participate in the system.
	 *
	 * @param caller The (indexed) address of the caller.
	 * @param account The (indexed) account the tokens were recovered from.
	 * @param tokenId The (indexed) ID of the token that was recovered.
	 */
	event TokensRecovered(address indexed caller, address indexed account, uint256 indexed tokenId);

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
	 * @notice This function configures the ERC721F contract with the initial state and granting
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
		__ERC721_init(_name, _symbol);
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
	}

	/**
	 * @notice This is a function used to issue new ERC721 token.
	 * The caller will issue a token to the `to` address.
	 *
	 * @dev Calling Conditions:
	 *
	 * - Can only be invoked by the address that has the role "MINTER_ROLE".
	 * - {ERC721F} is not paused. (checked internally by {_beforeTokenTransfer})
	 * - `to` is a non-zero address. (checked internally by {ERC721Upgradeable}.{_mint})
	 * - `to` is allowed to receive tokens.
	 *
	 * This function emits a {Transfer} event as part of {ERC721Upgradeable._mint}.
	 * This function emits a {TokenUriUpdated} event as part of {TokenUriUpgradeable._tokenUriUpdate}.
	 *
	 * @param to The address that will receive the issued token.
	 * @param tokenId The ID of the token to be issued.
	 * @param uri A URI link pointing to the current URI associated with the token.
	 */
	function mint(address to, uint256 tokenId, string calldata uri) external virtual onlyRole(MINTER_ROLE) {
		_requireHasAccess(to, false);
		_tokenUriUpdate(tokenId, uri);
		_safeMint(to, tokenId);
	}

	/**
	 * @notice This is a function used to burn an ERC721 token.
	 * The caller can burn an ERC721 token from their own address or from an address they have approval.
	 *
	 * @dev Calling Conditions:
	 *
	 * - Can only be invoked by the address that has the role "BURNER_ROLE".
	 * - {ERC721F} is not paused. (checked internally by {_beforeTokenTransfer})
	 * - `caller` is allowed to hold tokens.
	 *
	 * This function emits a {Transfer} event as part of {ERC721Upgradeable._burn}.
	 *
	 * @param tokenId The ID of the token to be burned.
	 */
	function burn(uint256 tokenId) external virtual onlyRole(BURNER_ROLE) {
		_requireHasAccess(_msgSender(), true);
		if (!_isApprovedOrOwner(_msgSender(), tokenId)) {
			revert LibErrors.UnauthorizedTokenManagement();
		}
		_burn(tokenId);
	}

	/**
	 * @notice This is a function used to recover an ERC721 token from an address not on the Allowlist.
	 *
	 * @dev Calling Conditions:
	 *
	 * - `caller` of this function must have the "RECOVERY_ROLE".
	 * - {ERC721F} is not paused.(checked internally by {_beforeTokenTransfer}).
	 * - `accessRegistry` must be set.
	 * - `account` address must be not be allowed to hold tokens.
	 * - `account` must be a non-zero address. (checked internally in {ERC721Upgradeable._transfer})
	 *
	 * This function emits a {TokensRecovered} event, signalling that the token of the given address were recovered.
	 *
	 * @param account The address to recover the token from.
	 * @param tokenId The ID of the token to be recovered.
	 */
	function recoverTokens(address account, uint256 tokenId) external virtual onlyRole(RECOVERY_ROLE) {
		if (address(accessRegistry) == address(0)) revert LibErrors.AccessRegistryNotSet();
		if (accessRegistry.hasAccess(account, _msgSender(), _msgData())) revert LibErrors.RecoveryOnActiveAccount(account);
		emit TokensRecovered(_msgSender(), account, tokenId);
		_transfer(account, _msgSender(), tokenId);
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
	 * This function emits an {Approval} event as part of {ERC721Upgradeable._approve}.
	 * This function emits a {Transfer} event as part of {ERC721Upgradeable._transfer}.
	 *
	 * @dev Calling Conditions:
	 *
	 * - {ERC721F} is not paused. (checked internally by {_beforeTokenTransfer})
	 * - The `from` is allowed to send the token.
	 * - The `to` is allowed to receive the token.
	 * - `from` is a non-zero address. (checked internally by {ERC721Upgradeable}.{_transfer})
	 * - `to` is a non-zero address. (checked internally by {ERC721Upgradeable}.{_transfer})
	 *
	 * @param from The address that tokens will be transferred on behalf of.
	 * @param to The address that will receive the tokens.
	 * @param tokenId The ID of the token to be transferred.
	 */
	function transferFrom(address from, address to, uint256 tokenId) public virtual override {
		_requireHasAccess(from, true);
		_requireHasAccess(to, false);
		super.transferFrom(from, to, tokenId);
	}

	/**
	 * @notice This is a function used to transfer tokens safely on behalf of the `from` address to
	 * the `to` address.
	 *
	 * @dev Safely transfers `tokenId` token from `from` to `to`.
	 *
	 * Calling Conditions:
	 *
	 * - `from` cannot be the zero address. (checked internally by {ERC721Upgradeable}.{_transfer})
	 * - `to` cannot be the zero address. (checked internally by {ERC721Upgradeable}.{_transfer})
	 * - `tokenId` token must exist and be owned by `from`. (checked internally by {ERC721Upgradeable}.{_transfer})
	 * - `from` has access to this token.
	 * - `to` has access to this token.
	 * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
	 * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
	 * a safe transfer.
	 *
	 * Emits a {Transfer} event as part of {ERC721Upgradeable._transfer}.
	 *
	 * @param from The address that tokens will be transferred on behalf of.
	 * @param to The address that will receive the tokens.
	 * @param tokenId The ID of the token to be transferred.
	 * @param data Additional data with no specified format, sent in call to `to`.
	 */
	function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual override {
		_requireHasAccess(from, true);
		_requireHasAccess(to, false);
		super.safeTransferFrom(from, to, tokenId, data);
	}

	/**
	 * @notice This function allows the owner of a token to authorize another address to operate that token.
	 * The `spender` parameter is the address that is being authorized to operate the token and the `tokenId` parameter is
	 * the token that the `spender` is being authorized to operate.
	 *
	 * @dev Calling Conditions:
	 *
	 * - {ERC721F} is not paused.
	 * - The `spender` must be a non-zero address. (checked internally by {ERC721Upgradeable}.{_approve}).
	 *
	 * Upon successful execution function emits an {Approval} event as part of {ERC721Upgradeable._approve}.
	 *
	 * @param to The address getting an allowance.
	 * @param tokenId The ID of the token that the `spender` is being authorized to use.
	 */
	function approve(address to, uint256 tokenId) public virtual override whenNotPaused {
		super.approve(to, tokenId);
	}

	/**
	 * @notice This function allows the owner of some ERC721 tokens to authorize another address to operate all
	 * of those tokens. The `operator` parameter is the address that is being authorized to operate the tokens.
	 *
	 * @dev Calling Conditions:
	 *
	 * - {ERC721F} is not paused.
	 *
	 * Upon successful execution function emits an {ApprovalForAll} event as part of
	 * {ERC721Upgradeable._setApprovalForAll}.
	 *
	 * @param operator The address getting an allowance.
	 * @param approved The boolean value indicating whether the `operator` is being authorized or not.
	 */
	function setApprovalForAll(address operator, bool approved) public virtual override whenNotPaused {
		super.setApprovalForAll(operator, approved);
	}

	/**
	 * @notice This function returns the URI for a given token.
	 * @dev This function overrides the {ERC721Upgradeable-tokenURI} function.
	 * @param tokenId The token ID.
	 * @return The URI for the given token.
	 */
	function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
		_requireMinted(tokenId);
		return _tokenUri[tokenId];
	}

	/**
	 * @notice This is a function used to check if an interface is supported by this contract.
	 * @dev This function returns `true` if the interface is supported, otherwise it returns `false`.
	 * @return `true` if the interface is supported, otherwise it returns `false`.
	 */
	function supportsInterface(
		bytes4 interfaceId
	) public view virtual override(AccessControlUpgradeable, ERC721Upgradeable) returns (bool) {
		return
			interfaceId == type(IERC1967Upgradeable).interfaceId ||
			interfaceId == type(IERC1822ProxiableUpgradeable).interfaceId ||
			super.supportsInterface(interfaceId);
	}

	/**
	 * @notice This function works as a middle layer and performs some checks before
	 * it allows a transfer to operate.
	 *
	 * @dev A hook inherited from ERC721Upgradeable.
	 *
	 * This function performs the following checks, and reverts when not met:
	 *
	 * - {ERC721F} is not paused.
	 *
	 * @param from The address that sent the tokens.
	 * @param to The address that receives the transfer `tokenId`.
	 * @param tokenId The ID of the token to be transferred.
	 * @param batchSize The amount of tokens to be transferred.
	 */
	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 tokenId,
		uint256 batchSize
	) internal virtual override whenNotPaused {
		super._beforeTokenTransfer(from, to, tokenId, batchSize);
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
	 * - {ERC721F} is not paused.
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
	 * - {ERC721F} is not paused.
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
	 * - {ERC721F} is not paused.
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
	 * - {ERC721F} is not paused.
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
	 * - {ERC721F} is not paused.
	 */
	/* solhint-disable no-empty-blocks */
	function _authorizeAccessRegistryUpdate() internal virtual override whenNotPaused onlyRole(CONTRACT_ADMIN_ROLE) {}

	/**
	 * @notice This is a function that applies any validations required to allow Role Access operation (like grantRole or revokeRole ) to be executed.
	 *
	 * @dev Reverts when the {ERC721F} contract is paused.
	 *
	 * Calling Conditions:
	 *
	 * - {ERC721F} is not paused.
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
	 * - {ERC721F} is not paused.
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
					revert ERC721InvalidSender(account);
				} else {
					revert ERC721InvalidReceiver(account);
				}
			}
		}
	}
}
