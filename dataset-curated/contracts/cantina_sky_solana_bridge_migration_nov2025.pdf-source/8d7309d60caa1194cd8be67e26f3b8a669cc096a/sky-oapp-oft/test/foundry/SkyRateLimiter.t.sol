// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import "../../contracts/SkyRateLimiter.sol";
import "../../contracts/interfaces/ISkyRateLimiter.sol";

contract SkyRateLimiterImpl is SkyRateLimiter {
    constructor() {}

    function setRateLimits(RateLimitConfig[] memory _rateLimitConfigs, RateLimitDirection _direction) external {
        _setRateLimits(_rateLimitConfigs, _direction);
    }

    function checkAndUpdateRateLimit(uint32 _eid, uint256 _amount, RateLimitDirection _direction) external {
        _checkAndUpdateRateLimit(_eid, _amount, _direction);
    }

    function inflow(uint32 _srcEid, uint256 _amount) external {
        _checkAndUpdateRateLimit(_srcEid, _amount, RateLimitDirection.Inbound);
    }

    function outflow(uint32 _dstEid, uint256 _amount) external {
        _checkAndUpdateRateLimit(_dstEid, _amount, RateLimitDirection.Outbound);
    }

    function resetRateLimits(uint32[] calldata _eids, RateLimitDirection _direction) external {
        _resetRateLimits(_eids, _direction);
    }

    function setRateLimitAccountingType(RateLimitAccountingType _rateLimitAccountingType) external {
        _setRateLimitAccountingType(_rateLimitAccountingType);
    }
    
    // Expose internal functions for testing
    function calculateDecay(
        uint256 _amountInFlight,
        uint128 _lastUpdated,
        uint256 _limit,
        uint48 _window
    ) external view returns (uint256 currentAmountInFlight, uint256 availableCapacity) {
        return _calculateDecay(_amountInFlight, _lastUpdated, _limit, _window);
    }
}

