// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseController, IChainlinkAggregatorLike } from "./BaseController.sol";

/**
 * @title PriceFeedManager
 * @notice Abstract contract for managing Chainlink price feeds for various assets
 * @dev Extends BaseController and provides functionality to set, retrieve, and validate price feeds
 * All prices are normalized to 18 decimals for consistency across the protocol
 */
abstract contract PriceFeedManager is BaseController {
    /**
     * @notice Role identifier for price feed management operations
     */
    bytes32 public constant PRICE_FEED_MANAGER_ROLE = keccak256("PRICE_FEED_MANAGER_ROLE");
    /**
     * @notice Buffer time for price feed heartbeats
     * @dev Allows a small grace period beyond the configured heartbeat to account for minor delays
     */
    uint256 public constant HEARTBEAT_BUFFER = 1 minutes;
    /**
     * @notice Number of decimals used for normalized price representation
     */
    uint8 public constant NORMALIZED_PRICE_DECIMALS = 18;

    /**
     * @notice Emitted when a price feed is updated for an asset
     */
    event PriceFeedUpdated(
        address indexed asset, address indexed oldFeed, address indexed newFeed, uint24 newHeartbeat
    );

    /**
     * @notice Thrown when attempting to set a price feed for a zero address asset
     */
    error PriceFeed_ZeroAsset();
    /**
     * @notice Thrown when attempting to set a zero address as a price feed
     */
    error PriceFeed_ZeroFeed();
    /**
     * @notice Thrown when the provided heartbeat value is zero
     */
    error PriceFeed_ZeroHeartbeat();
    /**
     * @notice Thrown when trying to get price for an asset without a configured price feed
     */
    error PriceFeed_FeedNotExists();
    /**
     * @notice Thrown when the price feed returns an invalid (non-positive) price
     */
    error PriceFeed_InvalidPrice();
    /**
     * @notice Thrown when the price feed data is stale based on the configured heartbeat
     */
    error PriceFeed_StalePrice();
    /**
     * @notice Thrown when the price feed has more decimals than the normalized decimals
     */
    error PriceFeed_DecimalsTooHigh();

    /**
     * @notice Internal initialization function for PriceFeedManager
     * @dev Must be called during contract initialization. Currently empty but reserved for future use
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function __PriceFeedManager_init() internal onlyInitializing { }

    /**
     * @notice Sets the Chainlink price feed for a specific asset
     * @dev Only callable by accounts with PRICE_FEED_MANAGER_ROLE
     * @param asset The address of the asset to set the price feed for
     * @param feed The Chainlink aggregator interface for the asset's price feed
     * @param heartbeat The maximum allowed time in seconds between price updates before data is considered stale
     */
    function setPriceFeed(
        address asset,
        IChainlinkAggregatorLike feed,
        uint24 heartbeat
    )
        external
        onlyRole(PRICE_FEED_MANAGER_ROLE)
    {
        require(asset != address(0), PriceFeed_ZeroAsset());
        require(address(feed) != address(0), PriceFeed_ZeroFeed());
        require(heartbeat > 0, PriceFeed_ZeroHeartbeat());
        emit PriceFeedUpdated(asset, address(priceFeeds[asset].feed), address(feed), heartbeat);
        priceFeeds[asset] = PriceFeed({ feed: feed, heartbeat: heartbeat });
    }

    /**
     * @notice Retrieves the current price of an asset from its configured price feed
     * @dev Normalizes the price to 18 decimals regardless of the feed's native decimal places
     * @param asset The address of the asset to get the price for
     * @return normalizedPrice The asset's price normalized to 18 decimals
     */
    function getAssetPrice(address asset) public view returns (uint256 normalizedPrice) {
        PriceFeed memory priceFeed = priceFeeds[asset];
        require(address(priceFeed.feed) != address(0), PriceFeed_FeedNotExists());

        (, int256 answer,, uint256 updatedAt,) = priceFeed.feed.latestRoundData();
        require(answer > 0, PriceFeed_InvalidPrice());
        require(block.timestamp - updatedAt <= priceFeed.heartbeat + HEARTBEAT_BUFFER, PriceFeed_StalePrice());

        uint8 decimals = priceFeed.feed.decimals();
        require(decimals <= NORMALIZED_PRICE_DECIMALS, PriceFeed_DecimalsTooHigh());

        // casting to 'uint256' is safe because 'answer' is guaranteed to be positive
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(answer) * 10 ** (NORMALIZED_PRICE_DECIMALS - decimals);
    }

    /**
     * @notice Checks if a price feed exists for the given asset
     * @dev Overrides the abstract function from BaseController
     * @param asset The address of the asset to check
     * @return True if a price feed is configured for the asset, false otherwise
     */
    function priceFeedExists(address asset) public view returns (bool) {
        return address(priceFeeds[asset].feed) != address(0);
    }
}
