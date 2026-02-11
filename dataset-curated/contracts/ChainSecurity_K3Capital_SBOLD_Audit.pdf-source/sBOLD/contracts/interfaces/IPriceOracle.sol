// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title IPriceOracle
/// @notice PriceOracle interface.
interface IPriceOracle {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidMaxStalenessUpperBound();

    error InvalidMaxStaleness();

    error InvalidMaxConfWidthLowerBound();

    error InvalidFeed();

    error InvalidBaseDecimals();

    error TooStalePrice();

    error TooAheadPrice();

    error InvalidPrice();

    error InvalidPriceExponent();

    error DuplicateFeed();

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if the `base` token is supported.
    /// @param base The token that is being priced.
    /// @return The boolean if the token is supported.
    function isBaseSupported(address base) external view returns (bool);

    /// @notice Fetch the latest price and transform it to a quote.
    /// @param inAmount The amount of `base` to convert.
    /// @return outAmount The amount of `quote` that is equivalent to `inAmount` of `base`.
    function getQuote(uint256 inAmount, address base) external view returns (uint256 outAmount);
}
