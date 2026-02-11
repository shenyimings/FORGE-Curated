// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {IImmutableOwnableTrait} from "./base/IImmutableOwnableTrait.sol";

interface IPriceFeedStore is IVersion, IImmutableOwnableTrait {
    //
    // ERRORS
    //

    /// @notice Thrown when attempting to use a price feed that is not known by the price feed store
    error PriceFeedNotKnownException(address priceFeed);

    /// @notice Thrown when attempting to add a price feed that is already known by the price feed store
    error PriceFeedAlreadyAddedException(address priceFeed);

    /// @notice Thrown when attempting to remove a price feed that is not allowed for a token
    error PriceFeedIsNotAllowedException(address token, address priceFeed);

    //
    // EVENTS
    //

    /// @notice Emitted when a new price feed is added to PriceFeedStore
    event AddPriceFeed(address priceFeed, uint32 stalenessPeriod);

    /// @notice Emitted when the staleness period is changed in an existing price feed
    event SetStalenessPeriod(address priceFeed, uint32 stalenessPeriod);

    /// @notice Emitted when a price feed is allowed for a token
    event AllowPriceFeed(address token, address priceFeed);

    /// @notice Emitted when a price feed is forbidden for a token
    event ForbidPriceFeed(address token, address priceFeed);

    //
    // GETTERS
    //
    function getPriceFeeds(address token) external view returns (address[] memory);
    function isAllowedPriceFeed(address token, address priceFeed) external view returns (bool);
    function getStalenessPeriod(address priceFeed) external view returns (uint32);
    function getAllowanceTimestamp(address token, address priceFeed) external view returns (uint256);

    //
    // CONFIGURATION
    //
    function addPriceFeed(address priceFeed, uint32 stalenessPeriod) external;
    function setStalenessPeriod(address priceFeed, uint32 stalenessPeriod) external;
    function allowPriceFeed(address token, address priceFeed) external;
    function forbidPriceFeed(address token, address priceFeed) external;
}
