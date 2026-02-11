// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {DutchAuctionRebalanceAdapterTest} from "./DutchAuctionRebalanceAdapter.t.sol";
import {IDutchAuctionRebalanceAdapter} from "src/interfaces/IDutchAuctionRebalanceAdapter.sol";
import {Auction} from "src/types/DataTypes.sol";

contract CreateAuctionTest is DutchAuctionRebalanceAdapterTest {
    function test_createAuction_UnderCollateralized() public {
        // Set current ratio to be below min (under-collateralized)
        _setLeverageTokenCollateralRatio(1.4e18);

        // Set block timestamp
        vm.warp(AUCTION_START_TIME);

        // Create auction
        vm.expectEmit(true, true, true, true);
        emit IDutchAuctionRebalanceAdapter.AuctionCreated(
            Auction({
                isOverCollateralized: false,
                startTimestamp: AUCTION_START_TIME,
                endTimestamp: AUCTION_START_TIME + auctionRebalancer.getAuctionDuration()
            })
        );
        vm.prank(owner);
        auctionRebalancer.createAuction();

        // Verify auction details
        Auction memory auction = auctionRebalancer.getAuction();

        assertFalse(auction.isOverCollateralized);
        assertEq(auction.startTimestamp, AUCTION_START_TIME);
        assertEq(auction.endTimestamp, AUCTION_START_TIME + auctionRebalancer.getAuctionDuration());
    }

    function test_createAuction_OverCollateralized() public {
        // Set current ratio to be above max (over-collateralized)
        _setLeverageTokenCollateralRatio(3.1e18);

        // Set block timestamp
        vm.warp(AUCTION_START_TIME);

        // Create auction
        vm.expectEmit(true, true, true, true);
        emit IDutchAuctionRebalanceAdapter.AuctionCreated(
            Auction({
                isOverCollateralized: true,
                startTimestamp: AUCTION_START_TIME,
                endTimestamp: AUCTION_START_TIME + auctionRebalancer.getAuctionDuration()
            })
        );
        vm.prank(owner);
        auctionRebalancer.createAuction();

        // Verify auction details
        Auction memory auction = auctionRebalancer.getAuction();

        assertTrue(auction.isOverCollateralized);
        assertEq(auction.startTimestamp, AUCTION_START_TIME);
        assertEq(auction.endTimestamp, AUCTION_START_TIME + auctionRebalancer.getAuctionDuration());
    }

    function test_createAuction_RevertIf_AuctionStillValid() public {
        // Set current ratio to be above max (eligible)
        _setLeverageTokenCollateralRatio(3.1e18);

        // Create first auction
        _createAuction();

        // Try to create another auction while first is still valid
        vm.warp(AUCTION_START_TIME + auctionRebalancer.getAuctionDuration() - 1);
        vm.prank(owner);
        vm.expectRevert(IDutchAuctionRebalanceAdapter.AuctionStillValid.selector);
        auctionRebalancer.createAuction();
    }

    function test_createAuction_RevertIf_NotEligible() public {
        auctionRebalancer.mock_isEligible(false);

        vm.expectRevert(IDutchAuctionRebalanceAdapter.LeverageTokenNotEligibleForRebalance.selector);
        auctionRebalancer.createAuction();
    }
}
