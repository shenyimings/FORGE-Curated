// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {AdapterType} from "@gearbox-protocol/sdk-gov/contracts/AdapterType.sol";
import {PriceFeedType} from "@gearbox-protocol/sdk-gov/contracts/PriceFeedType.sol";

/// @dev In v3.0, adapters have custom version and type getters
interface ILegacyAdapter {
    function _gearboxAdapterVersion() external view returns (uint16);

    /// @dev Annotates `_gearboxAdapterType` as `uint8` instead of `AdapterType` enum to support future types
    function _gearboxAdapterType() external view returns (uint8);
}

/// @dev In v3.0, bot list also stores special permissions
interface ILegacyBotList {
    function getBotStatus(address bot, address creditManager, address creditAccount)
        external
        view
        returns (uint192 permissions, bool forbidden, bool hasSpecialPermissions);
}

/// @dev In v3.0, price feeds have custom type getter
interface ILegacyPriceFeed {
    /// @dev Annotates `priceFeedType` as `uint8` instead of `PriceFeedType` enum to support future types
    function priceFeedType() external view returns (uint8);
}

/// @dev In v3.0, price oracle doesn't provide `getTokens` and only allows to fetch staleness period of an active feed
interface ILegacyPriceOracle {
    /// @dev Older signature for fetching main and reserve feeds, reverts if price feed is not set
    function priceFeedsRaw(address token, bool reserve) external view returns (address);
}

library Legacy {
    function getAdapterType(uint8 adapterType) internal pure returns (bytes32) {
        if (adapterType == uint8(AdapterType.BALANCER_VAULT)) return "ADAPTER::BALANCER_VAULT";
        if (adapterType == uint8(AdapterType.BALANCER_V3_ROUTER)) return "ADAPTER::BALANCER_V3_ROUTER";
        if (adapterType == uint8(AdapterType.CAMELOT_V3_ROUTER)) return "ADAPTER::CAMELOT_V3_ROUTER";
        if (adapterType == uint8(AdapterType.CONVEX_V1_BASE_REWARD_POOL)) return "ADAPTER::CVX_V1_BASE_REWARD_POOL";
        if (adapterType == uint8(AdapterType.CONVEX_V1_BOOSTER)) return "ADAPTER::CVX_V1_BOOSTER";
        if (adapterType == uint8(AdapterType.CURVE_V1_2ASSETS)) return "ADAPTER::CURVE_V1_2ASSETS";
        if (adapterType == uint8(AdapterType.CURVE_V1_3ASSETS)) return "ADAPTER::CURVE_V1_3ASSETS";
        if (adapterType == uint8(AdapterType.CURVE_V1_4ASSETS)) return "ADAPTER::CURVE_V1_4ASSETS";
        if (adapterType == uint8(AdapterType.CURVE_STABLE_NG)) return "ADAPTER::CURVE_STABLE_NG";
        if (adapterType == uint8(AdapterType.CURVE_V1_STECRV_POOL)) return "ADAPTER::CURVE_V1_STECRV_POOL";
        if (adapterType == uint8(AdapterType.CURVE_V1_WRAPPER)) return "ADAPTER::CURVE_V1_WRAPPER";
        if (adapterType == uint8(AdapterType.DAI_USDS_EXCHANGE)) return "ADAPTER::DAI_USDS_EXCHANGE";
        if (adapterType == uint8(AdapterType.EQUALIZER_ROUTER)) return "ADAPTER::EQUALIZER_ROUTER";
        if (adapterType == uint8(AdapterType.ERC4626_VAULT)) return "ADAPTER::ERC4626_VAULT";
        if (adapterType == uint8(AdapterType.LIDO_V1)) return "ADAPTER::LIDO_V1";
        if (adapterType == uint8(AdapterType.LIDO_WSTETH_V1)) return "ADAPTER::LIDO_WSTETH_V1";
        if (adapterType == uint8(AdapterType.MELLOW_ERC4626_VAULT)) return "ADAPTER::MELLOW_ERC4626_VAULT";
        if (adapterType == uint8(AdapterType.MELLOW_LRT_VAULT)) return "ADAPTER::MELLOW_LRT_VAULT";
        if (adapterType == uint8(AdapterType.PENDLE_ROUTER)) return "ADAPTER::PENDLE_ROUTER";
        if (adapterType == uint8(AdapterType.STAKING_REWARDS)) return "ADAPTER::STAKING_REWARDS";
        if (adapterType == uint8(AdapterType.UNISWAP_V2_ROUTER)) return "ADAPTER::UNISWAP_V2_ROUTER";
        if (adapterType == uint8(AdapterType.UNISWAP_V3_ROUTER)) return "ADAPTER::UNISWAP_V3_ROUTER";
        if (adapterType == uint8(AdapterType.VELODROME_V2_ROUTER)) return "ADAPTER::VELODROME_V2_ROUTER";
        if (adapterType == uint8(AdapterType.YEARN_V2)) return "ADAPTER::YEARN_V2";
        return bytes32(0);
    }

    function getPriceFeedType(uint8 priceFeedType) internal pure returns (bytes32) {
        if (priceFeedType == uint8(PriceFeedType.BALANCER_STABLE_LP_ORACLE)) return "PRICE_FEED::BALANCER_STABLE";
        if (priceFeedType == uint8(PriceFeedType.BALANCER_WEIGHTED_LP_ORACLE)) return "PRICE_FEED::BALANCER_WEIGHTED";
        if (priceFeedType == uint8(PriceFeedType.BOUNDED_ORACLE)) return "PRICE_FEED::BOUNDED";
        if (priceFeedType == uint8(PriceFeedType.COMPOSITE_ORACLE)) return "PRICE_FEED::COMPOSITE";
        if (priceFeedType == uint8(PriceFeedType.CURVE_2LP_ORACLE)) return "PRICE_FEED::CURVE_STABLE";
        if (priceFeedType == uint8(PriceFeedType.CURVE_3LP_ORACLE)) return "PRICE_FEED::CURVE_STABLE";
        if (priceFeedType == uint8(PriceFeedType.CURVE_4LP_ORACLE)) return "PRICE_FEED::CURVE_STABLE";
        if (priceFeedType == uint8(PriceFeedType.CURVE_CRYPTO_ORACLE)) return "PRICE_FEED::CURVE_CRYPTO";
        if (priceFeedType == uint8(PriceFeedType.CURVE_USD_ORACLE)) return "PRICE_FEED::CURVE_USD";
        if (priceFeedType == uint8(PriceFeedType.ERC4626_VAULT_ORACLE)) return "PRICE_FEED::ERC4626";
        if (priceFeedType == uint8(PriceFeedType.MELLOW_LRT_ORACLE)) return "PRICE_FEED::MELLOW_LRT";
        if (priceFeedType == uint8(PriceFeedType.PENDLE_PT_TWAP_ORACLE)) return "PRICE_FEED::PENDLE_PT_TWAP";
        if (priceFeedType == uint8(PriceFeedType.PYTH_ORACLE)) return "PRICE_FEED::PYTH";
        if (priceFeedType == uint8(PriceFeedType.REDSTONE_ORACLE)) return "PRICE_FEED::REDSTONE";
        if (priceFeedType == uint8(PriceFeedType.WSTETH_ORACLE)) return "PRICE_FEED::WSTETH";
        if (priceFeedType == uint8(PriceFeedType.YEARN_ORACLE)) return "PRICE_FEED::YEARN";
        if (priceFeedType == uint8(PriceFeedType.ZERO_ORACLE)) return "PRICE_FEED::ZERO";
        return bytes32(0);
    }
}
