// SPDX-License-Identifier: CC0-1.0
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {INeuMetadataV3} from "../interfaces/INeuMetadataV3.sol";
import {INeuV3} from "../interfaces/INeuV3.sol";
import {INeuDaoLockV1} from "../interfaces/ILockV1.sol";
import {IERC7496} from "../interfaces/IERC7496.sol";

/**
 * @title NeuV3
 * @notice ERC721 token contract for NEU tokens with upgradeable features, supporting royalties, and access control.
 * @dev Inherits from multiple OpenZeppelin upgradeable contracts for ERC721 functionality, access control, and upgradeability.
 * Implements interfaces for metadata and DAO lock integration.
 * @custom:security-contact security@studiov.tech
 */
contract NeuV3 is
    INeuV3,
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    AccessControlUpgradeable,
    ERC721BurnableUpgradeable,
    ERC721RoyaltyUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint256 private constant _VERSION = 3;
    bytes32 private constant _POINTS_TRAIT_KEY = keccak256("points");
    uint256 private constant _GWEI = 1e9;
    uint96 private constant _ROYALTY_BASE_POINTS = 1000; // 10%
    uint256 private constant _ENTITLEMENT_COOLDOWN_SECONDS = 1 weeks;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 public weiPerSponsorPoint;
    INeuMetadataV3 private _neuMetadata;
    INeuDaoLockV1 private _neuDaoLock;

    mapping(uint256 => uint256) public entitlementAfterTimestamps;

    /**
     * @notice Disables initializers to prevent implementation contract from being initialized.
     * @dev This constructor is only used to disable initializers for the implementation contract. Standard practice for upgradeable contracts.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the NEU token contract with roles and default settings.
     * @dev Sets up ERC721, AccessControl, and other initial configurations. Grants roles to specified addresses.
     * @param defaultAdmin The address to be granted DEFAULT_ADMIN_ROLE.
     * @param upgrader The address to be granted UPGRADER_ROLE.
     * @param operator The address to be granted OPERATOR_ROLE.
     *
     * Emits {InitializedNeu} event with version and role addresses.
     */
    function initialize(
        address defaultAdmin,
        address upgrader,
        address operator
    ) public initializer {
        __ERC721_init("Neulock", "NEU");
        __ERC721Enumerable_init();
        __AccessControl_init();
        __ERC721Burnable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, upgrader);
        _grantRole(OPERATOR_ROLE, operator);

        _setDefaultRoyalty(address(this), 1000); // 10%

        weiPerSponsorPoint = 1e14; // 0.0001 ETH

        emit InitializedNeu(_VERSION, defaultAdmin, upgrader, operator);
    }

    /**
     * @notice Initializes the V2 version of the NEU token contract, adding DAO lock functionality.
     * @dev Reinitializes the contract to include NeuDaoLockV1 integration.
     * @param neuDaoLockAddress The address of the NeuDaoLockV1 contract.
     *
     * Emits {InitializedNeuV2} event with the DAO lock address.
     *
     * Requirements:
     * - Caller must have UPGRADER_ROLE.
     */
    function initializeV2(address payable neuDaoLockAddress) public reinitializer(2) onlyRole(UPGRADER_ROLE) {
        __ReentrancyGuard_init();

        _neuDaoLock = INeuDaoLockV1(neuDaoLockAddress);

        emit InitializedNeuV2(neuDaoLockAddress);
    }

    /**
     * @notice Initializes the V3 version of the NEU token contract, adding royalty and metadata functionality.
     * @dev Reinitializes the contract to include ERC721Royalty, metadata, and updated DAO lock integration.
     * @param royaltyReceiver The address to receive royalty payments.
     * @param metadataAddress The address of the NeuMetadataV3 contract for metadata management.
     * @param lockV2Address The address of the NeuDaoLockV2 contract for updated DAO locking functionality.
     * @param traitMetadataUri The URI for trait metadata.
     *
     * Emits {MetadataContractUpdated} event with the metadata contract address.
     *
     * Requirements:
     * - Caller must have UPGRADER_ROLE.
     */
    function initializeV3(
        address payable royaltyReceiver,
        address metadataAddress,
        address payable lockV2Address,
        string calldata traitMetadataUri
    ) public reinitializer(3) onlyRole(UPGRADER_ROLE) {
        __ERC721Royalty_init();

        _neuMetadata = INeuMetadataV3(metadataAddress);
        _setDefaultRoyalty(royaltyReceiver, _ROYALTY_BASE_POINTS);
        _neuDaoLock = INeuDaoLockV1(lockV2Address);

        emit MetadataContractUpdated(metadataAddress);
        emit RoyaltyReceiverUpdated(royaltyReceiver);
        emit DaoLockContractUpdated(lockV2Address);
        emit InitializedNeuV3(royaltyReceiver, metadataAddress, lockV2Address);

        _setTraitMetadataURI(traitMetadataUri);

        // slither-disable-next-line unused-return (we expect a revert)
        try _neuMetadata.sumAllRefundableTokensValue() returns (uint256) {
            revert("Upgrade Metadata to V3 first");
        } catch {
            // Do nothing
        }
   }

    /**
     * @notice Retrieves the URI for trait metadata from the NeuMetadataV3 contract.
     * @dev Delegates the call to the `_neuMetadata` contract.
     * @return uri The trait metadata URI.
     */
    function getTraitMetadataURI() external view override returns (string memory uri) {
        return _neuMetadata.getTraitMetadataURI();
    }

    /**
     * @notice Sets the URI for trait metadata in the NeuMetadataV3 contract.
     * @dev Emits an event and delegates the call to the `_neuMetadata` contract.
     * @param uri The new URI for trait metadata.
     *
     * Emits {TraitMetadataURIUpdated} event.
     */
    function _setTraitMetadataURI(string calldata uri) private {
        emit TraitMetadataURIUpdated();
        _neuMetadata.setTraitMetadataURI(uri);
    }

    /**
     * @notice Returns the token URI for a given token ID, containing its metadata.
     * @dev Attempts to retrieve the token URI from the `_neuMetadata` contract. Returns an empty string if the call fails.
     * @param tokenId The ID of the token.
     * @return The token URI string.
     *
     * Requirements:
     * - The caller must own the token.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        // slither-disable-start calls-loop (try-catch mitigates the DoS risk on revert)
        try _neuMetadata.tokenURI(tokenId) returns (string memory result) {
            return result;
        } catch {
            return "";
        }
        // slither-disable-end calls-loop
    }

    /**
     * @notice Reverts if called, as the metadata contract is already set.
     * @dev This function is intended to prevent changes to the metadata contract address.
     */
    function setMetadataContract(address) external view onlyRole(OPERATOR_ROLE) {
        revert("Metadata contract already set");
    }

    /**
     * @notice Sets the address of the NeuDaoLockV1 contract for DAO locking functionality.
     * @dev Only callable by an account with OPERATOR_ROLE.
     * @param newDaoLockContract The address of the new NeuDaoLockV1 contract.
     *
     * Emits {DaoLockContractUpdated} event with the new contract address.
     */
    function setDaoLockContract(address payable newDaoLockContract) external onlyRole(OPERATOR_ROLE) {
        _neuDaoLock = INeuDaoLockV1(newDaoLockContract);
        
        emit DaoLockContractUpdated(newDaoLockContract);
    }

    /**
     * @notice Reverts if called, as the storage contract functionality is deprecated.
     * @dev This function is intended to prevent changes to the storage contract address.
     */
    function setStorageContract(address) external pure {
        revert Deprecated();
    }

    /**
     * @notice Mints a new token privately with specified series index and original price.
     * @dev Calls the NeuMetadataV3 contract to create token metadata and safely mints the token.
     * @param to The address to mint the token to.
     * @param seriesIndex The index of the series to mint from.
     * @param originalPrice The original price of the token in Wei.
     */
    function _privateMint(
        address to,
        uint16 seriesIndex,
        uint256 originalPrice
    ) private {
        uint256 tokenId = _neuMetadata.createTokenMetadataV3(seriesIndex, originalPrice);

        _safeMint(to, tokenId);
    }

    /**
     * @notice Mints a new token to a specified address with zero original price.
     * @dev Only callable by an account with OPERATOR_ROLE. Uses `_privateMint` for minting.
     * @param to The address to mint the token to.
     * @param seriesIndex The index of the series to mint from.
     */
    function safeMint(address to, uint16 seriesIndex) public override onlyRole(OPERATOR_ROLE) {
        _privateMint(to, seriesIndex, 0);
    }

    /**
     * @notice Mints a new token to the caller, requiring ETH payment for the series price.
     * @dev Checks that the sent ETH covers the series price and uses `_privateMint` for minting.
     * @param seriesIndex The index of the series to mint from.
     *
     * Requirements:
     * - `msg.value` must be greater than or equal to the series price.
     */
    function safeMintPublic(uint16 seriesIndex) external payable {
        uint256 seriesPrice = _neuMetadata.getSeriesMintingPrice(seriesIndex);

        require(msg.value >= seriesPrice, "Not enough ETH sent");
        _privateMint(msg.sender, seriesIndex, seriesPrice);
    }

    /**
     * @notice Burns a token and deletes its metadata.
     * @dev Calls the NeuMetadataV3 contract to delete token metadata after burning.
     * @param tokenId The ID of the token to burn.
     */
    function burn(uint256 tokenId) public override {
        super.burn(tokenId);
        _neuMetadata.deleteTokenMetadata(tokenId);
    }

    /**
     * @notice Withdraws the contract's balance to the caller.
     * @dev Only callable by an account with OPERATOR_ROLE.
     */
    function withdraw() external onlyRole(OPERATOR_ROLE) {
        uint256 availableBalance = address(this).balance;

        if (availableBalance > 0) {
            // slither-disable-next-line arbitrary-send-eth (msg.sender is operator, guaranteed by onlyRole check)
            payable(msg.sender).transfer(availableBalance);
        }
    }

    /**
     * @notice Reverts if called, as the refund functionality is deprecated.
     * @dev This function is intended to prevent refund operations.
     */
    function refund(uint256) external pure {
        revert("Refund deprecated on NeuV3");
    }

    /**
     * @notice Increases the sponsor points for a specific token by sending ETH.
     * @dev Sends ETH to the DAO lock contract and updates sponsor points in the metadata.
     * @param tokenId The ID of the token to update.
     * @return newSponsorPoints The new sponsor points value after the increase.
     * @return sponsorPointsIncrease The amount by which sponsor points were increased.
     *
     * Requirements:
     * - The caller must own the token.
     */
    function increaseSponsorPoints(uint256 tokenId) external payable returns (uint256 newSponsorPoints, uint256 sponsorPointsIncrease) {
        _requireOwned(tokenId);

        (newSponsorPoints, sponsorPointsIncrease) = _increaseSponsorPoints(tokenId, msg.value);

        // slither-disable-next-line low-level-calls (calling like this is the best practice for sending Ether)
        (bool sent, ) = address(_neuDaoLock).call{value: msg.value}("");
        require(sent, "Failed to send Ether");
    }

    /**
     * @notice Internal function to increase sponsor points for a token based on ETH sent.
     * @dev Calculates sponsor points increase and updates metadata.
     * @param tokenId The ID of the token to update.
     * @param value The amount of ETH sent.
     * @return newSponsorPoints The new sponsor points value after the increase.
     * @return sponsorPointsIncrease The amount by which sponsor points were increased.
     */
    function _increaseSponsorPoints(uint256 tokenId, uint256 value) private nonReentrant() returns (uint256 newSponsorPoints, uint256 sponsorPointsIncrease) {
        sponsorPointsIncrease = value / weiPerSponsorPoint;

        if (sponsorPointsIncrease == 0) {
            revert("Not enough ETH sent");
        }

        newSponsorPoints = _neuMetadata.increaseSponsorPoints(tokenId, sponsorPointsIncrease);

        emit TraitUpdated(_POINTS_TRAIT_KEY, tokenId, bytes32(newSponsorPoints));
    }

    /**
     * @notice Sets the amount of Wei required to increase sponsor points by one.
     * @dev Only callable by an account with OPERATOR_ROLE.
     * @param newWeiPerSponsorPoint The new amount of Wei per sponsor point.
     *
     * Emits {WeiPerSponsorPointUpdated} event with the new value.
     *
     * Requirements:
     * - `newWeiPerSponsorPoint` must be at least 1 Gwei.
     */
    function setWeiPerSponsorPoint(uint256 newWeiPerSponsorPoint) external onlyRole(OPERATOR_ROLE) {
        require(newWeiPerSponsorPoint >= _GWEI, "Must be at least 1 gwei");
        weiPerSponsorPoint = newWeiPerSponsorPoint;

        emit WeiPerSponsorPointUpdated(newWeiPerSponsorPoint);
    }

    /**
     * @notice Reverts if called, as setting individual traits is not allowed.
     * @dev This function is intended to prevent individual trait updates.
     */
    function setTrait(
        uint256 /*tokenId*/,
        bytes32 /*traitKey*/,
        bytes32 /*newValue*/
    ) pure public {
        revert TraitValueUnchanged();
    }

    /**
     * @notice Retrieves the value of a specific trait for a token.
     * @dev Delegates the call to the NeuMetadataV3 contract.
     * @param tokenId The ID of the token.
     * @param traitKey The key of the trait to retrieve.
     * @return traitValue The value of the trait.
     *
     * Requirements:
     * - The caller must own the token.
     */
    function getTraitValue(
        uint256 tokenId,
        bytes32 traitKey
    ) public view returns (bytes32 traitValue) {
        _requireOwned(tokenId);

        return _neuMetadata.getTraitValue(tokenId, traitKey);
    }

    /**
     * @notice Retrieves the values of multiple traits for a token.
     * @dev Delegates the call to the NeuMetadataV3 contract.
     * @param tokenId The ID of the token.
     * @param traitKeys An array of trait keys to retrieve.
     * @return traitValues An array of corresponding trait values.
     *
     * Requirements:
     * - The caller must own the token.
     */
    function getTraitValues(
        uint256 tokenId,
        bytes32[] calldata traitKeys
    ) public view virtual override returns (bytes32[] memory traitValues) {
        _requireOwned(tokenId);

        // slither-disable-next-line calls-loop (an unexpected revert here indicates a bug in our NeuMetadata contract that we would need to fix)
        return _neuMetadata.getTraitValues(tokenId, traitKeys);
    }

    /**
     * @notice Sets the URI for trait metadata in the NeuMetadataV3 contract.
     * @dev Only callable by an account with OPERATOR_ROLE. Delegates the call to `_setTraitMetadataURI`.
     * @param uri The new URI for trait metadata.
     */
    function setTraitMetadataURI(
        string calldata uri
    ) external onlyRole(OPERATOR_ROLE) {
        _setTraitMetadataURI(uri);
    }

    /**
     * @notice Retrieves the token IDs owned by a specific address.
     * @dev Iterates through the owner's tokens and constructs an array of token IDs.
     * @param owner The address of the token owner.
     * @return tokenIds An array of token IDs owned by the specified address.
     */
    function getTokensOfOwner(address owner) public view returns (uint256[] memory tokenIds) {
        uint256 tokenCount = balanceOf(owner);

        tokenIds = new uint256[](tokenCount);

        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
    }

    /**
     * @notice Retrieves token URIs and user mint status for a list of token IDs.
     * @dev Iterates through the token IDs and retrieves their URIs and mint status from the NeuMetadataV3 contract.
     * @param tokenIds An array of token IDs to query.
     * @return tokenUris An array of token URIs.
     * @return isUserMinted An array indicating if each token was user-minted.
     */
    function getTokensWithData(uint256[] calldata tokenIds) external view returns (string[] memory tokenUris, bool[] memory isUserMinted) {
        tokenUris = new string[](tokenIds.length);
        isUserMinted = new bool[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenUris[i] = tokenURI(tokenIds[i]);
            // slither-disable-next-line calls-loop (will only revert if there's a bug in our NeuMetadata contract; we don't want to fail silently)
            isUserMinted[i] = _neuMetadata.isUserMinted(tokenIds[i]);
        }
    }

    /**
     * @notice Retrieves trait values for a list of token IDs and trait keys.
     * @dev Iterates through the token IDs and retrieves their trait values from the NeuMetadataV3 contract.
     * @param tokenIds An array of token IDs to query.
     * @param traitKeys An array of trait keys to retrieve for each token.
     * @return traitValues A 2D array of trait values for each token and trait key.
     */
    function getTokensTraitValues(uint256[] calldata tokenIds, bytes32[] calldata traitKeys) external view returns (bytes32[][] memory traitValues) {
        traitValues = new bytes32[][](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            traitValues[i] = getTraitValues(tokenIds[i], traitKeys);
        }
    }

    /**
     * @notice Checks if a token is part of a governance series.
     * @dev Delegates the call to the NeuMetadataV3 contract.
     * @param tokenId The ID of the token to check.
     * @return True if the token belongs to a governance series, false otherwise.
     *
     * Requirements:
     * - The caller must own the token.
     */
    function isGovernanceToken(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);

        return _neuMetadata.isGovernanceToken(tokenId);
    }

    /**
     * @notice Sets the address of the royalty receiver for the contract.
     * @dev Only callable by an account with OPERATOR_ROLE. Updates the default royalty receiver.
     * @param royaltyReceiver The address to receive royalty payments.
     *
     * Emits {RoyaltyReceiverUpdated} event with the new address.
     */
    function setRoyaltyReceiver(address royaltyReceiver) external onlyRole(OPERATOR_ROLE) {
        _setDefaultRoyalty(royaltyReceiver, _ROYALTY_BASE_POINTS);

        emit RoyaltyReceiverUpdated(royaltyReceiver);
    }

    /**
     * @notice Sets the entitlement date for a token based on transfer conditions.
     * @dev Updates the entitlement timestamp with a cooldown period.
     * @param tokenId The ID of the token to update.
     */
    function _setEntitlementDate(uint256 tokenId) internal {
        // slither-disable-next-line block-timestamp (with a granularity of days for the entitlement cooldown, we can tolerate miner manipulation)
        uint256 blockTimestamp = block.timestamp;

        if (blockTimestamp >= entitlementAfterTimestamps[tokenId] + _ENTITLEMENT_COOLDOWN_SECONDS) {
            // Token transferred for the first time or entitlement active for more than a week.
            // Give entitlement to new owner.
            // Add 1 second to disallow flashloans even if token has not been transferred for more than a week
            entitlementAfterTimestamps[tokenId] = blockTimestamp + 1;
            emit EntitlementTimestampSet(tokenId, entitlementAfterTimestamps[tokenId]);
        } else if (blockTimestamp >= entitlementAfterTimestamps[tokenId]) {
            // Entitlement active for less than a week.
            // New owner will get entitlement a week after entitlement last started.
            entitlementAfterTimestamps[tokenId] += _ENTITLEMENT_COOLDOWN_SECONDS;
            emit EntitlementTimestampSet(tokenId, entitlementAfterTimestamps[tokenId]);
        }
        // In cooldown period. Don't change it.
    }

    /**
     * @notice Updates the token's ownership and handles entitlement date adjustments.
     * @dev Overrides the `_update` function from ERC721 and ERC721Enumerable.
     * @param to The new owner of the token.
     * @param tokenId The ID of the token to update.
     * @param auth The authorized address for the update.
     * @return The previous owner of the token.
     */
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) returns (address) {
        address from = super._update(to, tokenId, auth);

        if (to == address(0)) {
            delete entitlementAfterTimestamps[tokenId];
            emit EntitlementTimestampSet(tokenId, 0);
        } else if (from != address(0)) {
            // Leave entitlement date as 0 for mints, to allow mint + transfer (gifting) with immediate entitlement
            _setEntitlementDate(tokenId);
        }

        return from;
    }

    /**
     * @notice Increases the balance of an account by a specified value.
     * @dev Overrides the `_increaseBalance` function from ERC721 and ERC721Enumerable.
     * @param account The account whose balance is to be increased.
     * @param value The value to add to the account's balance.
     */
    function _increaseBalance(address account, uint128 value) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._increaseBalance(account, value);
    }

    /**
     * @notice Checks if the contract supports a specific interface.
     * @dev Overrides the `supportsInterface` function from multiple inherited contracts.
     * @param interfaceId The interface identifier to check.
     * @return True if the interface is supported, false otherwise.
     */
    function supportsInterface(bytes4 interfaceId) public view override(
            AccessControlUpgradeable,
            ERC721EnumerableUpgradeable,
            ERC721RoyaltyUpgradeable,
            ERC721Upgradeable
        ) returns (bool)
    {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(IERC7496).interfaceId;
    }

    /**
     * @notice Authorizes contract upgrades.
     * @dev Only callable by an account with UPGRADER_ROLE.
     * @param newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}