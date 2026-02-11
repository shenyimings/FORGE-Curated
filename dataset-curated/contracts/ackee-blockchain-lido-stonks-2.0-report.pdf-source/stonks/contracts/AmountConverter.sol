// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IAmountConverter} from "./interfaces/IAmountConverter.sol";
import {IOracleRouter} from "./interfaces/IOracleRouter.sol";

/**
 * @title AmountConverter
 * @dev This contract provides functionality for converting the amount
 *      of Token A into the amount of Token B based on oracle router prices.
 */
contract AmountConverter is IAmountConverter {
    // ==================== Immutables ====================

    /// @notice Oracle router contract used for fetching token prices.
    IOracleRouter public immutable ORACLE_ROUTER;
    /// @notice If true, uses ETH-denominated prices directly (gas optimized for ETH-quoted pairs).
    ///         If false, uses USD prices (supports mixed denominations).
    bool public immutable USE_ETH_ANCHOR;
    /// @notice Cached router max decimals to avoid an external call per quote.
    uint8 public immutable ROUTER_MAX_DECIMALS;

    // ==================== Storage Variables ====================

    /// @notice Mapping indicating which tokens are allowed to be sold.
    mapping(address tokenToSell => bool allowed) public allowedTokensToSell;
    /// @notice Mapping indicating which tokens are allowed to be bought.
    mapping(address tokenToBuy => bool allowed) public allowedTokensToBuy;

    // ==================== Events ====================

    event AllowedTokenToSellAdded(address token);
    event AllowedTokenToBuyAdded(address token);

    // ==================== Errors ====================

    error InvalidOracleRouterAddress(address oracleRouter);
    error InvalidAllowedTokenToBuy(address allowedTokenToBuy);
    error InvalidAllowedTokenToSell(address allowedTokenToSell);
    error InvalidAmount(uint256 amount);
    error InvalidTokensToSellArrayLength();
    error InvalidTokensToBuyArrayLength();
    error SellTokenNotAllowed(address tokenFrom);
    error BuyTokenNotAllowed(address tokenTo);
    error TokensCannotBeSame();
    error InvalidDecimalsDifference(uint8 diff);
    error AmountFromTooLarge(uint256 amount);
    error ScaledPriceOverflow();
    error PriceFromUsdZero();
    error PriceToUsdZero();
    error PriceFromEthZero();
    error PriceToEthZero();

    // ==================== Constructor ====================

    /**
     * @param oracleRouter_ Oracle router for price fetching
     * @param allowedTokensToSell_ List of addresses which are allowed to use as sell tokens
     * @param allowedTokensToBuy_ List of addresses of tokens that are allowed to be bought
     * @param useEthAnchor_ If true, prices are requested in ETH (tokens already quoted in ETH avoid a bridge, others are automatically bridged).
     *                      If false, prices are requested in USD (router handles bridging as needed).
     */
    constructor(
        address oracleRouter_,
        address[] memory allowedTokensToSell_,
        address[] memory allowedTokensToBuy_,
        bool useEthAnchor_
    ) {
        uint256 allowedTokensToSellLength = allowedTokensToSell_.length;
        uint256 allowedTokensToBuyLength = allowedTokensToBuy_.length;

        if (oracleRouter_ == address(0)) {
            revert InvalidOracleRouterAddress(oracleRouter_);
        }

        if (allowedTokensToSellLength == 0) {
            revert InvalidTokensToSellArrayLength();
        }

        if (allowedTokensToBuyLength == 0) {
            revert InvalidTokensToBuyArrayLength();
        }

        ORACLE_ROUTER = IOracleRouter(oracleRouter_);
        USE_ETH_ANCHOR = useEthAnchor_;
        ROUTER_MAX_DECIMALS = uint8(IOracleRouter(oracleRouter_).MAX_DECIMALS());

        for (uint256 i; i < allowedTokensToBuyLength; ) {
            address token = allowedTokensToBuy_[i];

            if (token == address(0)) {
                revert InvalidAllowedTokenToBuy(token);
            }

            allowedTokensToBuy[token] = true;

            emit AllowedTokenToBuyAdded(token);

            unchecked {
                ++i;
            }
        }

        for (uint256 i; i < allowedTokensToSellLength; ) {
            address token = allowedTokensToSell_[i];

            if (token == address(0)) {
                revert InvalidAllowedTokenToSell(token);
            }

            allowedTokensToSell[token] = true;

            emit AllowedTokenToSellAdded(token);

            unchecked {
                ++i;
            }
        }
    }

    // ==================== External View Functions ====================

    /**
     * @notice Calculates the expected amount of `tokenTo_` that one would receive for a given amount of `tokenFrom_`.
     * @dev Uses the oracle router to get the current price relation between tokens and handles decimal scaling.
     *
     * @param tokenFrom_ The address of the token being sold.
     * @param tokenTo_ The address of the token being bought.
     * @param amountFrom_ The amount of `tokenFrom_` that is being sold.
     * @return expectedOutputAmount The expected amount of `tokenTo_` that will be received.
     */
    function getExpectedOut(
        address tokenFrom_,
        address tokenTo_,
        uint256 amountFrom_
    ) external view returns (uint256 expectedOutputAmount) {
        if (tokenFrom_ == tokenTo_) {
            revert TokensCannotBeSame();
        }

        if (amountFrom_ == 0) {
            revert InvalidAmount(amountFrom_);
        }

        if (amountFrom_ > type(uint128).max) {
            revert AmountFromTooLarge(amountFrom_);
        }

        if (!allowedTokensToSell[tokenFrom_]) {
            revert SellTokenNotAllowed(tokenFrom_);
        }

        if (!allowedTokensToBuy[tokenTo_]) {
            revert BuyTokenNotAllowed(tokenTo_);
        }

        uint256 priceFrom;
        uint256 priceTo;
        uint8 decimalsOfSellToken;
        uint8 decimalsOfBuyToken;

        IOracleRouter.QuoteDenomination quote;

        if (USE_ETH_ANCHOR) {
            quote = IOracleRouter.QuoteDenomination.ETH;
        } else {
            quote = IOracleRouter.QuoteDenomination.USD;
        }

        (priceFrom, priceTo, decimalsOfSellToken, decimalsOfBuyToken) = ORACLE_ROUTER
            .getPricesAndDecimals(tokenFrom_, tokenTo_, quote);

        if (priceFrom == 0) {
            if (USE_ETH_ANCHOR) {
                revert PriceFromEthZero();
            } else {
                revert PriceFromUsdZero();
            }
        }

        if (priceTo == 0) {
            if (USE_ETH_ANCHOR) {
                revert PriceToEthZero();
            } else {
                revert PriceToUsdZero();
            }
        }

        bool sellHasMoreOrEqualDecimals = decimalsOfSellToken >= decimalsOfBuyToken;
        uint8 decimalsDiff;

        if (sellHasMoreOrEqualDecimals) {
            decimalsDiff = decimalsOfSellToken - decimalsOfBuyToken;
        } else {
            decimalsDiff = decimalsOfBuyToken - decimalsOfSellToken;
        }

        if (decimalsDiff > ROUTER_MAX_DECIMALS) {
            revert InvalidDecimalsDifference(decimalsDiff);
        }

        if (sellHasMoreOrEqualDecimals) {
            if (decimalsDiff == 0) {
                expectedOutputAmount = Math.mulDiv(amountFrom_, priceFrom, priceTo);
            } else {
                uint256 pow10 = 10 ** decimalsDiff;

                // Pre-multiply overflow check: ensure priceTo * pow10 won't overflow.
                if (pow10 > type(uint256).max / priceTo) {
                    revert ScaledPriceOverflow();
                }

                unchecked {
                    uint256 scaledPriceTo = priceTo * pow10;
                    expectedOutputAmount = Math.mulDiv(amountFrom_, priceFrom, scaledPriceTo);
                }
            }
        } else {
            // Scale the input first to avoid overflow on multiplication by 10**diff.
            uint256 pow10 = 10 ** decimalsDiff;
            uint256 maxAmountFromBeforeScale = type(uint256).max / pow10;

            if (amountFrom_ > maxAmountFromBeforeScale) {
                revert AmountFromTooLarge(amountFrom_);
            }

            uint256 scaledAmountFrom = amountFrom_ * pow10;
            expectedOutputAmount = Math.mulDiv(scaledAmountFrom, priceFrom, priceTo);
        }
    }
}
