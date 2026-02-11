// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Ownable} from "../Ownable.sol";
import {IOracleRouter} from "../interfaces/IOracleRouter.sol";
import {IFeedRegistry} from "../interfaces/IFeedRegistry.sol";

/**
 * @title OracleRouter
 * @notice Price router based on Chainlink Feed Registry with two hop options:
 *         - TOKEN/USD (preferred), or
 *         - TOKEN/ETH bridged via ETH/USD.
 *         All outputs are normalized to PRICE_UNIT (10 ** PRICE_DECIMALS).
 */
contract OracleRouter is IOracleRouter, Ownable {
    // ==================== Immutables ====================

    /// @notice Number of decimals used for price normalization (typically 8 or 18).
    uint8 public immutable PRICE_DECIMALS;
    /// @notice Price unit calculated as 10 ** PRICE_DECIMALS.
    uint256 public immutable PRICE_UNIT;
    /// @notice Address of the Chainlink Feed Registry contract.
    address public immutable FEED_REGISTRY;

    // ==================== Constants ====================

    /// @notice Address representing USD denomination in Chainlink Feed Registry.
    address private constant USD_DENOMINATION = 0x0000000000000000000000000000000000000348;
    /// @notice Address representing ETH denomination in Chainlink Feed Registry.
    address private constant ETH_DENOMINATION = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Maximum supported decimals for feeds and tokens.
    uint128 public constant MAX_DECIMALS = 38;

    // ==================== Type Definitions ====================

    struct FeedConfig {
        address aggregator;
        uint128 scaleNumerator;
        uint128 scaleDenominator;
        uint32 maxStalenessSeconds;
        uint8 aggregatorDecimals;
    }

    struct TokenConfig {
        IOracleRouter.QuoteDenomination primaryQuote;
        FeedConfig primaryFeed;
        uint8 tokenDecimals;
        bool isActive;
        uint32 ethUsdMaxStalenessOverrideSeconds; // 0 => use global bridge staleness
    }

    struct BridgeCache {
        uint256 price;
        uint32 capSeconds;
    }

    // ==================== Storage Variables ====================

    /// @notice Mapping from token address to its price feed configuration.
    mapping(address => TokenConfig) public tokenConfig;
    /// @notice Configuration for the ETH/USD bridge feed used for tokens quoted in ETH.
    FeedConfig public ethUsdBridge;

    // ==================== Events ====================

    event TokenConfigured(
        address indexed token,
        IOracleRouter.QuoteDenomination primaryQuote,
        address indexed aggregator,
        uint8 aggregatorDecimals,
        uint32 maxStalenessSeconds,
        uint8 tokenDecimals,
        uint128 scaleNumerator,
        uint128 scaleDenominator,
        bool isActive
    );
    event TokenActiveUpdated(address indexed token, bool isActive);
    event EthUsdBridgeConfigured(
        address indexed aggregator,
        uint8 aggregatorDecimals,
        uint32 maxStalenessSeconds,
        uint128 scaleNumerator,
        uint128 scaleDenominator
    );
    event TokenEthUsdStalenessOverridden(address indexed token, uint32 overrideSeconds);

    // ==================== Errors ====================

    error InvalidFeedRegistryAddress(address feedRegistry);
    error InvalidTokenAddress(address token);
    error InvalidStaleness();
    error InvalidAggregatorDecimals();
    error InvalidUnitDecimals();
    error InvalidTokenDecimals();
    error TokenNotConfigured(address token);
    error TokenDecimalsMismatch(uint8 erc20Decimals, uint8 providedDecimals);
    error TokenStateUnchanged(address token, bool currentState);
    error EthUsdBridgeMissing();
    error FeedMissing(address base, address quote);
    error FeedConfigOutOfSync(
        address expectedAggregator,
        address actualAggregator,
        uint8 expectedDecimals,
        uint8 actualDecimals
    );
    error OracleStale(address aggregator, uint256 lastUpdate);
    error OracleBadAnswer(address aggregator, int256 answer);
    error OracleUnanswered(address aggregator, uint80 roundId, uint80 answeredInRound);
    error OracleQuantizedToZero(address aggregator, uint8 feedDecimals, uint8 unitDecimals);

    // ==================== Constructor ====================

    /**
     * @notice Constructor
     * @param agent_ Address of the owner agent.
     * @param unitDecimals_ Number of decimals for price normalization.
     * @param feedRegistry_ Address of the Chainlink Feed Registry.
     */
    constructor(address agent_, uint8 unitDecimals_, address feedRegistry_) Ownable(agent_) {
        if (unitDecimals_ == 0 || unitDecimals_ > MAX_DECIMALS) {
            revert InvalidUnitDecimals();
        }

        if (feedRegistry_ == address(0)) {
            revert InvalidFeedRegistryAddress(feedRegistry_);
        }

        FEED_REGISTRY = feedRegistry_;
        PRICE_DECIMALS = unitDecimals_;

        unchecked {
            PRICE_UNIT = 10 ** unitDecimals_;
        }
    }

    // ==================== External Functions ====================

    /**
     * @notice Sets the ETH/USD bridge configuration for token price routing.
     * @param maxStalenessSeconds_ Maximum allowed staleness for ETH/USD price feed.
     */
    function setEthUsdBridge(uint32 maxStalenessSeconds_) external onlyAgentOrManager {
        if (maxStalenessSeconds_ == 0) {
            revert InvalidStaleness();
        }

        _updateEthUsdBridge(maxStalenessSeconds_);
    }

    /**
     * @notice Synchronizes the ETH/USD bridge configuration with current feed registry state.
     * @dev Preserves the existing staleness threshold while updating feed metadata.
     */
    function syncEthUsdBridge() external onlyAgentOrManager {
        _updateEthUsdBridge(ethUsdBridge.maxStalenessSeconds);
    }

    /**
     * @notice Sets the feed configuration for a token.
     * @param token_ Address of the token to configure.
     * @param primaryQuote_ Primary quote denomination (USD or ETH).
     * @param maxStalenessSeconds_ Maximum allowed staleness for the price feed.
     * @param tokenDecimals_ Number of decimals for the token.
     * @param isActive_ Whether the token should be active for price queries.
     */
    function setTokenFeed(
        address token_,
        IOracleRouter.QuoteDenomination primaryQuote_,
        uint32 maxStalenessSeconds_,
        uint8 tokenDecimals_,
        bool isActive_
    ) external onlyAgentOrManager {
        _setTokenFeed(token_, primaryQuote_, maxStalenessSeconds_, tokenDecimals_, isActive_);
    }

    /**
     * @notice Sets a custom staleness override for ETH/USD bridge when used for a specific token.
     * @param token_ Address of the token to configure.
     * @param overrideSeconds_ Custom staleness threshold for this token's ETH/USD bridge usage.
     */
    function setTokenEthUsdStalenessOverride(
        address token_,
        uint32 overrideSeconds_
    ) external onlyAgentOrManager {
        if (token_ == address(0)) {
            revert InvalidTokenAddress(token_);
        }

        tokenConfig[token_].ethUsdMaxStalenessOverrideSeconds = overrideSeconds_;

        emit TokenEthUsdStalenessOverridden(token_, overrideSeconds_);
    }

    /**
     * @notice Sets the active status of a token configuration.
     * @param token_ Address of the token to configure.
     * @param isActive_ Whether the token should be active for price queries.
     */
    function setTokenActive(address token_, bool isActive_) external onlyAgentOrManager {
        if (token_ == address(0)) {
            revert InvalidTokenAddress(token_);
        }

        TokenConfig storage config = tokenConfig[token_];

        if (config.isActive == isActive_) {
            revert TokenStateUnchanged(token_, config.isActive);
        }

        if (isActive_) {
            if (config.tokenDecimals == 0) {
                revert TokenNotConfigured(token_);
            }
        }

        config.isActive = isActive_;
        emit TokenActiveUpdated(token_, isActive_);
    }

    /**
     * @notice Synchronizes a token's feed configuration with current feed registry state.
     * @param token_ Address of the token to synchronize.
     */
    function syncTokenFeed(address token_) external onlyAgentOrManager {
        TokenConfig storage config = tokenConfig[token_];

        if (config.tokenDecimals == 0) {
            revert TokenNotConfigured(token_);
        }

        address quote;
        if (config.primaryQuote == IOracleRouter.QuoteDenomination.USD) {
            quote = USD_DENOMINATION;
        } else {
            quote = ETH_DENOMINATION;
        }

        (
            address aggregator,
            uint8 decimals,
            uint128 scaleNumerator,
            uint128 scaleDenominator
        ) = _resolveFeedAndScale(token_, quote);

        FeedConfig storage primaryFeed = config.primaryFeed;
        primaryFeed.aggregator = aggregator;
        primaryFeed.aggregatorDecimals = decimals;
        primaryFeed.scaleNumerator = scaleNumerator;
        primaryFeed.scaleDenominator = scaleDenominator;

        emit TokenConfigured(
            token_,
            config.primaryQuote,
            aggregator,
            decimals,
            primaryFeed.maxStalenessSeconds,
            config.tokenDecimals,
            scaleNumerator,
            scaleDenominator,
            config.isActive
        );
    }

    // ==================== External View Functions ====================

    /**
     * @notice Gets USD prices for two tokens.
     * @param baseToken_ Address of the base token.
     * @param quoteToken_ Address of the quote token.
     * @return baseUsdPrice USD price of the base token.
     * @return quoteUsdPrice USD price of the quote token.
     */
    function getUsdPrices(
        address baseToken_,
        address quoteToken_
    ) external view returns (uint256 baseUsdPrice, uint256 quoteUsdPrice) {
        return _getUsdPrices(baseToken_, quoteToken_);
    }

    /**
     * @notice Gets prices and decimal places for two tokens in the requested quote denomination.
     * @dev Tokens can have different primary quote denominations (USD or ETH). If a token's
     *      primary quote doesn't match the requested quote, the price will be bridged through
     *      ETH/USD to convert to the requested denomination.
     * @param baseToken_ Address of the base token.
     * @param quoteToken_ Address of the quote token.
     * @param quote_ Requested quote denomination (USD or ETH) for the returned prices.
     * @return basePrice Price of the base token in the requested quote (normalized to PRICE_UNIT).
     * @return quotePrice Price of the quote token in the requested quote (normalized to PRICE_UNIT).
     * @return baseTokenDecimals Number of decimals for the base token.
     * @return quoteTokenDecimals Number of decimals for the quote token.
     */
    function getPricesAndDecimals(
        address baseToken_,
        address quoteToken_,
        IOracleRouter.QuoteDenomination quote_
    )
        external
        view
        returns (
            uint256 basePrice,
            uint256 quotePrice,
            uint8 baseTokenDecimals,
            uint8 quoteTokenDecimals
        )
    {
        TokenConfig storage baseConfig = tokenConfig[baseToken_];
        baseTokenDecimals = baseConfig.tokenDecimals;

        if (!baseConfig.isActive || baseTokenDecimals == 0) {
            revert TokenNotConfigured(baseToken_);
        }

        TokenConfig storage quoteConfig = tokenConfig[quoteToken_];
        quoteTokenDecimals = quoteConfig.tokenDecimals;

        if (!quoteConfig.isActive || quoteTokenDecimals == 0) {
            revert TokenNotConfigured(quoteToken_);
        }

        BridgeCache memory sharedBridge = _sharedBridgeIfSameCap(
            baseConfig.primaryQuote != quote_,
            quoteConfig.primaryQuote != quote_,
            baseConfig,
            quoteConfig
        );

        // Get prices in the requested quote denomination, bridging through ETH/USD if needed
        basePrice = _getPriceInQuote(baseToken_, baseConfig, quote_, sharedBridge);
        quotePrice = _getPriceInQuote(quoteToken_, quoteConfig, quote_, sharedBridge);
    }

    /**
     * @notice Checks if the ETH/USD bridge configuration is synchronized with the feed registry.
     * @return True if the bridge configuration matches the current feed registry state.
     */
    function isBridgeInSync() external view returns (bool) {
        (address aggregator, uint8 decimals) = _currentFeedMeta(ETH_DENOMINATION, USD_DENOMINATION);
        FeedConfig storage bridge = ethUsdBridge;

        return (aggregator == bridge.aggregator && decimals == bridge.aggregatorDecimals);
    }

    /**
     * @notice Checks if a token's feed configuration is synchronized with the feed registry.
     * @param token_ Address of the token to check.
     * @return True if the token configuration matches the current feed registry state.
     */
    function isFeedInSync(address token_) external view returns (bool) {
        TokenConfig storage configEntry = tokenConfig[token_];

        if (configEntry.tokenDecimals == 0) {
            return false;
        }

        address quote;
        if (configEntry.primaryQuote == IOracleRouter.QuoteDenomination.USD) {
            quote = USD_DENOMINATION;
        } else {
            quote = ETH_DENOMINATION;
        }

        (address aggregator, uint8 decimals) = _currentFeedMeta(token_, quote);

        return (aggregator == configEntry.primaryFeed.aggregator &&
            decimals == configEntry.primaryFeed.aggregatorDecimals);
    }

    // ==================== Internal Functions ====================

    /**
     * @dev Updates ETH/USD bridge configuration. Consolidates logic for setEthUsdBridge and syncEthUsdBridge.
     * @param maxStalenessSeconds_ Maximum allowed staleness for ETH/USD price feed.
     */
    function _updateEthUsdBridge(uint32 maxStalenessSeconds_) internal {
        (
            address aggregator,
            uint8 decimals,
            uint128 scaleNumerator,
            uint128 scaleDenominator
        ) = _resolveFeedAndScale(ETH_DENOMINATION, USD_DENOMINATION);

        ethUsdBridge = FeedConfig({
            aggregator: aggregator,
            maxStalenessSeconds: maxStalenessSeconds_,
            aggregatorDecimals: decimals,
            scaleNumerator: scaleNumerator,
            scaleDenominator: scaleDenominator
        });

        emit EthUsdBridgeConfigured(
            aggregator,
            decimals,
            maxStalenessSeconds_,
            scaleNumerator,
            scaleDenominator
        );
    }

    /**
     * @dev Gets USD price for a token, optionally reusing a shared ETH/USD bridge price.
     * @param token_ Address of the token to price.
     * @param config_ Token configuration.
     * @param sharedBridge_ Cached ETH/USD bridge price and cap (if available).
     * @return price USD price of the token, normalized to PRICE_UNIT.
     */
    function _getUsdPrice(
        address token_,
        TokenConfig storage config_,
        BridgeCache memory sharedBridge_
    ) internal view returns (uint256 price) {
        if (!config_.isActive || config_.tokenDecimals == 0) {
            revert TokenNotConfigured(token_);
        }

        return
            _getPriceInQuote(token_, config_, IOracleRouter.QuoteDenomination.USD, sharedBridge_);
    }

    /**
     * @dev Gets USD prices for two tokens with gas optimization for shared ETH/USD bridge.
     * When both tokens are ETH-quoted with same staleness cap, fetches ETH/USD once.
     */
    function _getUsdPrices(
        address baseToken_,
        address quoteToken_
    ) internal view returns (uint256 baseUsdPrice, uint256 quoteUsdPrice) {
        TokenConfig storage baseConfig = tokenConfig[baseToken_];
        TokenConfig storage quoteConfig = tokenConfig[quoteToken_];

        BridgeCache memory sharedBridge = _sharedBridgeIfSameCap(
            baseConfig.primaryQuote == IOracleRouter.QuoteDenomination.ETH,
            quoteConfig.primaryQuote == IOracleRouter.QuoteDenomination.ETH,
            baseConfig,
            quoteConfig
        );

        baseUsdPrice = _getUsdPrice(baseToken_, baseConfig, sharedBridge);
        quoteUsdPrice = _getUsdPrice(quoteToken_, quoteConfig, sharedBridge);
    }

    function _sharedBridgeIfSameCap(
        bool firstNeedsBridge_,
        bool secondNeedsBridge_,
        TokenConfig storage firstConfig_,
        TokenConfig storage secondConfig_
    ) internal view returns (BridgeCache memory cache) {
        if (!firstNeedsBridge_ || !secondNeedsBridge_) {
            return cache;
        }

        uint32 firstCap = _effectiveEthUsdStaleness(firstConfig_);
        uint32 secondCap = _effectiveEthUsdStaleness(secondConfig_);

        if (firstCap != secondCap) {
            return cache;
        }

        uint256 price = _readEthUsdWithCap(firstCap);

        if (price == 0) {
            return cache;
        }

        cache = BridgeCache({price: price, capSeconds: firstCap});
    }

    function _readEthUsdWithCap(uint32 capSeconds_) internal view returns (uint256) {
        FeedConfig storage bridge = ethUsdBridge;

        if (bridge.aggregatorDecimals == 0) {
            revert EthUsdBridgeMissing();
        }

        FeedConfig memory bridgeCopy = bridge;
        bridgeCopy.maxStalenessSeconds = capSeconds_;

        return _readNormalizedPrice(ETH_DENOMINATION, USD_DENOMINATION, bridgeCopy);
    }

    function _effectiveEthUsdStaleness(TokenConfig storage config) internal view returns (uint32) {
        uint32 overrideSeconds = config.ethUsdMaxStalenessOverrideSeconds;
        uint32 maxStaleness = ethUsdBridge.maxStalenessSeconds;

        if (overrideSeconds == 0) {
            return maxStaleness;
        }

        if (overrideSeconds < maxStaleness) {
            return overrideSeconds;
        } else {
            return maxStaleness;
        }
    }

    function _getPriceInQuote(
        address token_,
        TokenConfig storage config_,
        IOracleRouter.QuoteDenomination requestedQuote_,
        BridgeCache memory sharedBridge_
    ) internal view returns (uint256 price) {
        // If the token's primary quote matches the requested quote, use it directly
        if (config_.primaryQuote == requestedQuote_) {
            if (requestedQuote_ == IOracleRouter.QuoteDenomination.USD) {
                return _readNormalizedPrice(token_, USD_DENOMINATION, config_.primaryFeed);
            } else {
                return _readNormalizedPrice(token_, ETH_DENOMINATION, config_.primaryFeed);
            }
        }

        // Need to bridge through ETH/USD
        // Get the token's price in its primary quote
        uint256 tokenInPrimaryQuote;
        if (config_.primaryQuote == IOracleRouter.QuoteDenomination.USD) {
            tokenInPrimaryQuote = _readNormalizedPrice(
                token_,
                USD_DENOMINATION,
                config_.primaryFeed
            );
        } else {
            tokenInPrimaryQuote = _readNormalizedPrice(
                token_,
                ETH_DENOMINATION,
                config_.primaryFeed
            );
        }

        // Get ETH/USD price for bridging
        uint32 cap = _effectiveEthUsdStaleness(config_);
        uint256 ethUsdPrice;

        if (sharedBridge_.price != 0 && sharedBridge_.capSeconds == cap) {
            ethUsdPrice = sharedBridge_.price;
        } else {
            ethUsdPrice = _readEthUsdWithCap(cap);
        }

        // Convert to requested quote
        if (requestedQuote_ == IOracleRouter.QuoteDenomination.USD) {
            // Token is ETH-quoted, need USD: token/ETH * ETH/USD = token/USD
            price = Math.mulDiv(tokenInPrimaryQuote, ethUsdPrice, PRICE_UNIT);
        } else {
            // Token is USD-quoted, need ETH: token/USD / ETH/USD = token/ETH
            price = Math.mulDiv(tokenInPrimaryQuote, PRICE_UNIT, ethUsdPrice);
        }
    }

    function _readNormalizedPrice(
        address baseToken_,
        address quoteToken_,
        FeedConfig memory feedConfig_
    ) internal view returns (uint256 normalizedPrice) {
        IFeedRegistry registry = IFeedRegistry(FEED_REGISTRY);

        address liveAggregator = registry.getFeed(baseToken_, quoteToken_);
        uint8 liveDecimals = registry.decimals(baseToken_, quoteToken_);

        if (
            liveAggregator != feedConfig_.aggregator ||
            liveDecimals != feedConfig_.aggregatorDecimals
        ) {
            revert FeedConfigOutOfSync(
                feedConfig_.aggregator,
                liveAggregator,
                feedConfig_.aggregatorDecimals,
                liveDecimals
            );
        }

        (uint80 roundId, int256 rawAnswer, , uint256 updatedAt, uint80 answeredInRound) = registry
            .latestRoundData(baseToken_, quoteToken_);

        if (rawAnswer <= 0) {
            revert OracleBadAnswer(feedConfig_.aggregator, rawAnswer);
        }

        if (answeredInRound < roundId) {
            revert OracleUnanswered(feedConfig_.aggregator, roundId, answeredInRound);
        }

        if (block.timestamp - updatedAt > feedConfig_.maxStalenessSeconds) {
            revert OracleStale(feedConfig_.aggregator, updatedAt);
        }

        normalizedPrice = Math.mulDiv(
            uint256(rawAnswer),
            feedConfig_.scaleNumerator,
            feedConfig_.scaleDenominator
        );

        if (normalizedPrice == 0) {
            revert OracleQuantizedToZero(feedConfig_.aggregator, liveDecimals, PRICE_DECIMALS);
        }
    }

    function _setTokenFeed(
        address token_,
        IOracleRouter.QuoteDenomination primaryQuote_,
        uint32 maxStalenessSeconds_,
        uint8 tokenDecimals_,
        bool isActive_
    ) internal {
        if (token_ == address(0)) {
            revert InvalidTokenAddress(token_);
        }

        if (maxStalenessSeconds_ == 0) {
            revert InvalidStaleness();
        }

        uint8 erc20Decimals;
        if (tokenDecimals_ != 0) {
            erc20Decimals = tokenDecimals_;
        } else {
            erc20Decimals = IERC20Metadata(token_).decimals();
        }

        if (erc20Decimals == 0 || erc20Decimals > MAX_DECIMALS) {
            revert InvalidTokenDecimals();
        }

        if (tokenDecimals_ != 0) {
            uint8 onchain = IERC20Metadata(token_).decimals();
            if (onchain != erc20Decimals) {
                revert TokenDecimalsMismatch(onchain, erc20Decimals);
            }
        }

        address quote;
        if (primaryQuote_ == IOracleRouter.QuoteDenomination.USD) {
            quote = USD_DENOMINATION;
        } else {
            quote = ETH_DENOMINATION;
        }

        (
            address aggregator,
            uint8 feedDecimals,
            uint128 scaleNumerator,
            uint128 scaleDenominator
        ) = _resolveFeedAndScale(token_, quote);

        tokenConfig[token_] = TokenConfig({
            primaryQuote: primaryQuote_,
            primaryFeed: FeedConfig({
                aggregator: aggregator,
                maxStalenessSeconds: maxStalenessSeconds_,
                aggregatorDecimals: feedDecimals,
                scaleNumerator: scaleNumerator,
                scaleDenominator: scaleDenominator
            }),
            tokenDecimals: erc20Decimals,
            isActive: isActive_,
            ethUsdMaxStalenessOverrideSeconds: 0
        });

        emit TokenConfigured(
            token_,
            primaryQuote_,
            aggregator,
            feedDecimals,
            maxStalenessSeconds_,
            erc20Decimals,
            scaleNumerator,
            scaleDenominator,
            isActive_
        );
    }

    function _resolveFeedAndScale(
        address baseToken_,
        address quoteToken_
    )
        internal
        view
        returns (
            address aggregator,
            uint8 decimals,
            uint128 scaleNumerator,
            uint128 scaleDenominator
        )
    {
        IFeedRegistry registry = IFeedRegistry(FEED_REGISTRY);

        aggregator = registry.getFeed(baseToken_, quoteToken_);

        if (aggregator == address(0)) {
            revert FeedMissing(baseToken_, quoteToken_);
        }

        decimals = registry.decimals(baseToken_, quoteToken_);

        if (decimals == 0 || decimals > MAX_DECIMALS) {
            revert InvalidAggregatorDecimals();
        }

        (scaleNumerator, scaleDenominator) = _computeScaleFactors(decimals);
    }

    function _currentFeedMeta(
        address baseToken_,
        address quoteToken_
    ) internal view returns (address aggregator, uint8 decimals) {
        IFeedRegistry registry = IFeedRegistry(FEED_REGISTRY);

        aggregator = registry.getFeed(baseToken_, quoteToken_);
        decimals = registry.decimals(baseToken_, quoteToken_);
    }

    function _computeScaleFactors(
        uint8 feedDecimals_
    ) internal view returns (uint128 numerator, uint128 denominator) {
        if (feedDecimals_ == PRICE_DECIMALS) {
            return (1, 1);
        }

        if (feedDecimals_ < PRICE_DECIMALS) {
            uint8 upDiff = PRICE_DECIMALS - feedDecimals_;

            if (upDiff > MAX_DECIMALS) {
                revert InvalidAggregatorDecimals();
            }

            unchecked {
                return (uint128(10 ** upDiff), 1);
            }
        }

        uint8 downDiff = feedDecimals_ - PRICE_DECIMALS;

        if (downDiff > MAX_DECIMALS) {
            revert InvalidAggregatorDecimals();
        }

        unchecked {
            return (1, uint128(10 ** downDiff));
        }
    }
}
