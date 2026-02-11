// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {DutchAuctionRebalanceAdapterTest} from "./DutchAuctionRebalanceAdapter.t.sol";

contract GetCurrentAuctionMultiplierTest is DutchAuctionRebalanceAdapterTest {
    function test_getCurrentAuctionMultiplier_NoAuction() public view {
        assertEq(auctionRebalancer.getCurrentAuctionMultiplier(), DEFAULT_MIN_PRICE_MULTIPLIER);
    }

    function test_getCurrentAuctionMultiplier_AtStart() public {
        // Create auction
        _setLeverageTokenCollateralRatio(3.1e18); // Over-collateralized

        _createAuction();

        // Check multiplier at start
        assertEq(auctionRebalancer.getCurrentAuctionMultiplier(), DEFAULT_INITIAL_PRICE_MULTIPLIER);
    }

    function test_getCurrentAuctionMultiplier_AtEnd() public {
        // Create auction
        _setLeverageTokenCollateralRatio(3.1e18); // Over-collateralized

        _createAuction();

        // Warp to end of auction
        vm.warp(AUCTION_START_TIME + DEFAULT_DURATION);

        // At end, should be at minimum multiplier
        assertEq(auctionRebalancer.getCurrentAuctionMultiplier(), DEFAULT_MIN_PRICE_MULTIPLIER);
    }

    function test_getCurrentAuctionMultiplier_AtQuarter() public {
        // Create auction
        _setLeverageTokenCollateralRatio(3.1e18);

        _createAuction();

        // Warp to 25% of auction duration
        vm.warp(AUCTION_START_TIME + DEFAULT_DURATION / 4);

        uint256 multiplier = auctionRebalancer.getCurrentAuctionMultiplier();

        // At t=0.25:
        // progress = 0.25
        // base = (1-0.25) = 0.75
        // decayFactor = (0.75)^4 = 0.31640625
        // range = 11000 - 1000 = 10000
        // premium = 10000 * 0.31640625 = 3164.0625
        // final = 1000 + 3164.0625 = 4164.0625
        assertEq(multiplier, 416406250000000000);

        // Sanity checks
        assertTrue(multiplier < DEFAULT_INITIAL_PRICE_MULTIPLIER);
        assertTrue(multiplier > DEFAULT_MIN_PRICE_MULTIPLIER);
    }

    function test_getCurrentAuctionMultiplier_AtHalf() public {
        // Create auction
        _setLeverageTokenCollateralRatio(3.1e18);

        _createAuction();

        // Warp to 50% of auction duration
        vm.warp(AUCTION_START_TIME + DEFAULT_DURATION / 2);

        uint256 multiplier = auctionRebalancer.getCurrentAuctionMultiplier();

        // At t=0.5:
        // progress = 0.5
        // base = (1-0.5) = 0.5
        // decayFactor = (0.5)^4 = 0.0625
        // range = 11000 - 1000 = 10000
        // premium = 10000 * 0.0625 = 625
        // final = 1000 + 625 = 1625
        assertEq(multiplier, 162500000000000000);

        // Sanity checks
        assertTrue(multiplier < DEFAULT_INITIAL_PRICE_MULTIPLIER);
        assertTrue(multiplier > DEFAULT_MIN_PRICE_MULTIPLIER);
    }

    function test_getCurrentAuctionMultiplier_AtThreeQuarters() public {
        // Create auction
        _setLeverageTokenCollateralRatio(3.1e18);

        _createAuction();

        // Warp to 75% of auction duration
        vm.warp(AUCTION_START_TIME + (DEFAULT_DURATION * 3) / 4);

        uint256 multiplier = auctionRebalancer.getCurrentAuctionMultiplier();

        // At t=0.75:
        // progress = 0.75
        // base = (1-0.75) = 0.25
        // decayFactor = (0.25)^4 = 0.00390625
        // range = 11000 - 1000 = 10000
        // premium = 10000 * 0.00390625 = 39
        // final = 1000 + 39 = 1039
        assertEq(multiplier, 103906250000000000);

        // Sanity checks
        assertTrue(multiplier < DEFAULT_INITIAL_PRICE_MULTIPLIER);
        assertTrue(multiplier > DEFAULT_MIN_PRICE_MULTIPLIER);
    }

    function testFuzz_getCurrentAuctionMultiplier_PriceShouldAlwaysDecrease(uint256 timeElapsed1, uint256 timeElapsed2)
        public
    {
        timeElapsed1 = bound(timeElapsed1, 0, DEFAULT_DURATION);
        timeElapsed2 = bound(timeElapsed2, 0, DEFAULT_DURATION);
        vm.assume(timeElapsed1 < timeElapsed2);
        vm.assume(timeElapsed2 - timeElapsed1 > 3);

        // Create auction
        _setLeverageTokenCollateralRatio(3.1e18);

        _createAuction();

        // Warp to first timestamp
        vm.warp(AUCTION_START_TIME + timeElapsed1);
        uint256 multiplier1 = auctionRebalancer.getCurrentAuctionMultiplier();

        // Warp to second timestamp
        vm.warp(AUCTION_START_TIME + timeElapsed2);
        uint256 multiplier2 = auctionRebalancer.getCurrentAuctionMultiplier();

        assertTrue(multiplier1 > multiplier2);
    }

    function testFuzz_getCurrentAuctionMultiplier_MultiplierShouldNeverBeBelowMinMultiplier(uint256 timeElapsed)
        public
    {
        timeElapsed = bound(timeElapsed, 0, DEFAULT_DURATION);

        // Create auction
        _setLeverageTokenCollateralRatio(3.1e8);

        _createAuction();

        // Warp to timestamp
        vm.warp(AUCTION_START_TIME + timeElapsed);

        assertGe(auctionRebalancer.getCurrentAuctionMultiplier(), DEFAULT_MIN_PRICE_MULTIPLIER);
    }
}
