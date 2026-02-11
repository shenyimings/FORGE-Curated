// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IOracleRouter {
    enum QuoteDenomination {
        USD,
        ETH
    }

    // Pricing reads
    function getUsdPrices(
        address baseToken_,
        address quoteToken_
    ) external view returns (uint256 baseUsdPrice, uint256 quoteUsdPrice);

    function getPricesAndDecimals(
        address baseToken_,
        address quoteToken_,
        QuoteDenomination quote_
    )
        external
        view
        returns (
            uint256 basePrice,
            uint256 quotePrice,
            uint8 baseTokenDecimals,
            uint8 quoteTokenDecimals
        );

    // Configuration (admin/manager)
    function setEthUsdBridge(uint32 maxStalenessSeconds_) external;

    function syncEthUsdBridge() external;

    function setTokenFeed(
        address token_,
        QuoteDenomination primaryQuote_,
        uint32 maxStalenessSeconds_,
        uint8 tokenDecimals_,
        bool isActive_
    ) external;

    function setTokenEthUsdStalenessOverride(address token_, uint32 overrideSeconds_) external;

    function setTokenActive(address token_, bool isActive_) external;

    function isBridgeInSync() external view returns (bool);

    function isFeedInSync(address token_) external view returns (bool);

    function syncTokenFeed(address token_) external;

    function MAX_DECIMALS() external view returns (uint128);
}
