// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { PriceFeedManager } from "../../../src/controller/PriceFeedManager.sol";
import { IChainlinkAggregatorLike } from "../../../src/interfaces/IChainlinkAggregatorLike.sol";

import { ControllerTest } from "./Controller.t.sol";

abstract contract Controller_PriceFeedManager_Test is ControllerTest {
    address manager = makeAddr("manager");
    bytes32 managerRole;
    address asset = makeAddr("asset");
    IChainlinkAggregatorLike feed = IChainlinkAggregatorLike(makeAddr("feed"));
    uint24 heartbeat = 1 hours;

    function setUp() public virtual override {
        super.setUp();

        managerRole = controller.PRICE_FEED_MANAGER_ROLE();
        vm.prank(admin);
        controller.grantRole(managerRole, manager);
    }
}

contract Controller_PriceFeedManager_SetPriceFeed_Test is Controller_PriceFeedManager_Test {
    function testFuzz_shouldRevert_whenCallerNotManager(address caller) public {
        vm.assume(caller != manager);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        controller.setPriceFeed(asset, feed, heartbeat);
    }

    function test_shouldRevert_whenAssetIsZero() public {
        vm.prank(manager);
        vm.expectRevert(PriceFeedManager.PriceFeed_ZeroAsset.selector);
        controller.setPriceFeed(address(0), feed, heartbeat);
    }

    function test_shouldRevert_whenFeedIsZero() public {
        vm.prank(manager);
        vm.expectRevert(PriceFeedManager.PriceFeed_ZeroFeed.selector);
        controller.setPriceFeed(asset, IChainlinkAggregatorLike(address(0)), heartbeat);
    }

    function test_shouldRevert_whenHeartbeatIsZero() public {
        vm.prank(manager);
        vm.expectRevert(PriceFeedManager.PriceFeed_ZeroHeartbeat.selector);
        controller.setPriceFeed(asset, feed, 0);
    }

    function testFuzz_shouldSetPriceFeed(address _feed, uint24 _heartbeat) public {
        vm.assume(_feed != address(0));
        vm.assume(_heartbeat > 0);

        vm.prank(manager);
        controller.setPriceFeed(asset, IChainlinkAggregatorLike(_feed), _heartbeat);

        (IChainlinkAggregatorLike returnedFeed, uint24 returnedHeartbeat) = controller.priceFeeds(asset);
        assertEq(address(returnedFeed), _feed);
        assertEq(returnedHeartbeat, _heartbeat);
    }

    function test_shouldEmit_PriceFeedUpdated() public {
        address feed1 = makeAddr("feed1");
        uint24 heartbeat1 = 1 hours;
        vm.expectEmit();
        emit PriceFeedManager.PriceFeedUpdated(asset, address(0), feed1, heartbeat1);

        vm.prank(manager);
        controller.setPriceFeed(asset, IChainlinkAggregatorLike(feed1), heartbeat1);

        address feed2 = makeAddr("feed2");
        uint24 heartbeat2 = 2 hours;
        vm.expectEmit();
        emit PriceFeedManager.PriceFeedUpdated(asset, address(feed1), address(feed2), heartbeat2);

        vm.prank(manager);
        controller.setPriceFeed(asset, IChainlinkAggregatorLike(feed2), heartbeat2);
    }
}

contract Controller_PriceFeedManager_GetAssetPrice_Test is Controller_PriceFeedManager_Test {
    function _mockFeed(uint8 _decimals, int256 _price, uint256 _updatedAt) internal {
        vm.mockCall(
            address(feed), abi.encodeWithSelector(IChainlinkAggregatorLike.decimals.selector), abi.encode(_decimals)
        );
        vm.mockCall(
            address(feed),
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            abi.encode(0, _price, 0, _updatedAt, 0)
        );
    }

    function setUp() public override {
        super.setUp();

        vm.prank(manager);
        controller.setPriceFeed(asset, feed, heartbeat);

        _mockFeed(8, 1e8, block.timestamp);
    }

    function testFuzz_shouldRevert_whenFeedNotExists(address _asset) public {
        vm.assume(_asset != asset);

        vm.expectRevert(PriceFeedManager.PriceFeed_FeedNotExists.selector);
        controller.getAssetPrice(_asset);
    }

    function testFuzz_shouldRevert_whenPriceInvalid(int256 price) public {
        price = bound(price, type(int256).min, 0);

        _mockFeed(8, price, block.timestamp);

        vm.expectRevert(PriceFeedManager.PriceFeed_InvalidPrice.selector);
        controller.getAssetPrice(asset);
    }

    function test_shouldRevert_whenPriceStale() public {
        _mockFeed(8, 1e8, 10 days);

        vm.warp(10 days + heartbeat + controller.HEARTBEAT_BUFFER() + 1);

        vm.expectRevert(PriceFeedManager.PriceFeed_StalePrice.selector);
        controller.getAssetPrice(asset);
    }

    function testFuzz_shouldRevert_whenDecimalsTooHigh(uint8 decimals) public {
        decimals = uint8(bound(decimals, controller.NORMALIZED_PRICE_DECIMALS() + 1, type(uint8).max));

        _mockFeed(decimals, 1, block.timestamp);

        vm.expectRevert(PriceFeedManager.PriceFeed_DecimalsTooHigh.selector);
        controller.getAssetPrice(asset);
    }

    function testFuzz_shouldReturnNormalizedPrice(int256 price, uint8 decimals) public {
        uint8 normalizedDecimals = controller.NORMALIZED_PRICE_DECIMALS();
        decimals = uint8(bound(decimals, 0, normalizedDecimals));
        price = bound(price, 1, type(int256).max / int256(10) ** normalizedDecimals);
        _mockFeed(decimals, price, block.timestamp);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(controller.getAssetPrice(asset), uint256(price) * 10 ** (normalizedDecimals - decimals));
    }
}

contract Controller_PriceFeedManager_PriceFeedExists_Test is Controller_PriceFeedManager_Test {
    function test_shouldReturnFalse_whenFeedNotExists() public {
        assertFalse(controller.priceFeedExists(makeAddr("unknown asset")));
    }

    function test_shouldReturnTrue_whenFeedExists() public {
        vm.prank(manager);
        controller.setPriceFeed(asset, feed, heartbeat);

        assertTrue(controller.priceFeedExists(asset));
    }
}
