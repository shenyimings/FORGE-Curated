// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IPriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";

interface NestedPriceFeedWithSingleUnderlying is IPriceFeed {
    function priceFeed() external view returns (address);
}

interface NestedPriceFeedWithMultipleUnderlyings is IPriceFeed {
    function priceFeed0() external view returns (address);
    function priceFeed1() external view returns (address);
    function priceFeed2() external view returns (address);
    function priceFeed3() external view returns (address);
    function priceFeed4() external view returns (address);
    function priceFeed5() external view returns (address);
    function priceFeed6() external view returns (address);
    function priceFeed7() external view returns (address);
}

library NestedPriceFeeds {
    uint256 constant MAX_UNDERLYING_PRICE_FEEDS = 8;

    enum NestingType {
        NO_NESTING,
        SINGLE_UNDERLYING,
        MULTIPLE_UNDERLYING
    }

    function getUnderlyingFeeds(IPriceFeed priceFeed) internal view returns (address[] memory feeds) {
        NestingType nestingType = getNestingType(priceFeed);
        if (nestingType == NestingType.SINGLE_UNDERLYING) {
            feeds = getSingleUnderlyingFeed(NestedPriceFeedWithSingleUnderlying(address(priceFeed)));
        } else if (nestingType == NestingType.MULTIPLE_UNDERLYING) {
            feeds = getMultipleUnderlyingFeeds(NestedPriceFeedWithMultipleUnderlyings(address(priceFeed)));
        }
    }

    function getNestingType(IPriceFeed priceFeed) internal view returns (NestingType) {
        try NestedPriceFeedWithSingleUnderlying(address(priceFeed)).priceFeed() returns (address) {
            return NestingType.SINGLE_UNDERLYING;
        } catch {}

        try NestedPriceFeedWithMultipleUnderlyings(address(priceFeed)).priceFeed0() returns (address) {
            return NestingType.MULTIPLE_UNDERLYING;
        } catch {}

        return NestingType.NO_NESTING;
    }

    function getSingleUnderlyingFeed(NestedPriceFeedWithSingleUnderlying priceFeed)
        internal
        view
        returns (address[] memory feeds)
    {
        feeds = new address[](1);
        feeds[0] = priceFeed.priceFeed();
    }

    function getMultipleUnderlyingFeeds(NestedPriceFeedWithMultipleUnderlyings priceFeed)
        internal
        view
        returns (address[] memory feeds)
    {
        feeds = new address[](MAX_UNDERLYING_PRICE_FEEDS);
        for (uint256 i; i < MAX_UNDERLYING_PRICE_FEEDS; ++i) {
            feeds[i] = _getPriceFeedByIndex(priceFeed, i);
            if (feeds[i] == address(0)) {
                assembly {
                    mstore(feeds, i)
                }
                break;
            }
        }
    }

    function _getPriceFeedByIndex(NestedPriceFeedWithMultipleUnderlyings priceFeed, uint256 index)
        private
        view
        returns (address)
    {
        bytes4 selector;
        if (index == 0) {
            selector = priceFeed.priceFeed0.selector;
        } else if (index == 1) {
            selector = priceFeed.priceFeed1.selector;
        } else if (index == 2) {
            selector = priceFeed.priceFeed2.selector;
        } else if (index == 3) {
            selector = priceFeed.priceFeed3.selector;
        } else if (index == 4) {
            selector = priceFeed.priceFeed4.selector;
        } else if (index == 5) {
            selector = priceFeed.priceFeed5.selector;
        } else if (index == 6) {
            selector = priceFeed.priceFeed6.selector;
        } else if (index == 7) {
            selector = priceFeed.priceFeed7.selector;
        }
        (bool success, bytes memory result) = address(priceFeed).staticcall(abi.encodePacked(selector));
        if (!success || result.length == 0) return address(0);
        return abi.decode(result, (address));
    }
}
