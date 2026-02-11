// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import {Series, TokenMetadata, INeuMetadataV3} from "../interfaces/INeuMetadataV3.sol";
import {NeuLogoV2} from "./LogoV2.sol";
import {Bytes8Utils} from "../lib/Utils.sol";

using Bytes8Utils for bytes8;
using Strings for uint256;
using SafeCast for uint256;

/**
 * @title NeuMetadataV3
 * @author Lucas Neves (lneves.eth) for Studio V
 * @notice Manages metadata for NEU tokens, including series information, traits, and on-chain SVG generation.
 * @dev Upgradeable contract using OpenZeppelin's UUPS pattern. Handles token metadata, series management, trait storage, and integrates with NeuLogoV2 for SVG rendering. Version 3 introduces bitmap for available series and other V3 specific logic.
 * @custom:security-contact security@studiov.tech
 */
contract NeuMetadataV3 is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    INeuMetadataV3
{
    using BitMaps for BitMaps.BitMap;

    uint256 private constant _VERSION = 3;
    bytes32 private constant _POINTS_TRAIT_KEY = keccak256("points");
    uint256 private constant _REFUND_WINDOW = 7 days;

    /**
     * @notice Role identifier for the main NEU contract, authorized to manage token metadata.
     */
    bytes32 public constant NEU_ROLE = keccak256("NEU_ROLE");
    /**
     * @notice Role identifier for accounts authorized to upgrade the contract.
     */
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    /**
     * @notice Role identifier for accounts authorized to perform operational tasks like managing series.
     */
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    string private _traitMetadataURI;
    mapping(uint256 => TokenMetadata) private _tokenMetadata;
    Series[] private _series;
    // slither-disable-next-line uninitialized-state-variables
    uint16[] private _availableSeries; // Deprecated in V3
    NeuLogoV2 private _logo;

    BitMaps.BitMap private _availableSeriesMap;

    /**
     * @notice Disables initializers to prevent implementation contract from being initialized.
     * @dev This constructor is only used to disable initializers for the implementation contract. Standard practice for upgradeable contracts.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the metadata contract with roles and dependent contract addresses.
     * @dev Sets up AccessControl, UUPS, grants roles (DEFAULT_ADMIN, UPGRADER, OPERATOR, NEU_ROLE), and sets the Logo contract address.
     * @param defaultAdmin The address to be granted DEFAULT_ADMIN_ROLE.
     * @param upgrader The address to be granted UPGRADER_ROLE.
     * @param operator The address to be granted OPERATOR_ROLE.
     * @param neuContract The address of the main NEU token contract, granted NEU_ROLE.
     * @param logoContract The address of the NeuLogoV2 contract used for generating token SVGs.
     *
     * Emits {LogoUpdated} event with `logoContract`.
     * Emits {InitializedMetadata} event with version, roles, and contract addresses.
     */
    function initialize(
        address defaultAdmin,
        address upgrader,
        address operator,
        address neuContract,
        address logoContract
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, upgrader);
        _grantRole(OPERATOR_ROLE, operator);
        _grantRole(NEU_ROLE, neuContract);

        _logo = NeuLogoV2(logoContract);

        emit LogoUpdated(logoContract);
        emit InitializedMetadata(_VERSION, defaultAdmin, upgrader, operator, neuContract, logoContract);
    }

    /**
     * @notice Initializes V3 specific state, migrating available series from the deprecated `_availableSeries` array to the `_availableSeriesMap` bitmap.
     * @dev Only callable by an account with UPGRADER_ROLE. This is a reinitializer for version 3.
     * Reverts if refundable tokens exist from a previous version to prevent issues during migration.
     *
     * Emits {InitializedMetadataV3} event upon successful V3 initialization.
     * Emits {SeriesAvailabilityUpdated} for each series made available via `_addAvailableSeries`.
     *
     * Requirements:
     * - Caller must have UPGRADER_ROLE.
     * - No refundable tokens must exist (checked by `_hasRefundableTokens`).
     */
    function initializeV3() public reinitializer(3) onlyRole(UPGRADER_ROLE) {
        if (_hasRefundableTokens()) {
            revert("Refundable tokens exist");
        }

        for (uint256 i = 0; i < _availableSeries.length; i++) {
            _addAvailableSeries(_availableSeries[i]);
        }

        emit InitializedMetadataV3();
    }

    /**
     * @notice Deprecated function for creating token metadata. Reverts if called.
     * @dev This function is deprecated in V3. Use `createTokenMetadataV3` instead.
     * @return tokenId Deprecated return value.
     * @return isAvailable Deprecated return value.
     */
    function createTokenMetadata(uint16, uint256) external pure returns (uint256, bool) {
        revert("Deprecated on MetadataV3");
    }

    /**
     * @notice Creates metadata for a new token within a specified series.
     * @dev Only callable by an account with NEU_ROLE (typically the main NEU contract). Assigns the next available tokenId in the series.
     * Updates series minted token count and removes series from `_availableSeriesMap` if maxTokens is reached.
     * @param seriesIndex The index of the series to mint from.
     * @param originalPrice The original price of the token in Wei (will be converted to Gwei for storage).
     * @return tokenId The tokenId of the newly created token metadata.
     *
     * Emits {TokenMetadataUpdated} with the new token's metadata.
     * Emits {TraitUpdated} for the `_POINTS_TRAIT_KEY` (sponsor points, initialized to 0).
     * Emits {SeriesAvailabilityUpdated} if the series becomes fully minted and thus unavailable.
     *
     * Requirements:
     * - Caller must have NEU_ROLE.
     * - `seriesIndex` must be a valid index for an existing series.
     * - The series specified by `seriesIndex` must not be fully minted.
     */
    function createTokenMetadataV3(uint16 seriesIndex, uint256 originalPrice) external onlyRole(NEU_ROLE) returns (uint256 tokenId) {
        require(seriesIndex < _series.length, "Invalid series index");
        require(_series[seriesIndex].mintedTokens < _series[seriesIndex].maxTokens, "Series has been fully minted");

        Series memory series = _series[seriesIndex];
        tokenId = series.firstToken + series.mintedTokens;

        _setTokenMetadata(tokenId, TokenMetadata({
            originalPriceInGwei: uint64(originalPrice / 1e9),
            sponsorPoints: 0,
            mintedAt: uint40(block.timestamp)
        }));

        _series[seriesIndex].mintedTokens = ++series.mintedTokens;

        if (series.mintedTokens == series.maxTokens) {
            _removeAvailableSeries(seriesIndex);
        }
    }

    /**
     * @notice Deletes metadata for a specified token, typically upon burning of the token.
     * @dev Only callable by an account with NEU_ROLE. Increments burnt token count for the token's series.
     * @param tokenId The tokenId whose metadata is to be deleted.
     *
     * Emits {TokenMetadataDeleted} event with the `tokenId`.
     *
     * Requirements:
     * - Caller must have NEU_ROLE.
     * - Metadata for `tokenId` must exist (checked by `_metadataExists`).
     */
    function deleteTokenMetadata(uint256 tokenId) external onlyRole(NEU_ROLE) {
        require(_metadataExists(tokenId), "Token metadata does not exist");

        uint16 seriesIndex = _seriesOfToken(tokenId);

        _series[seriesIndex].burntTokens++;
        delete _tokenMetadata[tokenId];

        emit TokenMetadataDeleted(tokenId);
    }

    /**
     * @notice Sets the URI for external trait metadata.
     * @dev Only callable by an account with NEU_ROLE. This URI can point to a resource providing additional trait information (e.g., an off-chain API or IPFS).
     * @param uri The new URI for trait metadata.
     *
     * Emits {TraitMetadataURIUpdated} event via `_setTraitMetadataURI`.
     */
    function setTraitMetadataURI(string calldata uri) external onlyRole(NEU_ROLE) {
        _setTraitMetadataURI(uri);
    }

    /**
     * @notice Returns the URI for a given token ID, typically containing its metadata in JSON format.
     * @dev Constructs a data URI (RFC 2397) containing base64 encoded JSON metadata.
     * The JSON includes attributes like series name, governance access, supply, mint date, and an on-the-fly generated SVG image.
     * Reverts if metadata for the token does not exist (via `_makeJsonMetadata` which calls `_seriesOfToken`).
     * @param tokenId The ID of the token.
     * @return The data URI string for the token's metadata.
     *
     * Requirements:
     * - Metadata for `tokenId` must exist.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        return string.concat(
            "data:application/json;base64,",
            Base64.encode(_makeJsonMetadata(tokenId))
        );
    }

    /**
     * @notice Checks if a token was originally minted by a user (i.e., had an original price greater than 0).
     * @dev A token is considered user-minted if its metadata exists and `originalPriceInGwei` is greater than 0.
     * @param tokenId The ID of the token to check.
     * @return True if the token was user-minted, false otherwise or if metadata doesn't exist.
     */
    function isUserMinted(uint256 tokenId) external view returns (bool) {
        // slither-disable-next-line timestamp (block miner cannot set timestamp in the past of previous block, so mintedAt == 0 can only mean the token does not exist)
        return _metadataExists(tokenId) && _tokenMetadata[tokenId].originalPriceInGwei > 0;
    }

    /**
     * @notice Retrieves the value of a specific trait for a given token.
     * @dev Delegates to the internal `_getTraitValue` function. Currently, only supports the `_POINTS_TRAIT_KEY` (sponsor points).
     * @param tokenId The ID of the token.
     * @param traitKey The key of the trait to retrieve (e.g., `keccak256("points")`).
     * @return The value of the trait. Returns 0 if trait or token metadata doesn't exist, or if trait key is not found.
     */
    function getTraitValue(uint256 tokenId, bytes32 traitKey) external view returns (bytes32) {
        return _getTraitValue(tokenId, traitKey);
    }

    /**
     * @notice Retrieves the values of multiple traits for a given token.
     * @dev Iterates through `traitKeys` and calls `_getTraitValue` for each.
     * @param tokenId The ID of the token.
     * @param traitKeys An array of trait keys to retrieve.
     * @return traitValues An array of corresponding trait values. Order matches `traitKeys`.
     */
    function getTraitValues(uint256 tokenId, bytes32[] calldata traitKeys) external view returns (bytes32[] memory traitValues) {
        uint256 length = traitKeys.length;
        traitValues = new bytes32[](length);

        for (uint256 i = 0; i < length; i++) {
            bytes32 traitKey = traitKeys[i];
            traitValues[i] = _getTraitValue(tokenId, traitKey);
        }
    }

    /**
     * @notice Returns the currently set URI for external trait metadata.
     * @return The trait metadata URI string. Can be empty if not set.
     */
    function getTraitMetadataURI() external view returns (string memory) {
        // Return the trait metadata URI.
        return _traitMetadataURI;
    }

    /**
     * @notice Adds a new token series.
     * @dev Only callable by an account with OPERATOR_ROLE. Validates against existing series for name uniqueness and token ID range overlaps.
     * @param name The name of the series (bytes8).
     * @param priceInGwei The price of tokens in this series, in Gwei.
     * @param firstToken The starting tokenId for this series.
     * @param maxTokens The maximum number of tokens that can be minted in this series.
     * @param fgColorRGB565 The foreground color for the series logo (RGB565 format).
     * @param bgColorRGB565 The background color for the series logo (RGB565 format).
     * @param accentColorRGB565 The accent color for the series logo (RGB565 format).
     * @param makeAvailable If true, the series is immediately made available for minting via `_addAvailableSeries`.
     * @return seriesIndex The index of the newly added series in the `_series` array.
     *
     * Emits {SeriesAdded} event with all series parameters.
     * Emits {SeriesAvailabilityUpdated} if `makeAvailable` is true and the series becomes available.
     *
     * Requirements:
     * - Caller must have OPERATOR_ROLE.
     * - `maxTokens` must be > 0.
     * - `priceInGwei` must be > 0.
     * - `firstToken` must be > 0.
     * - Series `name` must be unique among existing series.
     * - Token ID range (`firstToken` to `firstToken + maxTokens - 1`) must not overlap with any existing series.
     */
    function addSeries(bytes8 name, uint64 priceInGwei, uint32 firstToken, uint32 maxTokens, uint16 fgColorRGB565, uint16 bgColorRGB565, uint16 accentColorRGB565, bool makeAvailable) external onlyRole(OPERATOR_ROLE) returns (uint16) {
        require(maxTokens > 0, "maxTokens cannot be 0");
        require(priceInGwei > 0, "Price cannot be 0");
        require(firstToken > 0, "FirstToken cannot be 0");

        uint16 seriesIndex = uint16(_series.length);
        uint256 maxToken = firstToken + maxTokens - 1;

        for (uint16 i = 0; i < seriesIndex; i++) {
            Series memory series = _series[i];

            require(series.name != name, "Series name already exists");
            require(maxToken < series.firstToken || firstToken >= series.firstToken + series.maxTokens, "Series overlaps with existing");
        }

        _series.push(Series({
            name: name,
            priceInGwei: priceInGwei,
            firstToken: firstToken,
            maxTokens: maxTokens,
            mintedTokens: 0,
            burntTokens: 0,
            fgColorRGB565: fgColorRGB565,
            bgColorRGB565: bgColorRGB565,
            accentColorRGB565: accentColorRGB565
        }));

        if (makeAvailable) {
            _addAvailableSeries(seriesIndex);
        }

        emit SeriesAdded(seriesIndex, name, priceInGwei, firstToken, maxTokens, fgColorRGB565, bgColorRGB565, accentColorRGB565, makeAvailable);
        return seriesIndex;
    }

    /**
     * @notice Retrieves detailed information about a specific token series.
     * @dev Includes series parameters (name, price, token IDs, supply, colors), minting status (minted/burnt counts), availability, and a generated SVG logo for the series.
     * @param seriesIndex The index of the series to retrieve.
     * @return name The name of the series (bytes8).
     * @return priceInGwei The price of tokens in this series, in Gwei.
     * @return firstToken The starting tokenId for this series.
     * @return maxTokens The maximum number of tokens in this series.
     * @return mintedTokens The number of tokens already minted in this series.
     * @return burntTokens The number of tokens burnt from this series.
     * @return isAvailable True if the series is currently available for minting (checked via `_isSeriesAvailable`).
     * @return logoSvg An SVG string representing the logo for this series, generated by `_logo.makeLogo`.
     *
     * Requirements:
     * - `seriesIndex` must be a valid index for an existing series (i.e., `seriesIndex < _series.length`).
     */
    function getSeries(uint16 seriesIndex) external view returns (
        bytes8 name,
        uint256 priceInGwei,
        uint256 firstToken,
        uint256 maxTokens,
        uint256 mintedTokens,
        uint256 burntTokens,
        bool isAvailable,
        string memory logoSvg
    ) {
        require(seriesIndex < _series.length, "Invalid series index");

        Series memory series = _series[seriesIndex];

        name = series.name;
        priceInGwei = series.priceInGwei;
        firstToken = series.firstToken;
        maxTokens = series.maxTokens;
        mintedTokens = series.mintedTokens;
        burntTokens = series.burntTokens;
        isAvailable = _isSeriesAvailable(seriesIndex);
        logoSvg = _logo.makeLogo(
            _makeMaskedTokenId(series), series.name.toString(), series.fgColorRGB565, series.bgColorRGB565, series.accentColorRGB565);
    }

    /**
     * @notice Checks if a specific series is currently available for minting.
     * @dev Delegates to the internal `_isSeriesAvailable` function, which checks the `_availableSeriesMap`.
     * @param seriesIndex The index of the series to check.
     * @return True if the series is available, false otherwise.
     */
    function isSeriesAvailable(uint16 seriesIndex) external view returns (bool) {
        return _isSeriesAvailable(seriesIndex);
    }

    /**
     * @notice Sets the minting availability for a specific series.
     * @dev Only callable by an account with OPERATOR_ROLE. Updates `_availableSeriesMap` via `_addAvailableSeries` or `_removeAvailableSeries`.
     * @param seriesIndex The index of the series to update.
     * @param available True to make the series available, false to make it unavailable.
     *
     * Emits {SeriesAvailabilityUpdated} event if the availability status changes.
     *
     * Requirements:
     * - Caller must have OPERATOR_ROLE.
     * - `seriesIndex` must be a valid index for an existing series.
     * - If setting `available` to true, the series must not be fully minted.
     */
    function setSeriesAvailability(uint16 seriesIndex, bool available) external onlyRole(OPERATOR_ROLE) {
        require(seriesIndex < _series.length, "Invalid series index");

        if (available) {
            if (_series[seriesIndex].mintedTokens == _series[seriesIndex].maxTokens) {
                revert("Series has been fully minted");
            }

            _addAvailableSeries(seriesIndex);
        } else {
            _removeAvailableSeries(seriesIndex);
        }
    }

    /**
     * @notice Returns an array of indices for all series currently available for minting.
     * @dev Iterates through all series and checks `_isSeriesAvailable` for each. Constructs an array of available series indices.
     * Note: This function has an unbounded loop based on the total number of series, which could be gas-intensive if there are many series. It is not typically expected to be called by other smart contracts.
     * @return An array of `uint16` series indices that are currently available.
     */
    function getAvailableSeries() external view returns(uint16[] memory) {
        // This function has an unbounded loop, so it's not expected to be called by other contracts
        uint16 availableSeriesLength = uint16(_series.length);

        uint16[] memory availableSeries = new uint16[](availableSeriesLength);
        uint16 availableSeriesCount = 0;

        for (uint16 i = 0; i < availableSeriesLength; i++) {
            if (_isSeriesAvailable(i)) {
                availableSeries[availableSeriesCount] = i;
                availableSeriesCount++;
            }
        }

        assembly {
            mstore(availableSeries, availableSeriesCount)
        }

        return availableSeries;
    }

    /**
     * @notice Sets the minting price for a specific series.
     * @dev Only callable by an account with OPERATOR_ROLE. Updates the `priceInGwei` for the specified series.
     * @param seriesIndex The index of the series to update.
     * @param price The new price in Gwei for minting tokens in this series.
     *
     * Emits {SeriesPriceUpdated} event with the updated price.
     *
     * Requirements:
     * - Caller must have OPERATOR_ROLE.
     * - `seriesIndex` must be a valid index for an existing series.
     * - `price` must be greater than 0.
     */
    function setPriceInGwei(uint16 seriesIndex, uint64 price) external onlyRole(OPERATOR_ROLE) {
        require(seriesIndex < _series.length, "Invalid series index");
        require(price > 0, "Price cannot be 0");

        _series[seriesIndex].priceInGwei = price;

        emit SeriesPriceUpdated(seriesIndex, price);
    }

    /**
     * @notice Retrieves the minting price for a specific series.
     * @dev Returns the `priceInGwei` for the specified series.
     * @param seriesIndex The index of the series to query.
     * @return The price in Gwei for minting tokens in this series.
     *
     * Requirements:
     * - `seriesIndex` must be a valid index for an existing series.
     */
    function getSeriesMintingPrice(uint16 seriesIndex) external view returns (uint256) {
        require(_isSeriesAvailable(seriesIndex), "Public minting not available");

        return uint256(_series[seriesIndex].priceInGwei) * 1e9;
    }

    /**
     * @notice Deprecated function for summing all refundable token values. Reverts if called.
     * @dev This function is deprecated in V3 and should not be used.
     */
    function sumAllRefundableTokensValue() external pure returns (uint256) {
        revert("Deprecated on MetadataV3");
    }

    /**
     * @notice Deprecated function for getting refund amount. Reverts if called.
     * @dev Tokens are not refundable in V3, hence this function should not be used.
     */
    function getRefundAmount(uint256) external pure returns (uint256) {
        revert("Token is not refundable");
    }

    /**
     * @notice Sets the address of the NeuLogoV2 contract for generating SVG logos.
     * @dev Only callable by an account with OPERATOR_ROLE. Updates the `_logo` contract reference.
     * @param logoContract The address of the new NeuLogoV2 contract.
     *
     * Emits {LogoUpdated} event with the new contract address.
     */
    function setLogoContract(address logoContract) external onlyRole(OPERATOR_ROLE) {
        _logo = NeuLogoV2(logoContract);
        
        emit LogoUpdated(logoContract);
    }

    /**
     * @notice Internal function to set token metadata.
     * @dev Updates the `_tokenMetadata` mapping with the provided metadata.
     * @param tokenId The ID of the token to update.
     * @param metadata The new metadata for the token.
     *
     * Emits {TokenMetadataUpdated} and {TraitUpdated} events with the updated metadata.
     */
    function _setTokenMetadata(
        uint256 tokenId,
        TokenMetadata memory metadata
    ) internal {
        _tokenMetadata[tokenId] = metadata;

        emit TokenMetadataUpdated(tokenId, metadata);
        emit TraitUpdated(_POINTS_TRAIT_KEY, tokenId, bytes32(uint256(metadata.sponsorPoints)));
    }

    /**
     * @notice Increases the sponsor points for a specific token.
     * @dev Only callable by an account with NEU_ROLE. Updates the `sponsorPoints` in the token's metadata.
     * @param tokenId The ID of the token to update.
     * @param sponsorPointsIncrease The amount to increase the sponsor points by.
     * @return The new sponsor points value after the increase.
     *
     * Requirements:
     * - Caller must have NEU_ROLE.
     * - Metadata for `tokenId` must exist.
     */
    function increaseSponsorPoints(uint256 tokenId, uint256 sponsorPointsIncrease) external onlyRole(NEU_ROLE) returns (uint256) {
        TokenMetadata memory metadata = _tokenMetadata[tokenId];

        uint256 newSponsorPoints = metadata.sponsorPoints + sponsorPointsIncrease;

        _tokenMetadata[tokenId] = TokenMetadata({
            originalPriceInGwei: metadata.originalPriceInGwei,
            sponsorPoints: newSponsorPoints.toUint64(),
            mintedAt: metadata.mintedAt
        });

        return newSponsorPoints;
    }
    /**
     * @notice Checks if a token is part of a governance series.
     * @dev Determines governance access based on the series index of the token ID.
     * @param tokenId The ID of the token to check.
     * @return True if the token belongs to a governance series, false otherwise.
     */
    function isGovernanceToken(uint256 tokenId) external view returns (bool) {
        uint16 seriesIndex = _seriesOfToken(tokenId);
        return _givesGovernanceAccess(seriesIndex);
    }

    /**
     * @notice Checks if a series is available for minting.
     * @dev Uses the `_availableSeriesMap` to determine availability.
     * @param seriesIndex The index of the series to check.
     * @return True if the series is available, false otherwise.
     */
    function _isSeriesAvailable(uint16 seriesIndex) private view returns (bool) {
        return _availableSeriesMap.get(seriesIndex);
    }

    /**
     * @notice Marks a series as available for minting.
     * @dev Updates the `_availableSeriesMap` and emits an event if the status changes.
     * @param seriesIndex The index of the series to update.
     */
    function _addAvailableSeries(uint16 seriesIndex) private {
        if (!_isSeriesAvailable(seriesIndex)) {
            _availableSeriesMap.set(seriesIndex);
            emit SeriesAvailabilityUpdated(seriesIndex, true);
        }
    }

    /**
     * @notice Marks a series as unavailable for minting.
     * @dev Updates the `_availableSeriesMap` and emits an event if the status changes.
     * @param seriesIndex The index of the series to update.
     */
    function _removeAvailableSeries(uint16 seriesIndex) private {
        if (_isSeriesAvailable(seriesIndex)) {
            _availableSeriesMap.unset(seriesIndex);
            emit SeriesAvailabilityUpdated(seriesIndex, false);
        }
    }

    /**
     * @notice Retrieves the value of a specific trait for a token.
     * @dev Only supports the `_POINTS_TRAIT_KEY` (sponsor points) currently.
     * @param tokenId The ID of the token.
     * @param traitKey The key of the trait to retrieve.
     * @return The value of the trait.
     */
    function _getTraitValue(uint256 tokenId, bytes32 traitKey) private view returns (bytes32) {
        TokenMetadata memory metadata = _tokenMetadata[tokenId];

        if (traitKey == _POINTS_TRAIT_KEY) {
            return bytes32(uint256(metadata.sponsorPoints));
        } else {
            revert("Trait key not found");
        }
    }

    /**
     * @notice Generates JSON metadata for a token.
     * @dev Constructs a JSON string with token attributes and an on-the-fly generated SVG image.
     * @param tokenId The ID of the token.
     * @return The JSON metadata as a byte array.
     */
    function _makeJsonMetadata(uint256 tokenId) internal view returns (bytes memory) {
        TokenMetadata memory metadata = _tokenMetadata[tokenId];
        uint16 seriesIndex = _seriesOfToken(tokenId);
        Series memory series = _series[seriesIndex];
        string memory governance = _givesGovernanceAccess(seriesIndex) ? "Yes" : "No";
        string memory seriesName = series.name.toString();
        string memory tokenName = string.concat(tokenId.toString(), ' ', seriesName);
        string memory logoSvg = Base64.encode(bytes(_logo.makeLogo(
            tokenId.toString(), seriesName, series.fgColorRGB565, series.bgColorRGB565, series.accentColorRGB565)));

        return bytes(string.concat(
            '{"description": "Neulock Password Manager membership NFT - neulock.app", "name": "NEU #',
            tokenName,
            '", "image": "data:image/svg+xml;base64,',
            logoSvg,
            '", "attributes": [{"trait_type": "Series", "value": "',
            seriesName,
            '"},{"trait_type": "Governance Access", "value": "',
            governance,
            '"},{"trait_type": "Series Max Supply", "value": ',
            uint256(series.maxTokens).toString(),
            '},{"trait_type": "Mint Date", "display_type": "date", "value": ',
            uint256(metadata.mintedAt).toString(),
            '}]}'
        ));
    }

    /**
     * @notice Determines the series index for a token ID.
     * @dev Iterates through series to find the matching range for the token ID.
     * @param tokenId The ID of the token.
     * @return The index of the series the token belongs to.
     */
    function _seriesOfToken(uint256 tokenId) private view returns (uint16) {
        uint256 seriesLength = _series.length;

        for (uint16 i = 0; i < seriesLength; i++) {
            if (tokenId >= _series[i].firstToken && tokenId < _series[i].firstToken + _series[i].maxTokens) {
                return i;
            }
        }

        revert("Token does not belong to any series");
    }

    /**
     * @notice Creates a masked token ID string for display.
     * @dev Masks differing digits in the token ID range with 'x'.
     * @param series The series information.
     * @return The masked token ID string.
     */
    function _makeMaskedTokenId(Series memory series) private pure returns (string memory) {
        uint256 lastToken = series.firstToken + series.maxTokens - 1;
        bytes memory lastTokenBytes = bytes(lastToken.toString());
        bytes memory firstTokenBytes = bytes(uint256(series.firstToken).toString());

        bool stoppedMatching = firstTokenBytes.length != lastTokenBytes.length;
        bytes memory result = new bytes(lastTokenBytes.length);

        for (uint256 i = 0; i < result.length; i++) {
            if (!stoppedMatching && firstTokenBytes.length > i && lastTokenBytes[i] == firstTokenBytes[i]) {
                result[i] = lastTokenBytes[i];
            } else {
                stoppedMatching = true;
                result[i] = "x";
            }
        }

        return string(result);
    }

    /**
     * @notice Checks if metadata exists for a token ID.
     * @dev Determines existence based on the `mintedAt` timestamp.
     * @param tokenId The ID of the token to check.
     * @return True if metadata exists, false otherwise.
     */
    function _metadataExists(uint256 tokenId) private view returns (bool) {
        return _tokenMetadata[tokenId].mintedAt != 0;
    }

    /**
     * @notice Determines if a series grants governance access.
     * @dev Checks if series name does not start with "WAGMI".
     * @param seriesIndex The index of the series to check.
     * @return True if the series grants governance access, false otherwise.
     */
    function _givesGovernanceAccess(uint16 seriesIndex) private view returns (bool) {
        bytes32 wagmiNamePrefix = "WAGMI";
        bytes8 seriesName = _series[seriesIndex].name;

        for (uint256 i = 0; i < 5; i++) {
            if (seriesName[i] != wagmiNamePrefix[i]) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Sets the URI for trait metadata.
     * @dev Updates the `_traitMetadataURI` with the new URI.
     * @param uri The new trait metadata URI.
     *
     * Emits {MetadataURIUpdated} event with the new URI.
     */
    function _setTraitMetadataURI(string memory uri) private {
        _traitMetadataURI = uri;

        emit MetadataURIUpdated(uri);
    }

    /**
     * @notice Checks if there are any refundable tokens within the refund window.
     * @dev Iterates through series and tokens to determine refund eligibility.
     * @return True if any refundable tokens exist, false otherwise.
     */
    function _hasRefundableTokens() private view returns (bool) {
        uint256 seriesLength = _series.length;

        for (uint256 i = 0; i < seriesLength; i++) {
            Series memory series = _series[i];

            for (uint256 j = series.firstToken + series.mintedTokens - 1; j >= series.firstToken; j--) {
                if (!_metadataExists(j)) { // Token burned
                    continue;
                }

                TokenMetadata memory metadata = _tokenMetadata[j];

                // slither-disable-next-line dangerous-strict-equalities (makes no sense to use >= 0)
                if (metadata.originalPriceInGwei == 0) { // Token airdropped
                    continue;
                }
                
                // slither-disable-next-line timestamp (with a granularity of days for refunds, we can tolerate miner manipulation)
                if (block.timestamp - metadata.mintedAt <= _REFUND_WINDOW) {
                    return true;
                }

                // No other tokens in series can be in refund window
                break;
            }
        }

        return false;
    }

    /**
     * @notice Authorizes contract upgrades.
     * @dev Only callable by an account with UPGRADER_ROLE.
     * @param newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}
