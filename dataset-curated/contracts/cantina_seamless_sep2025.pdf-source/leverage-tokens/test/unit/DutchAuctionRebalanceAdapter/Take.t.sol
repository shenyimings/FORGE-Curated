// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {DutchAuctionRebalanceAdapterTest} from "./DutchAuctionRebalanceAdapter.t.sol";
import {IDutchAuctionRebalanceAdapter} from "src/interfaces/IDutchAuctionRebalanceAdapter.sol";
import {Auction} from "src/types/DataTypes.sol";

contract TakeTest is DutchAuctionRebalanceAdapterTest {
    function test_take_OverCollateralized() public {
        // Create over-collateralized auction
        _setLeverageTokenCollateralRatio(MAX_RATIO + 1);

        _createAuction();

        // Mock exchange rate
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(0.5e8);

        uint256 timePassed = 1000;
        vm.warp(AUCTION_START_TIME + timePassed);

        uint256 amountOut = 1e18;
        uint256 amountIn = auctionRebalancer.getAmountIn(amountOut);

        // Give tokens to taker and approve
        deal(address(collateralToken), address(this), amountIn);
        collateralToken.approve(address(auctionRebalancer), amountIn);

        deal(address(debtToken), address(leverageManager), amountOut);

        auctionRebalancer.take(amountOut);

        // Verify token transfers
        assertEq(collateralToken.balanceOf(address(this)), 0);
        assertEq(debtToken.balanceOf(address(this)), amountOut);
    }

    function test_take_UnderCollateralized() public {
        // Create under-collateralized auction
        _setLeverageTokenCollateralRatio(MIN_RATIO - 1);

        _createAuction();

        // Mock exchange rate
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8);

        uint256 amountOut = 1000;
        uint256 amountIn = auctionRebalancer.getAmountIn(amountOut);

        // Give tokens to taker and approve
        deal(address(debtToken), address(this), amountIn);
        debtToken.approve(address(auctionRebalancer), amountIn);

        deal(address(collateralToken), address(leverageManager), amountOut);

        auctionRebalancer.take(amountOut);

        // Verify token transfers
        assertEq(debtToken.balanceOf(address(this)), 0);
        assertEq(collateralToken.balanceOf(address(this)), amountOut);
    }

    function test_take_RevertIf_NoAuction() public {
        vm.expectRevert(IDutchAuctionRebalanceAdapter.AuctionNotValid.selector);
        auctionRebalancer.take(1000);
    }

    function test_take_RevertIf_AuctionEnded() public {
        // Create auction
        _setLeverageTokenCollateralRatio(MAX_RATIO + 1);

        _createAuction();

        // Warp past auction end
        vm.warp(AUCTION_START_TIME + DEFAULT_DURATION + 1);

        vm.expectRevert(IDutchAuctionRebalanceAdapter.AuctionNotValid.selector);
        auctionRebalancer.take(1000);
    }

    function test_take_EndsAuctionWhenLeverageTokenBackToNormalRange() public {
        bytes[] memory returnValues = new bytes[](4);
        returnValues[0] = abi.encode(0, 0, 0, MAX_RATIO + 1);
        returnValues[1] = abi.encode(0, 0, 0, MAX_RATIO + 1);
        returnValues[2] = abi.encode(0, 0, 0, MAX_RATIO + 1);
        returnValues[3] = abi.encode(0, 0, 0, TARGET_RATIO);

        // First call to getLeverageTokenRebalanceStatus during take - still over-collateralized
        vm.mockCalls(
            address(leverageManager),
            abi.encodeWithSelector(leverageManager.getLeverageTokenState.selector, leverageToken),
            returnValues
        );

        // Create over-collateralized auction
        _createAuction();

        // Mock exchange rate
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(0.5e8);

        uint256 amountOut = 1e18;
        uint256 amountIn = auctionRebalancer.getAmountIn(amountOut);

        // Give tokens to taker and approve
        deal(address(collateralToken), address(this), amountIn);
        collateralToken.approve(address(auctionRebalancer), amountIn);
        deal(address(debtToken), address(leverageManager), amountOut);

        auctionRebalancer.take(amountOut);

        // Get auction state
        Auction memory auction = auctionRebalancer.getAuction();

        assertEq(auction.isOverCollateralized, false);
        assertEq(auction.startTimestamp, 0);
        assertEq(auction.endTimestamp, 0);

        // Verify auction is no longer valid
        assertFalse(auctionRebalancer.isAuctionValid());
    }
}
