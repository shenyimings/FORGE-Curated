// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IDutchAuctionRebalanceAdapter} from "src/interfaces/IDutchAuctionRebalanceAdapter.sol";
import {DutchAuctionTest} from "./DutchAuction.t.sol";
import {Auction} from "src/types/DataTypes.sol";

contract EndAuctionTest is DutchAuctionTest {
    function testFork_endAuction_TimePassed() public {
        _prepareOverCollateralizedState();

        // Start auction
        ethLong2xRebalanceAdapter.createAuction();

        // End auction
        vm.warp(block.timestamp + 7 minutes + 1);
        assertFalse(ethLong2xRebalanceAdapter.isAuctionValid());
        ethLong2xRebalanceAdapter.endAuction();

        Auction memory auction = ethLong2xRebalanceAdapter.getAuction();

        assertEq(auction.isOverCollateralized, false);
        assertEq(auction.startTimestamp, 0);
        assertEq(auction.endTimestamp, 0);
    }

    function testFork_endAuction_NoLongerEligible() public {
        _prepareOverCollateralizedState();

        // Start auction
        ethLong2xRebalanceAdapter.createAuction();

        _moveEthPrice(-15_00); // 15% down to make it healthy

        // End auction
        assertFalse(ethLong2xRebalanceAdapter.isAuctionValid());
        ethLong2xRebalanceAdapter.endAuction();

        Auction memory auction = ethLong2xRebalanceAdapter.getAuction();
        assertEq(auction.isOverCollateralized, false);
        assertEq(auction.startTimestamp, 0);
        assertEq(auction.endTimestamp, 0);

        (bool isEligible,) = ethLong2xRebalanceAdapter.getLeverageTokenRebalanceStatus();
        assertFalse(isEligible);
    }

    function testFork_endAuction_ExposureDirectionChanged() public {
        _prepareOverCollateralizedState();

        // Start auction
        ethLong2xRebalanceAdapter.createAuction();

        _moveEthPrice(-50_00); // 50% down to make it under-collateralized

        // End auction
        assertFalse(ethLong2xRebalanceAdapter.isAuctionValid());
        ethLong2xRebalanceAdapter.endAuction();

        Auction memory auction = ethLong2xRebalanceAdapter.getAuction();
        assertEq(auction.isOverCollateralized, false);
        assertEq(auction.startTimestamp, 0);
        assertEq(auction.endTimestamp, 0);
    }

    function testFork_endAuction_RevertIf_AuctionStillValid() public {
        _prepareOverCollateralizedState();

        // Start auction
        ethLong2xRebalanceAdapter.createAuction();

        vm.warp(block.timestamp + 7 minutes);
        assertTrue(ethLong2xRebalanceAdapter.isAuctionValid());

        // End auction
        vm.expectRevert(IDutchAuctionRebalanceAdapter.AuctionStillValid.selector);
        ethLong2xRebalanceAdapter.endAuction();
    }

    function testFork_endAuction_RevertIf_EligibleForRebalance() public {
        _prepareOverCollateralizedState();

        // Start auction
        ethLong2xRebalanceAdapter.createAuction();

        assertTrue(ethLong2xRebalanceAdapter.isAuctionValid());

        // End auction
        vm.expectRevert(IDutchAuctionRebalanceAdapter.AuctionStillValid.selector);
        ethLong2xRebalanceAdapter.endAuction();
    }
}
