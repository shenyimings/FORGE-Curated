// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IOracleRouter} from "../interfaces/IOracleRouter.sol";

/**
 * @title OracleRouterStub
 * @dev Stub contract for testing AmountConverter zero price errors.
 *      Allows setting prices to zero to test PriceFromUsdZero, PriceToUsdZero, etc.
 */
contract OracleRouterStub is IOracleRouter {
    address public immutable FEED_REGISTRY;
    uint128 public constant MAX_DECIMALS = 38;

    struct PriceConfig {
        uint256 basePrice;
        uint256 quotePrice;
        uint8 baseTokenDecimals;
        uint8 quoteTokenDecimals;
    }

    mapping(address => mapping(address => mapping(QuoteDenomination => PriceConfig)))
        public priceConfigs;

    constructor(address, uint8, address feedRegistry_) {
        FEED_REGISTRY = feedRegistry_;
    }

    function setPricesAndDecimals(
        address baseToken_,
        address quoteToken_,
        QuoteDenomination quote_,
        uint256 basePrice_,
        uint256 quotePrice_,
        uint8 baseTokenDecimals_,
        uint8 quoteTokenDecimals_
    ) external {
        priceConfigs[baseToken_][quoteToken_][quote_] = PriceConfig({
            basePrice: basePrice_,
            quotePrice: quotePrice_,
            baseTokenDecimals: baseTokenDecimals_,
            quoteTokenDecimals: quoteTokenDecimals_
        });
    }

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
        )
    {
        PriceConfig memory config = priceConfigs[baseToken_][quoteToken_][quote_];
        return (
            config.basePrice,
            config.quotePrice,
            config.baseTokenDecimals,
            config.quoteTokenDecimals
        );
    }

    // Stub implementations for interface compliance (not used in tests)
    function getUsdPrices(address, address) external pure returns (uint256, uint256) {
        revert("Not implemented in stub");
    }

    function setEthUsdBridge(uint32) external pure {
        revert("Not implemented in stub");
    }

    function syncEthUsdBridge() external pure {
        revert("Not implemented in stub");
    }

    function setTokenFeed(address, QuoteDenomination, uint32, uint8, bool) external pure {
        revert("Not implemented in stub");
    }

    function setTokenEthUsdStalenessOverride(address, uint32) external pure {
        revert("Not implemented in stub");
    }

    function setTokenActive(address, bool) external pure {
        revert("Not implemented in stub");
    }

    function isBridgeInSync() external pure returns (bool) {
        return true;
    }

    function isFeedInSync(address) external pure returns (bool) {
        return true;
    }

    function syncTokenFeed(address) external pure {
        revert("Not implemented in stub");
    }
}