contract SkyRateLimiterTest is Test {
    uint32 eidA = 1;

    uint256 limit = 100 ether;
    uint48 window = 1 hours;

    uint256 amountInFlight;
    uint256 amountCanBeSent;
    uint256 amountCanBeReceived;

    SkyRateLimiterImpl rateLimiter;

    function setUp() public virtual {
        vm.warp(0);
        rateLimiter = new SkyRateLimiterImpl();
        
        // Set up outbound rate limits
        RateLimitConfig[] memory outboundConfigs = new RateLimitConfig[](1);
        outboundConfigs[0] = RateLimitConfig({ eid: eidA, limit: limit, window: window });
        rateLimiter.setRateLimits(outboundConfigs, RateLimitDirection.Outbound);

        // Set up inbound rate limits
        RateLimitConfig[] memory inboundConfigs = new RateLimitConfig[](1);
        inboundConfigs[0] = RateLimitConfig({ eid: eidA, limit: limit, window: window });
        rateLimiter.setRateLimits(inboundConfigs, RateLimitDirection.Inbound);
    }

    function test_max_outbound_rate_limit() public {
        rateLimiter.outflow(eidA, limit);
        
        (amountInFlight, amountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        assertEq(amountInFlight, limit);
        assertEq(amountCanBeSent, 0);
    }

    function test_max_inbound_rate_limit() public {
        rateLimiter.inflow(eidA, limit);
        
        (amountInFlight, amountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);
        assertEq(amountInFlight, limit);
        assertEq(amountCanBeReceived, 0);
    }

    function test_net_rate_limits_with_amounts_equal_to_limits() public {
        rateLimiter.setRateLimitAccountingType(RateLimitAccountingType.Net);

        // Use full outbound capacity
        rateLimiter.outflow(eidA, limit);
        (amountInFlight, amountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        assertEq(amountInFlight, limit);
        assertEq(amountCanBeSent, 0);

        (amountInFlight, amountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);
        assertEq(amountInFlight, 0);
        assertEq(amountCanBeReceived, limit);
        
        // Should still be able to receive inbound
        rateLimiter.inflow(eidA, limit);

        // Verify outbound is offset by the inbound
        (amountInFlight, amountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        assertEq(amountCanBeSent, limit);
        assertEq(amountInFlight, 0);

        // Verify inbound is maxed
        (amountInFlight, amountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);
        assertEq(amountCanBeReceived, 0);
        assertEq(amountInFlight, limit);

        rateLimiter.outflow(eidA, limit);

        // Verify inbound is offset by the outbound
        (amountInFlight, amountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        assertEq(amountCanBeSent, 0);
        assertEq(amountInFlight, limit);

        (amountInFlight, amountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);
        assertEq(amountCanBeReceived, limit);
        assertEq(amountInFlight, 0);
    }

    function test_gross_rate_limits_with_amounts_equal_to_limits() public {
        rateLimiter.setRateLimitAccountingType(RateLimitAccountingType.Gross);

        // Use full outbound capacity
        rateLimiter.outflow(eidA, limit);
        (amountInFlight, amountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        assertEq(amountInFlight, limit);
        assertEq(amountCanBeSent, 0);

        (amountInFlight, amountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);
        assertEq(amountInFlight, 0);
        assertEq(amountCanBeReceived, limit);
        
        // Should still be able to receive inbound
        rateLimiter.inflow(eidA, limit);

        (amountInFlight, amountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        assertEq(amountCanBeSent, 0);
        assertEq(amountInFlight, limit);

        (amountInFlight, amountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);
        assertEq(amountCanBeReceived, 0);
        assertEq(amountInFlight, limit);

        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        rateLimiter.outflow(eidA, limit);

        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        rateLimiter.inflow(eidA, limit);
    }

    function test_reset_net_rate_limits() public {
        rateLimiter.setRateLimitAccountingType(RateLimitAccountingType.Net);

        uint256 outflowAmount = limit / 2;
        uint256 inflowAmount = limit / 4;

        // Use some capacity
        rateLimiter.outflow(eidA, outflowAmount);
        rateLimiter.inflow(eidA, inflowAmount);

        (amountInFlight, amountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        assertEq(amountInFlight, outflowAmount - inflowAmount);
        assertEq(amountCanBeSent, limit - (outflowAmount - inflowAmount));

        (amountInFlight, amountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);
        assertEq(amountInFlight, inflowAmount);
        assertEq(amountCanBeReceived, limit - inflowAmount);

        // Reset the outbound rate limits
        uint32[] memory eids = new uint32[](1);
        eids[0] = eidA;
        rateLimiter.resetRateLimits(eids, RateLimitDirection.Outbound);

        // Verify outbound rate limits are cleared
        (amountInFlight, amountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        assertEq(amountInFlight, 0);
        assertEq(amountCanBeSent, limit);

        // Verify inbound rate limits are not affected
        (amountInFlight, amountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);
        assertEq(amountInFlight, inflowAmount);
        assertEq(amountCanBeReceived, limit - inflowAmount);

        // Reset the inbound rate limits
        rateLimiter.resetRateLimits(eids, RateLimitDirection.Inbound);

        // Verify inbound rate limits are cleared
        (amountInFlight, amountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);
        assertEq(amountInFlight, 0);
        assertEq(amountCanBeReceived, limit);
    }

    function test_reset_gross_rate_limits() public {
        rateLimiter.setRateLimitAccountingType(RateLimitAccountingType.Gross);

        // Use some capacity
        rateLimiter.outflow(eidA, limit / 2);
        rateLimiter.inflow(eidA, limit / 2);

        (amountInFlight, amountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        assertEq(amountInFlight, limit / 2);
        assertEq(amountCanBeSent, limit / 2);

        (amountInFlight, amountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);
        assertEq(amountInFlight, limit / 2);
        assertEq(amountCanBeReceived, limit / 2);

        // Reset the outbound rate limits
        uint32[] memory eids = new uint32[](1);
        eids[0] = eidA;
        rateLimiter.resetRateLimits(eids, RateLimitDirection.Outbound);

        // Verify outbound rate limits are cleared
        (amountInFlight, amountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        assertEq(amountInFlight, 0);
        assertEq(amountCanBeSent, limit);

        // Verify inbound rate limits are not affected
        (amountInFlight, amountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);
        assertEq(amountInFlight, limit / 2);
        assertEq(amountCanBeReceived, limit / 2);

        // Reset the inbound rate limits
        rateLimiter.resetRateLimits(eids, RateLimitDirection.Inbound);

        // Verify inbound rate limits are cleared
        (amountInFlight, amountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);
        assertEq(amountInFlight, 0);
        assertEq(amountCanBeReceived, limit);
    }

    function test_change_accounting_type() public {
        // Start with Net accounting (default)
        rateLimiter.outflow(eidA, limit / 2);
        
        // Change to Gross accounting
        rateLimiter.setRateLimitAccountingType(RateLimitAccountingType.Gross);
        
        // Reset limits after changing accounting type
        uint32[] memory eids = new uint32[](1);
        eids[0] = eidA;
        rateLimiter.resetRateLimits(eids, RateLimitDirection.Outbound);

        rateLimiter.outflow(eidA, limit);
        
        rateLimiter.inflow(eidA, limit);
        
        // This should fail as we've hit the gross limit
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        rateLimiter.outflow(eidA, limit);
    }

    function test_rate_limit_window_decay() public {
        rateLimiter.outflow(eidA, limit / 2);
        
        skip(window / 4);

        (amountInFlight, amountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        assertEq(amountCanBeSent, limit - limit / 4);
        assertEq(amountInFlight, limit / 4);

        skip(window);

        (amountInFlight, amountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        assertEq(amountCanBeSent, limit);
        assertEq(amountInFlight, 0);
    }

    function test_over_rate_limit() public {
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        rateLimiter.outflow(eidA, limit + 1);

        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        rateLimiter.inflow(eidA, limit + 1);
    }

    function test_rate_limit_resets_after_window() public {
        rateLimiter.outflow(eidA, limit);
        vm.warp(block.timestamp + window + 1);
        rateLimiter.outflow(eidA, limit);

        rateLimiter.inflow(eidA, limit);
        vm.warp(block.timestamp + window + 1);
        rateLimiter.inflow(eidA, limit);
    }

    function test_fuzz_outflow(uint256 amount1, uint256 amount2, uint256 timeSkip) public {
        amount1 = bound(amount1, 0, limit);
        amount2 = bound(amount2, 0, limit);
        timeSkip = bound(timeSkip, 0, 2 * window);

        rateLimiter.outflow(eidA, amount1);
        
        skip(timeSkip);

        (uint256 actualAmountInFlight, uint256 actualAmountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);

        if (timeSkip >= window) {
            assertEq(actualAmountInFlight, 0);
            assertEq(actualAmountCanBeSent, limit);
        } else {
            assertTrue(actualAmountInFlight <= amount1);
            assertEq(actualAmountCanBeSent, limit - actualAmountInFlight);
        }

        if (amount2 <= actualAmountCanBeSent) {
            rateLimiter.outflow(eidA, amount2);
            (uint256 newAmountInFlight,) = rateLimiter.getAmountCanBeSent(eidA);
            assertTrue(newAmountInFlight <= limit, "Total amount exceeds limit");
        } else {
            vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
            rateLimiter.outflow(eidA, amount2);
        }
    }

    function test_fuzz_inflow(uint256 amount1, uint256 amount2, uint256 timeSkip) public {
        amount1 = bound(amount1, 0, limit);
        amount2 = bound(amount2, 0, limit);
        timeSkip = bound(timeSkip, 0, 2 * window);

        rateLimiter.inflow(eidA, amount1);

        skip(timeSkip);

        (uint256 actualAmountInFlight, uint256 actualAmountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);

        if (timeSkip >= window) {
            assertEq(actualAmountInFlight, 0);
            assertEq(actualAmountCanBeReceived, limit);
        } else {
            assertTrue(actualAmountInFlight <= amount1);
            assertEq(actualAmountCanBeReceived, limit - actualAmountInFlight);
        }

        if (amount2 <= actualAmountCanBeReceived) {
            rateLimiter.inflow(eidA, amount2);
        } else {
            vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
            rateLimiter.inflow(eidA, amount2);
        }
    }

    function test_fuzz_net_rate_limits(uint256 amount1, uint256 amount2, uint256 timeSkip) public {
        amount1 = bound(amount1, 0, limit);
        amount2 = bound(amount2, 0, limit);
        timeSkip = bound(timeSkip, 0, 2 * window);

        rateLimiter.setRateLimitAccountingType(RateLimitAccountingType.Net);

        rateLimiter.outflow(eidA, amount1);
        rateLimiter.inflow(eidA, amount2);

        (uint256 actualOutboundAmountInFlight, uint256 actualOutboundAmountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        (uint256 actualInboundAmountInFlight, uint256 actualInboundAmountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);

        if (amount1 > amount2) {
            assertEq(actualOutboundAmountInFlight, amount1 - amount2);
            assertEq(actualOutboundAmountCanBeSent, limit - (amount1 - amount2));
        } else {
            assertEq(actualOutboundAmountInFlight, 0);
            assertEq(actualOutboundAmountCanBeSent, limit);

            assertEq(actualInboundAmountInFlight, amount2);
            assertEq(actualInboundAmountCanBeReceived, limit - amount2);
        }

        skip(timeSkip);

        (actualOutboundAmountInFlight, actualOutboundAmountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        (actualInboundAmountInFlight, actualInboundAmountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);

        if (amount1 > amount2) {
            assertTrue(actualOutboundAmountInFlight <= amount1 - amount2);
            assertTrue(actualOutboundAmountCanBeSent >= limit - actualOutboundAmountInFlight);

            assertTrue(actualInboundAmountInFlight <= amount2);
            assertEq(actualInboundAmountCanBeReceived, limit - actualInboundAmountInFlight);
        } else {
            assertEq(actualOutboundAmountInFlight, 0);
            assertEq(actualOutboundAmountCanBeSent, limit);

            assertTrue(actualInboundAmountInFlight <= amount2);
            assertEq(actualInboundAmountCanBeReceived, limit - actualInboundAmountInFlight);
        }
    }

    function test_fuzz_gross_rate_limits(uint256 amount1, uint256 amount2, uint256 timeSkip) public {
        amount1 = bound(amount1, 0, limit);
        amount2 = bound(amount2, 0, limit);
        timeSkip = bound(timeSkip, 0, 2 * window);

        rateLimiter.setRateLimitAccountingType(RateLimitAccountingType.Gross);

        rateLimiter.outflow(eidA, amount1);
        rateLimiter.inflow(eidA, amount2);

        (uint256 actualOutboundAmountInFlight, uint256 actualOutboundAmountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        (uint256 actualInboundAmountInFlight, uint256 actualInboundAmountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);

        assertEq(actualOutboundAmountInFlight, amount1);
        assertEq(actualOutboundAmountCanBeSent, limit - amount1);
   
        assertEq(actualInboundAmountInFlight, amount2);
        assertEq(actualInboundAmountCanBeReceived, limit - amount2);

        skip(timeSkip);

        (actualOutboundAmountInFlight, actualOutboundAmountCanBeSent) = rateLimiter.getAmountCanBeSent(eidA);
        (actualInboundAmountInFlight, actualInboundAmountCanBeReceived) = rateLimiter.getAmountCanBeReceived(eidA);

        if (timeSkip >= window) {
            assertEq(actualOutboundAmountInFlight, 0);
            assertEq(actualOutboundAmountCanBeSent, limit);

            assertEq(actualInboundAmountInFlight, 0);
            assertEq(actualInboundAmountCanBeReceived, limit);
        } else {
            assertTrue(actualOutboundAmountInFlight <= amount1);
            assertEq(actualOutboundAmountCanBeSent, limit - actualOutboundAmountInFlight);

            assertTrue(actualInboundAmountInFlight <= amount2);
        }
    }

    // Additional tests for missing functionality

    function test_calculate_decay_function() public {
        uint256 testAmount = limit / 2;
        uint128 lastUpdated = uint128(block.timestamp);
        
        // Test when time elapsed is 0
        (uint256 currentAmountInFlight, uint256 availableCapacity) = rateLimiter.calculateDecay(
            testAmount, 
            lastUpdated, 
            limit, 
            window
        );
        assertEq(currentAmountInFlight, testAmount);
        assertEq(availableCapacity, limit - testAmount);
        
        // Test when time elapsed is half the window
        vm.warp(block.timestamp + window / 2);
        (currentAmountInFlight, availableCapacity) = rateLimiter.calculateDecay(
            testAmount, 
            lastUpdated, 
            limit, 
            window
        );
        // The decay calculation is: decay = (limit * timeSinceLastUpdate) / window
        // So with half the window: decay = (100 ether * (window/2)) / window = 50 ether
        // And currentAmountInFlight = testAmount - decay = 50 ether - 50 ether = 0
        uint256 expectedDecay = (limit * (window / 2)) / window;
        uint256 expectedAmountInFlight = testAmount > expectedDecay ? testAmount - expectedDecay : 0;
        assertEq(currentAmountInFlight, expectedAmountInFlight);
        assertEq(availableCapacity, limit - expectedAmountInFlight);
        
        // Test when time elapsed is equal to the window
        vm.warp(block.timestamp + window / 2); // Now at full window
        (currentAmountInFlight, availableCapacity) = rateLimiter.calculateDecay(
            testAmount, 
            lastUpdated, 
            limit, 
            window
        );
        assertEq(currentAmountInFlight, 0);
        assertEq(availableCapacity, limit);
        
        // Test when time elapsed is greater than the window
        vm.warp(block.timestamp + 1); // Now beyond window
        (currentAmountInFlight, availableCapacity) = rateLimiter.calculateDecay(
            testAmount, 
            lastUpdated, 
            limit, 
            window
        );
        assertEq(currentAmountInFlight, 0);
        assertEq(availableCapacity, limit);
    }

    function test_events_emitted() public {
        // Test RateLimitsChanged event
        RateLimitConfig[] memory configs = new RateLimitConfig[](1);
        configs[0] = RateLimitConfig({ eid: 2, limit: 200 ether, window: 2 hours });
        
        vm.expectEmit(true, true, true, true);
        emit ISkyRateLimiter.RateLimitsChanged(configs, RateLimitDirection.Outbound);
        rateLimiter.setRateLimits(configs, RateLimitDirection.Outbound);
        
        // Test RateLimitAccountingTypeSet event
        vm.expectEmit(true, true, true, true);
        emit ISkyRateLimiter.RateLimitAccountingTypeSet(RateLimitAccountingType.Gross);
        rateLimiter.setRateLimitAccountingType(RateLimitAccountingType.Gross);
        
        // Test RateLimitsReset event
        uint32[] memory eids = new uint32[](1);
        eids[0] = eidA;
        
        vm.expectEmit(true, true, true, true);
        emit ISkyRateLimiter.RateLimitsReset(eids, RateLimitDirection.Inbound);
        rateLimiter.resetRateLimits(eids, RateLimitDirection.Inbound);
    }

    function test_edge_cases() public {
        // Test with zero limit
        RateLimitConfig[] memory configs = new RateLimitConfig[](1);
        configs[0] = RateLimitConfig({ eid: 2, limit: 0, window: window });
        rateLimiter.setRateLimits(configs, RateLimitDirection.Outbound);
        
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        rateLimiter.outflow(2, 1); // Any amount > 0 should fail
        
        // Test with zero window (should be handled like any other window)
        configs[0] = RateLimitConfig({ eid: 3, limit: limit, window: 0 });
        rateLimiter.setRateLimits(configs, RateLimitDirection.Outbound);
        
        // Should be able to send the full limit
        rateLimiter.outflow(3, limit);
        
        // Test with very small amounts
        configs[0] = RateLimitConfig({ eid: 4, limit: 100, window: window });
        rateLimiter.setRateLimits(configs, RateLimitDirection.Outbound);
        
        // Send small amounts multiple times
        for (uint i = 0; i < 100; i++) {
            rateLimiter.outflow(4, 1);
        }
        
        // Should have reached the limit
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        rateLimiter.outflow(4, 1);
    }

    function test_multiple_endpoints() public {
        uint32 eidB = 2;
        
        // Set up different limits for different endpoints
        RateLimitConfig[] memory configs = new RateLimitConfig[](2);
        configs[0] = RateLimitConfig({ eid: eidA, limit: limit, window: window });
        configs[1] = RateLimitConfig({ eid: eidB, limit: limit * 2, window: window * 2 });
        
        rateLimiter.setRateLimits(configs, RateLimitDirection.Outbound);
        
        // Test that each endpoint has its own independent rate limit
        rateLimiter.outflow(eidA, limit);
        rateLimiter.outflow(eidB, limit * 2);
        
        // eidA should be at limit
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        rateLimiter.outflow(eidA, 1);
        
        // eidB should be at limit
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        rateLimiter.outflow(eidB, 1);
        
        // Reset just eidA
        uint32[] memory eids = new uint32[](1);
        eids[0] = eidA;
        rateLimiter.resetRateLimits(eids, RateLimitDirection.Outbound);
        
        // eidA should now allow sending
        rateLimiter.outflow(eidA, limit);
        
        // eidB should still be at limit
        vm.expectRevert(abi.encodeWithSelector(ISkyRateLimiter.RateLimitExceeded.selector));
        rateLimiter.outflow(eidB, 1);
    }
}