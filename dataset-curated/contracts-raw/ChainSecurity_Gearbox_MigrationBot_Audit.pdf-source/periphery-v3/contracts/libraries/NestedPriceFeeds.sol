// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IPriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";

uint256 constant MAX_UNDERLYING_PRICE_FEEDS = 8;

interface NestedPriceFeedWithSingleUnderlying is IPriceFeed {
    function priceFeed() external view returns (address);
    function stalenessPeriod() external view returns (uint32);
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

    function stalenessPeriod0() external view returns (uint32);
    function stalenessPeriod1() external view returns (uint32);
    function stalenessPeriod2() external view returns (uint32);
    function stalenessPeriod3() external view returns (uint32);
    function stalenessPeriod4() external view returns (uint32);
    function stalenessPeriod5() external view returns (uint32);
    function stalenessPeriod6() external view returns (uint32);
    function stalenessPeriod7() external view returns (uint32);
}

library NestedPriceFeeds {
    enum NestingType {
        NO_NESTING,
        SINGLE_UNDERLYING,
        MULTIPLE_UNDERLYING
    }

    function getUnderlyingFeeds(IPriceFeed priceFeed)
        internal
        view
        returns (address[] memory feeds, uint32[] memory stalenessPeriods)
    {
        NestingType nestingType = getNestingType(priceFeed);
        if (nestingType == NestingType.SINGLE_UNDERLYING) {
            (feeds, stalenessPeriods) = getSingleUnderlyingFeed(NestedPriceFeedWithSingleUnderlying(address(priceFeed)));
        } else if (nestingType == NestingType.MULTIPLE_UNDERLYING) {
            (feeds, stalenessPeriods) =
                getMultipleUnderlyingFeeds(NestedPriceFeedWithMultipleUnderlyings(address(priceFeed)));
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
        returns (address[] memory feeds, uint32[] memory stalenessPeriods)
    {
        feeds = new address[](1);
        stalenessPeriods = new uint32[](1);
        (feeds[0], stalenessPeriods[0]) = (priceFeed.priceFeed(), priceFeed.stalenessPeriod());
    }

    function getMultipleUnderlyingFeeds(NestedPriceFeedWithMultipleUnderlyings priceFeed)
        internal
        view
        returns (address[] memory feeds, uint32[] memory stalenessPeriods)
    {
        feeds = new address[](MAX_UNDERLYING_PRICE_FEEDS);
        stalenessPeriods = new uint32[](MAX_UNDERLYING_PRICE_FEEDS);
        for (uint256 i; i < MAX_UNDERLYING_PRICE_FEEDS; ++i) {
            feeds[i] = _getPriceFeedByIndex(priceFeed, i);
            if (feeds[i] == address(0)) {
                assembly {
                    mstore(feeds, i)
                    mstore(stalenessPeriods, i)
                }
                break;
            }
            stalenessPeriods[i] = _getStalenessPeriodByIndex(priceFeed, i);
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

    function _getStalenessPeriodByIndex(NestedPriceFeedWithMultipleUnderlyings priceFeed, uint256 index)
        private
        view
        returns (uint32)
    {
        bytes4 selector;
        if (index == 0) {
            selector = priceFeed.stalenessPeriod0.selector;
        } else if (index == 1) {
            selector = priceFeed.stalenessPeriod1.selector;
        } else if (index == 2) {
            selector = priceFeed.stalenessPeriod2.selector;
        } else if (index == 3) {
            selector = priceFeed.stalenessPeriod3.selector;
        } else if (index == 4) {
            selector = priceFeed.stalenessPeriod4.selector;
        } else if (index == 5) {
            selector = priceFeed.stalenessPeriod5.selector;
        } else if (index == 6) {
            selector = priceFeed.stalenessPeriod6.selector;
        } else if (index == 7) {
            selector = priceFeed.stalenessPeriod7.selector;
        }
        (bool success, bytes memory result) = address(priceFeed).staticcall(abi.encodePacked(selector));
        if (!success || result.length == 0) return 0;
        return abi.decode(result, (uint32));
    }
}
