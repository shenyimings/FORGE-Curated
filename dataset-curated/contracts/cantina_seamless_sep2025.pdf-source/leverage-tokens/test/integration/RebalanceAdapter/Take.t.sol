// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {DutchAuctionTest} from "./DutchAuction.t.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";
import {IDutchAuctionRebalanceAdapter} from "src/interfaces/IDutchAuctionRebalanceAdapter.sol";
import {Auction} from "src/types/DataTypes.sol";

contract TakeTest is DutchAuctionTest {
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    function testFork_take_OverCollateralized() public {
        _prepareOverCollateralizedState();

        // Start auction
        ethLong2xRebalanceAdapter.createAuction();

        LeverageTokenState memory stateBefore = leverageManager.getLeverageTokenState(ethLong2x);

        // Initial price is 102% or oracle. Highly unprofitable but is possible to be taken
        uint256 amountInAlice = _take_OverCollateralized(alice, 2_000 * 1e6);

        // Some time passes and Bob takes for better price
        vm.warp(block.timestamp + 2 minutes);
        uint256 amountInBob = _take_OverCollateralized(bob, 2_000 * 1e6);

        // Some more time passes and Charlie takes it for even better price
        vm.warp(block.timestamp + 4 minutes);
        uint256 amountInCharlie = _take_OverCollateralized(charlie, 2_000 * 1e6);

        LeverageTokenState memory stateAfter = leverageManager.getLeverageTokenState(ethLong2x);

        assertLe(stateAfter.collateralRatio, stateBefore.collateralRatio);

        // 1% is max loss because 99% is min auction multiplier
        uint256 maxLoss = stateBefore.equity / 100;
        assertGe(stateAfter.equity, stateBefore.equity - maxLoss);

        // Check if user received correct amount of debt
        assertEq(USDC.balanceOf(alice), 2_000 * 1e6);
        assertEq(USDC.balanceOf(bob), 2_000 * 1e6);
        assertEq(USDC.balanceOf(charlie), 2_000 * 1e6);

        // Execute one more take just to bring it back to healthy state
        _take_OverCollateralized(alice, 1_000 * 1e6);

        // Auction should automatically be removed because leverage token is back into healthy state
        Auction memory auction = ethLong2xRebalanceAdapter.getAuction();

        assertEq(auction.isOverCollateralized, false);
        assertEq(auction.startTimestamp, 0);
        assertEq(auction.endTimestamp, 0);

        assertLe(amountInBob, amountInAlice);
        assertLe(amountInCharlie, amountInBob);

        // Assert that returned price is min price even if auction is no longer valid
        vm.warp(block.timestamp + 6 minutes);
        assertEq(
            ethLong2xRebalanceAdapter.getCurrentAuctionMultiplier(), ethLong2xRebalanceAdapter.getMinPriceMultiplier()
        );
    }

    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_take_UnderCollateralized() public {
        _prepareUnderCollateralizedState();

        // Start auction
        ethLong2xRebalanceAdapter.createAuction();

        LeverageTokenState memory stateBefore = leverageManager.getLeverageTokenState(ethLong2x);

        // Alice takes for big price
        uint256 amountInAlice = _take_UnderCollateralized(alice, 1e18);

        // Some time passes and Bob takes for better price
        vm.warp(block.timestamp + 2 minutes);
        uint256 amountInBob = _take_UnderCollateralized(bob, 1e18);

        // Some more time passes and Charlie takes it for even better price
        vm.warp(block.timestamp + 4 minutes);
        uint256 amountInCharlie = _take_UnderCollateralized(charlie, 1e18);

        LeverageTokenState memory stateAfter = leverageManager.getLeverageTokenState(ethLong2x);

        assertGe(stateAfter.collateralRatio, stateBefore.collateralRatio);

        // 2% is max loss because 98% is min auction multiplier
        uint256 maxLoss = stateBefore.equity * 2 / 100;
        assertGe(stateAfter.equity, stateBefore.equity - maxLoss);

        // Check if user received correct amount of collateral
        assertEq(WETH.balanceOf(alice), 1e18);
        assertEq(WETH.balanceOf(bob), 1e18);
        assertEq(WETH.balanceOf(charlie), 1e18);

        // Auction should automatically be removed because leverage token is back into healthy state
        Auction memory auction = ethLong2xRebalanceAdapter.getAuction();

        assertEq(auction.isOverCollateralized, false);
        assertEq(auction.startTimestamp, 0);
        assertEq(auction.endTimestamp, 0);

        assertLe(amountInBob, amountInAlice);
        assertLe(amountInCharlie, amountInBob);

        assertLe(amountInBob, amountInAlice);
        assertLe(amountInCharlie, amountInBob);
    }

    function testFork_take_LeverageTokenBackToHealthy() public {
        _prepareOverCollateralizedState();

        // Start auction
        ethLong2xRebalanceAdapter.createAuction();

        // Alice takes
        _take_OverCollateralized(alice, 2_000 * 1e6);

        _moveEthPrice(-15_00); // Move ETH price 15% down to bring leverage token is back to healthy state

        // Try to take and reverts
        vm.expectRevert(IDutchAuctionRebalanceAdapter.AuctionNotValid.selector);
        ethLong2xRebalanceAdapter.take(1e18);
    }

    function _take_OverCollateralized(address user, uint256 amountOut) internal returns (uint256) {
        uint256 amountIn = ethLong2xRebalanceAdapter.getAmountIn(amountOut);
        deal(address(WETH), user, amountIn);

        vm.startPrank(user);
        WETH.approve(address(ethLong2xRebalanceAdapter), amountIn);
        ethLong2xRebalanceAdapter.take(amountOut);
        vm.stopPrank();

        return amountIn;
    }

    function _take_UnderCollateralized(address user, uint256 amountOut) internal returns (uint256) {
        uint256 amountIn = ethLong2xRebalanceAdapter.getAmountIn(amountOut);
        deal(address(USDC), user, amountIn);

        vm.startPrank(user);
        USDC.approve(address(ethLong2xRebalanceAdapter), amountIn);
        ethLong2xRebalanceAdapter.take(amountOut);
        vm.stopPrank();

        return amountIn;
    }
}
