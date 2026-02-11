// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IPriceOracleV3, PriceFeedParams} from "@gearbox-protocol/core-v3/contracts/interfaces/IPriceOracleV3.sol";
import {IPriceFeed, IUpdatablePriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

import {IPriceFeedCompressor} from "../interfaces/IPriceFeedCompressor.sol";

import {BaseLib} from "../libraries/BaseLib.sol";
import {ILegacyPriceFeed, ILegacyPriceOracle, Legacy} from "../libraries/Legacy.sol";
import {AP_PRICE_FEED_COMPRESSOR} from "../libraries/Literals.sol";
import {NestedPriceFeeds} from "../libraries/NestedPriceFeeds.sol";

import {BPTWeightedPriceFeedSerializer} from "../serializers/oracles/BPTWeightedPriceFeedSerializer.sol";
import {BoundedPriceFeedSerializer} from "../serializers/oracles/BoundedPriceFeedSerializer.sol";
import {LPPriceFeedSerializer} from "../serializers/oracles/LPPriceFeedSerializer.sol";
import {PendleTWAPPTPriceFeedSerializer} from "../serializers/oracles/PendleTWAPPTPriceFeedSerializer.sol";
import {PythPriceFeedSerializer} from "../serializers/oracles/PythPriceFeedSerializer.sol";
import {RedstonePriceFeedSerializer} from "../serializers/oracles/RedstonePriceFeedSerializer.sol";

import {BaseParams} from "../types/BaseState.sol";
import {MarketFilter} from "../types/Filters.sol";
import {PriceFeedAnswer, PriceFeedMapEntry, PriceFeedTreeNode, PriceOracleState} from "../types/PriceOracleState.sol";

import {BaseCompressor} from "./BaseCompressor.sol";

/// @title  Price feed compressor
/// @notice Allows to fetch all useful data from price oracle in a single call
/// @dev    The contract is not gas optimized and is thus not recommended for on-chain use
contract PriceFeedCompressor is BaseCompressor, IPriceFeedCompressor {
    using BaseLib for address;
    using NestedPriceFeeds for IPriceFeed;

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_PRICE_FEED_COMPRESSOR;

    /// @notice Map of state serializers for different price feed types
    /// @dev    Serializers only apply to feeds that don't implement `IStateSerializer` themselves
    mapping(bytes32 priceFeedType => address) public serializers;

    /// @notice Constructor
    /// @param  addressProvider_ Address provider contract address
    constructor(address addressProvider_) BaseCompressor(addressProvider_) {
        // these types can be serialized as generic LP price feeds
        address lpSerializer = address(new LPPriceFeedSerializer());
        serializers["PRICE_FEED::BALANCER_STABLE"] = lpSerializer;
        serializers["PRICE_FEED::CURVE_STABLE"] = lpSerializer;
        serializers["PRICE_FEED::CURVE_CRYPTO"] = lpSerializer;
        serializers["PRICE_FEED::CURVE_USD"] = lpSerializer;
        serializers["PRICE_FEED::ERC4626"] = lpSerializer;
        serializers["PRICE_FEED::MELLOW_LRT"] = lpSerializer;
        serializers["PRICE_FEED::WSTETH"] = lpSerializer;
        serializers["PRICE_FEED::YEARN"] = lpSerializer;

        // these types need special serialization
        serializers["PRICE_FEED::BALANCER_WEIGHTED"] = address(new BPTWeightedPriceFeedSerializer());
        serializers["PRICE_FEED::BOUNDED"] = address(new BoundedPriceFeedSerializer());
        serializers["PRICE_FEED::PENDLE_PT_TWAP"] = address(new PendleTWAPPTPriceFeedSerializer());
        serializers["PRICE_FEED::PYTH"] = address(new PythPriceFeedSerializer());
        serializers["PRICE_FEED::REDSTONE"] = address(new RedstonePriceFeedSerializer());
    }

    /// @notice Returns state of all price oracles matching market `filter`
    function getPriceOracles(MarketFilter memory filter)
        external
        view
        override
        returns (PriceOracleState[] memory result)
    {
        Pool[] memory pools = _getPools(filter);
        uint256 numPools = pools.length;
        result = new PriceOracleState[](numPools);
        for (uint256 i; i < numPools; ++i) {
            address priceOracle = _getPriceOracle(pools[i].addr, pools[i].configurator);
            address[] memory tokens = _getTokens(pools[i].addr);
            result[i] = getPriceOracleState(priceOracle, tokens);
        }
    }

    /// @notice Returns `priceOracle`'s state, see `PriceOracleState` for detailed description of struct fields
    function getPriceOracleState(address priceOracle) external view override returns (PriceOracleState memory) {
        // NOTE: After migration to v3.1.x governance system, all price oracles will provide `getTokens` getter.
        // Before that, however, there's no way to recover the list of tokens so it should be provided directly.
        return getPriceOracleState(priceOracle, IPriceOracleV3(priceOracle).getTokens());
    }

    /// @dev Same as the above but takes the list of tokens as argument as legacy oracle doesn't implement `getTokens`
    function getPriceOracleState(address priceOracle, address[] memory tokens)
        public
        view
        override
        returns (PriceOracleState memory result)
    {
        result.baseParams = priceOracle.getBaseParams("PRICE_ORACLE", address(0));
        result.priceFeedMap = _getPriceFeedMap(priceOracle, tokens);
        result.priceFeedTree = _getPriceFeedTree(_getPriceFeedsFromMap(result.priceFeedMap));
    }

    /// @notice Returns the price feed tree of price oracles matching market `filter`
    function loadPriceFeedTree(MarketFilter memory filter) public view override returns (PriceFeedTreeNode[] memory) {
        Pool[] memory pools = _getPools(filter);
        uint256 numPools = pools.length;
        address[] memory priceFeeds;
        for (uint256 i; i < numPools; ++i) {
            address priceOracle = _getPriceOracle(pools[i].addr, pools[i].configurator);
            address[] memory tokens = _getTokens(pools[i].addr);
            priceFeeds = _concat(priceFeeds, _getPriceFeedsFromMap(_getPriceFeedMap(priceOracle, tokens)));
        }
        return _getPriceFeedTree(priceFeeds);
    }

    /// @notice Returns the `priceFeeds` tree
    function loadPriceFeedTree(address[] memory priceFeeds) public view override returns (PriceFeedTreeNode[] memory) {
        return _getPriceFeedTree(priceFeeds);
    }

    /// @notice Returns all updatable feeds from the price feed tree of price oracles matching market `filter`
    function getUpdatablePriceFeeds(MarketFilter memory filter) external view override returns (BaseParams[] memory) {
        return _getUpdatablePriceFeedsFromTree(loadPriceFeedTree(filter));
    }

    /// @notice Returns all updatable feeds from the `priceFeeds` tree
    function getUpdatablePriceFeeds(address[] memory priceFeeds) external view override returns (BaseParams[] memory) {
        return _getUpdatablePriceFeedsFromTree(loadPriceFeedTree(priceFeeds));
    }

    // --------- //
    // INTERNALS //
    // --------- //

    /// @dev Returns the price feed map of `priceOracle` for `tokens`
    function _getPriceFeedMap(address priceOracle, address[] memory tokens)
        internal
        view
        returns (PriceFeedMapEntry[] memory priceFeedMap)
    {
        uint256 numTokens = tokens.length;
        priceFeedMap = new PriceFeedMapEntry[](2 * numTokens);
        uint256 priceFeedMapSize;
        for (uint256 i; i < 2 * numTokens; ++i) {
            address token = tokens[i % numTokens];
            bool reserve = i >= numTokens;
            (address priceFeed, uint32 stalenessPeriod) = _getPriceFeed(priceOracle, token, reserve);
            if (priceFeed == address(0)) continue;

            priceFeedMap[priceFeedMapSize++] = PriceFeedMapEntry({
                token: token,
                reserve: reserve,
                priceFeed: priceFeed,
                stalenessPeriod: stalenessPeriod
            });
        }
        // trim array to its actual size in case some tokens don't have reserve price feeds
        assembly {
            mstore(priceFeedMap, priceFeedMapSize)
        }
    }

    /// @dev Returns the `priceFeeds` tree
    function _getPriceFeedTree(address[] memory priceFeeds)
        internal
        view
        returns (PriceFeedTreeNode[] memory priceFeedTree)
    {
        uint256 len = priceFeeds.length;
        uint256 priceFeedTreeSize;
        for (uint256 i; i < len; ++i) {
            priceFeedTreeSize += _getPriceFeedTreeSize(priceFeeds[i]);
        }

        priceFeedTree = new PriceFeedTreeNode[](priceFeedTreeSize);
        uint256 offset;
        for (uint256 i; i < len; ++i) {
            offset = _loadPriceFeedTree(priceFeeds[i], priceFeedTree, offset);
        }
        // trim array to its actual size in case there were duplicates
        assembly {
            mstore(priceFeedTree, offset)
        }
    }

    /// @dev Returns the list of price feeds from `priceFeedMap`
    function _getPriceFeedsFromMap(PriceFeedMapEntry[] memory priceFeedMap)
        internal
        pure
        returns (address[] memory priceFeeds)
    {
        uint256 len = priceFeedMap.length;
        priceFeeds = new address[](len);
        for (uint256 i; i < len; ++i) {
            priceFeeds[i] = priceFeedMap[i].priceFeed;
        }
    }

    /// @dev Returns the list of updatable feeds from `priceFeedTree`
    function _getUpdatablePriceFeedsFromTree(PriceFeedTreeNode[] memory priceFeedTree)
        internal
        pure
        returns (BaseParams[] memory priceFeeds)
    {
        priceFeeds = new BaseParams[](priceFeedTree.length);
        uint256 num;
        for (uint256 i; i < priceFeedTree.length; ++i) {
            if (priceFeedTree[i].updatable) priceFeeds[num++] = priceFeedTree[i].baseParams;
        }
        // trim array to its actual size
        assembly {
            mstore(priceFeeds, num)
        }
    }

    /// @dev Returns `token`'s price feed in `priceOracle`
    function _getPriceFeed(address priceOracle, address token, bool reserve) internal view returns (address, uint32) {
        if (IPriceOracleV3(priceOracle).version() < 3_10) {
            try ILegacyPriceOracle(priceOracle).priceFeedsRaw(token, reserve) returns (address priceFeed) {
                // NOTE: legacy oracle does not allow to fetch staleness period of a non-active feed
                return (priceFeed, 0);
            } catch {
                return (address(0), 0);
            }
        }
        PriceFeedParams memory params = reserve
            ? IPriceOracleV3(priceOracle).reservePriceFeedParams(token)
            : IPriceOracleV3(priceOracle).priceFeedParams(token);
        return (params.priceFeed, params.stalenessPeriod);
    }

    /// @dev Computes the size of the `priceFeed`'s subtree (recursively)
    function _getPriceFeedTreeSize(address priceFeed) internal view returns (uint256 size) {
        size = 1;
        (address[] memory underlyingFeeds,) = IPriceFeed(priceFeed).getUnderlyingFeeds();
        for (uint256 i; i < underlyingFeeds.length; ++i) {
            size += _getPriceFeedTreeSize(underlyingFeeds[i]);
        }
    }

    /// @dev Loads `priceFeed`'s subtree (recursively)
    function _loadPriceFeedTree(address priceFeed, PriceFeedTreeNode[] memory priceFeedTree, uint256 offset)
        internal
        view
        returns (uint256)
    {
        // duplicates are possible since price feed can be in `priceFeedMap` for more than one (token, reserve) pair
        // or serve as an underlying in more than one nested feed, and the whole subtree can be skipped in this case
        for (uint256 i; i < offset; ++i) {
            if (priceFeedTree[i].baseParams.addr == priceFeed) return offset;
        }

        PriceFeedTreeNode memory node = _getPriceFeedTreeNode(priceFeed);
        priceFeedTree[offset++] = node;
        for (uint256 i; i < node.underlyingFeeds.length; ++i) {
            offset = _loadPriceFeedTree(node.underlyingFeeds[i], priceFeedTree, offset);
        }
        return offset;
    }

    /// @dev Returns price feed tree node, see `PriceFeedTreeNode` for detailed description of struct fields
    function _getPriceFeedTreeNode(address priceFeed) internal view returns (PriceFeedTreeNode memory data) {
        try IVersion(priceFeed).contractType() returns (bytes32 contractType_) {
            data.baseParams.contractType = contractType_;
        } catch {
            try ILegacyPriceFeed(priceFeed).priceFeedType() returns (uint8 priceFeedType) {
                data.baseParams.contractType = Legacy.getPriceFeedType(priceFeedType);
            } catch {
                data.baseParams.contractType = "PRICE_FEED::EXTERNAL";
            }
        }

        data.baseParams =
            priceFeed.getBaseParams(data.baseParams.contractType, serializers[data.baseParams.contractType]);

        data.decimals = IPriceFeed(priceFeed).decimals();

        try IPriceFeed(priceFeed).skipPriceCheck() returns (bool skipCheck) {
            data.skipCheck = skipCheck;
        } catch {}

        try IPriceFeed(priceFeed).description() returns (string memory description) {
            data.description = description;
        } catch {}

        try IUpdatablePriceFeed(priceFeed).updatable() returns (bool updatable) {
            data.updatable = updatable;
        } catch {}

        (data.underlyingFeeds, data.underlyingStalenessPeriods) = IPriceFeed(priceFeed).getUnderlyingFeeds();

        try IPriceFeed(priceFeed).latestRoundData() returns (uint80, int256 price, uint256, uint256 updatedAt, uint80) {
            data.answer = PriceFeedAnswer({price: price, updatedAt: updatedAt, success: true});
        } catch {}
    }

    /// @dev Concatenates two address arrays
    function _concat(address[] memory arr1, address[] memory arr2) internal pure returns (address[] memory arr) {
        uint256 len1 = arr1.length;
        uint256 len2 = arr2.length;
        arr = new address[](len1 + len2);
        for (uint256 i; i < len1; ++i) {
            arr[i] = arr1[i];
        }
        for (uint256 i; i < len2; ++i) {
            arr[len1 + i] = arr2[i];
        }
    }
}
