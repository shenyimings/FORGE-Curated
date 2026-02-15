// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {SanityCheckTrait} from "@gearbox-protocol/core-v3/contracts/traits/SanityCheckTrait.sol";
import {PriceFeedValidationTrait} from "@gearbox-protocol/core-v3/contracts/traits/PriceFeedValidationTrait.sol";
import {IPriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";

import {IPriceFeedStore} from "../interfaces/IPriceFeedStore.sol";
import {AP_PRICE_FEED_STORE, AP_INSTANCE_MANAGER_PROXY, NO_VERSION_CONTROL} from "../libraries/ContractLiterals.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {PriceFeedInfo} from "../interfaces/Types.sol";
import {ImmutableOwnableTrait} from "../traits/ImmutableOwnableTrait.sol";

contract PriceFeedStore is ImmutableOwnableTrait, SanityCheckTrait, PriceFeedValidationTrait, IPriceFeedStore {
    using EnumerableSet for EnumerableSet.AddressSet;

    //
    // CONSTANTS
    //

    /// @notice Meta info about contract type & version
    uint256 public constant override version = 3_10;
    bytes32 public constant override contractType = AP_PRICE_FEED_STORE;

    //
    // VARIABLES
    //

    /// @dev Set of all known price feeds
    EnumerableSet.AddressSet internal _knownPriceFeeds;

    /// @dev Set of all known price feeds
    EnumerableSet.AddressSet internal _knownTokens;

    /// @dev Mapping from token address to its set of allowed price feeds
    mapping(address token => EnumerableSet.AddressSet) internal _allowedPriceFeeds;

    /// @dev Mapping from a (token, priceFeed) pair to a timestamp when price feed was allowed for token
    mapping(address token => mapping(address priceFeed => uint256)) _allowanceTimestamps;

    /// @notice Mapping from price feed address to its data
    mapping(address => PriceFeedInfo) internal _priceFeedInfo;

    constructor(address _addressProvider)
        ImmutableOwnableTrait(
            IAddressProvider(_addressProvider).getAddressOrRevert(AP_INSTANCE_MANAGER_PROXY, NO_VERSION_CONTROL)
        )
    {}

    /// @notice Returns the list of price feeds available for a token
    function getPriceFeeds(address token) external view returns (address[] memory) {
        return _allowedPriceFeeds[token].values();
    }

    /// @notice Returns whether a price feed is allowed to be used for a token
    function isAllowedPriceFeed(address token, address priceFeed) external view returns (bool) {
        return _allowedPriceFeeds[token].contains(priceFeed);
    }

    /// @notice Returns the staleness period for a price feed
    function getStalenessPeriod(address priceFeed) external view returns (uint32) {
        return _priceFeedInfo[priceFeed].stalenessPeriod;
    }

    /// @notice Returns the timestamp when priceFeed was allowed for token
    function getAllowanceTimestamp(address token, address priceFeed) external view returns (uint256) {
        if (!_allowedPriceFeeds[token].contains(priceFeed)) revert PriceFeedIsNotAllowedException(token, priceFeed);
        return _allowanceTimestamps[token][priceFeed];
    }

    function getKnownTokens() external view returns (address[] memory) {
        return _knownTokens.values();
    }

    function getKnownPriceFeeds() external view returns (address[] memory) {
        return _knownPriceFeeds.values();
    }

    /**
     * @notice Adds a new price feed
     * @param priceFeed The address of the new price feed
     * @param stalenessPeriod Staleness period of the new price feed
     * @dev Reverts if the price feed's result is stale based on the staleness period
     */
    function addPriceFeed(address priceFeed, uint32 stalenessPeriod) external onlyOwner nonZeroAddress(priceFeed) {
        if (_knownPriceFeeds.contains(priceFeed)) revert PriceFeedAlreadyAddedException(priceFeed);

        _validatePriceFeed(priceFeed, stalenessPeriod);

        bytes32 priceFeedType;
        uint256 priceFeedVersion;

        try IPriceFeed(priceFeed).contractType() returns (bytes32 _cType) {
            priceFeedType = _cType;
            priceFeedVersion = IPriceFeed(priceFeed).version();
        } catch {
            priceFeedType = "PRICE_FEED::EXTERNAL";
            priceFeedVersion = 0;
        }

        _knownPriceFeeds.add(priceFeed);
        _priceFeedInfo[priceFeed].author = msg.sender;
        _priceFeedInfo[priceFeed].priceFeedType = priceFeedType;
        _priceFeedInfo[priceFeed].stalenessPeriod = stalenessPeriod;
        _priceFeedInfo[priceFeed].version = priceFeedVersion;

        emit AddPriceFeed(priceFeed, stalenessPeriod);
    }

    /**
     * @notice Sets the staleness period for an existing price feed
     * @param priceFeed The address of the price feed
     * @param stalenessPeriod New staleness period for the price feed
     * @dev Reverts if the price feed is not added to the global list
     */
    function setStalenessPeriod(address priceFeed, uint32 stalenessPeriod)
        external
        onlyOwner
        nonZeroAddress(priceFeed)
    {
        if (!_knownPriceFeeds.contains(priceFeed)) revert PriceFeedNotKnownException(priceFeed);
        uint32 oldStalenessPeriod = _priceFeedInfo[priceFeed].stalenessPeriod;

        if (stalenessPeriod != oldStalenessPeriod) {
            _validatePriceFeed(priceFeed, stalenessPeriod);
            _priceFeedInfo[priceFeed].stalenessPeriod = stalenessPeriod;
            emit SetStalenessPeriod(priceFeed, stalenessPeriod);
        }
    }

    /**
     * @notice Allows a price feed for use with a particular token
     * @param token Address of the token
     * @param priceFeed Address of the price feed
     * @dev Reverts if the price feed is not added to the global list
     */
    function allowPriceFeed(address token, address priceFeed) external onlyOwner nonZeroAddress(token) {
        if (!_knownPriceFeeds.contains(priceFeed)) revert PriceFeedNotKnownException(priceFeed);

        _allowedPriceFeeds[token].add(priceFeed);
        _allowanceTimestamps[token][priceFeed] = block.timestamp;
        _knownTokens.add(token);

        emit AllowPriceFeed(token, priceFeed);
    }

    /**
     * @notice Forbids a price feed for use with a particular token
     * @param token Address of the token
     * @param priceFeed Address of the price feed
     * @dev Reverts if the price feed is not added to the global list or the per-token list
     */
    function forbidPriceFeed(address token, address priceFeed) external onlyOwner nonZeroAddress(token) {
        if (!_knownPriceFeeds.contains(priceFeed)) revert PriceFeedNotKnownException(priceFeed);
        if (!_allowedPriceFeeds[token].contains(priceFeed)) revert PriceFeedIsNotAllowedException(token, priceFeed);

        _allowedPriceFeeds[token].remove(priceFeed);
        _allowanceTimestamps[token][priceFeed] = 0;

        emit ForbidPriceFeed(token, priceFeed);
    }

    function priceFeedInfo(address priceFeed) external view returns (PriceFeedInfo memory) {
        return _priceFeedInfo[priceFeed];
    }
}
