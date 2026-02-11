// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {RebalanceTest} from "test/integration/LeverageManager/Rebalance.t.sol";
import {DutchAuctionRebalanceAdapter} from "src/rebalance/DutchAuctionRebalanceAdapter.sol";
import {Auction, LeverageTokenState} from "src/types/DataTypes.sol";
import {IDutchAuctionRebalanceAdapter} from "src/interfaces/IDutchAuctionRebalanceAdapter.sol";
import {DutchAuctionTest} from "./DutchAuction.t.sol";

contract CreateAuctionTest is DutchAuctionTest {
    function testFork_createAuction_OverCollateralized() public {
        _prepareOverCollateralizedState();

        // Start auction
        ethLong2xRebalanceAdapter.createAuction();

        Auction memory auction = ethLong2xRebalanceAdapter.getAuction();

        assertEq(auction.isOverCollateralized, true);
        assertEq(auction.startTimestamp, block.timestamp);
        assertEq(auction.endTimestamp, block.timestamp + 7 minutes);
    }

    function testFork_createAuction_UnderCollateralized() public {
        _prepareUnderCollateralizedState();

        // Start auction
        ethLong2xRebalanceAdapter.createAuction();

        Auction memory auction = ethLong2xRebalanceAdapter.getAuction();

        assertEq(auction.isOverCollateralized, false);
        assertEq(auction.startTimestamp, block.timestamp);
        assertEq(auction.endTimestamp, block.timestamp + 7 minutes);
    }

    function testFork_createAuction_DeletesPreviousInvalidAuction_IfTimePassed() public {
        _prepareOverCollateralizedState();

        // Start auction
        ethLong2xRebalanceAdapter.createAuction();

        // Time passes
        vm.warp(block.timestamp + 7 minutes + 1);

        // Create auction again
        ethLong2xRebalanceAdapter.createAuction();

        Auction memory auction = ethLong2xRebalanceAdapter.getAuction();

        assertEq(auction.isOverCollateralized, true);
        assertEq(auction.startTimestamp, block.timestamp);
        assertEq(auction.endTimestamp, block.timestamp + 7 minutes);
    }

    function test_Fork_createAuction_DeletesPreviousInvalidAuctionIf_CollateralRatioDirectionChanged() public {
        _prepareOverCollateralizedState();

        // Start auction
        ethLong2xRebalanceAdapter.createAuction();

        // Move ETH price 40% down
        _moveEthPrice(-40_00);

        // Create auction again
        ethLong2xRebalanceAdapter.createAuction();

        Auction memory auction = ethLong2xRebalanceAdapter.getAuction();

        assertEq(auction.isOverCollateralized, false);
        assertEq(auction.startTimestamp, block.timestamp);
        assertEq(auction.endTimestamp, block.timestamp + 7 minutes);
    }

    function testFork_createAuction_RevertIf_LeverageTokenNotEligibleForRebalance() public {
        uint256 equityToDeposit = 10 * 1e18;
        uint256 collateralToAdd = leverageManager.previewDeposit(ethLong2x, equityToDeposit).collateral;
        _deposit(ethLong2x, user, equityToDeposit, collateralToAdd);

        vm.expectRevert(IDutchAuctionRebalanceAdapter.LeverageTokenNotEligibleForRebalance.selector);
        ethLong2xRebalanceAdapter.createAuction();
    }
}
