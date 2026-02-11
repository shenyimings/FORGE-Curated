// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {DutchAuctionRebalanceAdapterTest} from "./DutchAuctionRebalanceAdapter.t.sol";
import {IDutchAuctionRebalanceAdapter} from "src/interfaces/IDutchAuctionRebalanceAdapter.sol";
import {Auction} from "src/types/DataTypes.sol";

contract EndAuctionTest is DutchAuctionRebalanceAdapterTest {
    function test_endAuction_WhenExpired() public {
        // Create an auction that will be expired
        _setLeverageTokenCollateralRatio(3.1e18); // Over-collateralized

        _createAuction();

        // Warp to after auction end time
        vm.warp(AUCTION_START_TIME + DEFAULT_DURATION + 1);

        // End auction
        vm.expectEmit(true, true, true, true);
        emit IDutchAuctionRebalanceAdapter.AuctionEnded();
        auctionRebalancer.endAuction();

        // Verify auction was deleted
        Auction memory auction = auctionRebalancer.getAuction();

        assertEq(auction.startTimestamp, 0);
        assertEq(auction.endTimestamp, 0);
        assertFalse(auction.isOverCollateralized);
    }

    function test_endAuction_WhenLeverageTokenNoLongerEligible() public {
        // Create an auction when over-collateralized
        _setLeverageTokenCollateralRatio(3.1e18);

        _createAuction();

        // Change leverage token state to be within bounds (no longer eligible)
        _setLeverageTokenCollateralRatio(2e18);

        // End auction
        vm.expectEmit(true, true, true, true);
        emit IDutchAuctionRebalanceAdapter.AuctionEnded();
        auctionRebalancer.endAuction();

        // Verify auction was deleted
        Auction memory auction = auctionRebalancer.getAuction();

        assertEq(auction.startTimestamp, 0);
        assertEq(auction.endTimestamp, 0);
        assertFalse(auction.isOverCollateralized);
    }

    function test_endAuction_WhenCollateralRatioDirectionChanged() public {
        // Create an auction when over-collateralized
        _setLeverageTokenCollateralRatio(3.1e18);

        _createAuction();

        // Change leverage token state to be under-collateralized
        _setLeverageTokenCollateralRatio(0.9e18);

        // End auction
        vm.expectEmit(true, true, true, true);
        emit IDutchAuctionRebalanceAdapter.AuctionEnded();
        auctionRebalancer.endAuction();

        // Verify auction was deleted
        Auction memory auction = auctionRebalancer.getAuction();

        assertEq(auction.startTimestamp, 0);
        assertEq(auction.endTimestamp, 0);
        assertFalse(auction.isOverCollateralized);
    }

    function test_endAuction_RevertIf_AuctionStillValid() public {
        // Create an auction
        _setLeverageTokenCollateralRatio(3.1e18);

        _createAuction();

        // Try to end auction while it's still valid
        vm.warp(AUCTION_START_TIME + DEFAULT_DURATION - 1);
        vm.expectRevert(IDutchAuctionRebalanceAdapter.AuctionStillValid.selector);
        auctionRebalancer.endAuction();
    }

    function testFuzz_endAuction_WhenExpired(uint256 timeAfterExpiry) public {
        // Create an auction
        _setLeverageTokenCollateralRatio(3.1e18);

        _createAuction();

        // Warp to some time after auction expiry
        timeAfterExpiry = bound(timeAfterExpiry, 1, 365 days);
        vm.warp(AUCTION_START_TIME + DEFAULT_DURATION + timeAfterExpiry);

        // End auction
        vm.expectEmit(true, true, true, true);
        emit IDutchAuctionRebalanceAdapter.AuctionEnded();
        auctionRebalancer.endAuction();

        // Verify auction was deleted
        Auction memory auction = auctionRebalancer.getAuction();

        assertEq(auction.startTimestamp, 0);
        assertEq(auction.endTimestamp, 0);
        assertFalse(auction.isOverCollateralized);
    }
}
