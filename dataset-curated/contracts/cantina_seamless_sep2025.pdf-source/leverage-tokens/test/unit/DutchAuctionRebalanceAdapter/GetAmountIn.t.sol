// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {DutchAuctionRebalanceAdapterTest} from "./DutchAuctionRebalanceAdapter.t.sol";
import {IDutchAuctionRebalanceAdapter} from "src/interfaces/IDutchAuctionRebalanceAdapter.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract GetAmountInTest is DutchAuctionRebalanceAdapterTest {
    function test_getAmountIn_NoAuction() public view {
        assertEq(auctionRebalancer.getAmountIn(1000), 100);
    }

    function test_getAmountIn_OverCollateralized_AtStart() public {
        // Create over-collateralized auction
        _setLeverageTokenCollateralRatio(MAX_RATIO + 1);

        _createAuction();

        // Mock exchange rate: 1 collateral = 0.5 debt (inverse of 1 debt = 2 collateral)
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(0.5e8);

        // At start, price is DEFAULT_INITIAL_PRICE_MULTIPLIER (110%)
        // amountOut (debt) = 1000
        // baseAmountIn = 1000 * 2 = 2000 (collateral)
        // amountIn = 2000 * 1.1 = 2200
        uint256 amountIn = auctionRebalancer.getAmountIn(1000);
        assertEq(amountIn, 2200);
    }

    function test_getAmountIn_UnderCollateralized_AtStart() public {
        // Create under-collateralized auction
        _setLeverageTokenCollateralRatio(MIN_RATIO - 1);

        _createAuction();

        // Mock exchange rate: 1 collateral = 2 debt
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8);

        // At start, price is DEFAULT_INITIAL_PRICE_MULTIPLIER (110%)
        // amountOut (collateral) = 1000
        // baseAmountIn = 1000 * 2 = 2000 (debt)
        // amountIn = 2000 * 1.1 = 2200
        uint256 amountIn = auctionRebalancer.getAmountIn(1000);
        assertEq(amountIn, 2200);
    }

    function test_getAmountIn_OverCollateralized_AtHalf() public {
        // Create over-collateralized auction
        _setLeverageTokenCollateralRatio(3.1e18);

        _createAuction();

        // Warp to 50% of auction duration
        vm.warp(AUCTION_START_TIME + DEFAULT_DURATION / 2);

        // Mock exchange rate: 1 collateral = 0.5 debt (inverse of 1 debt = 2 collateral)
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(0.5e8);

        // At t=0.5, multiplier is 0.1625 (16.25%)
        // amountOut (debt) = 1000
        // baseAmountIn = 1000 * 2 = 2000 (collateral)
        // amountIn = 2000 * 0.1625 = 325
        uint256 amountIn = auctionRebalancer.getAmountIn(1000);
        assertEq(amountIn, 325);
    }

    function test_getAmountIn_UnderCollateralized_AtHalf() public {
        // Create under-collateralized auction
        _setLeverageTokenCollateralRatio(MIN_RATIO - 1);

        _createAuction();

        // Warp to 50% of auction duration
        vm.warp(AUCTION_START_TIME + DEFAULT_DURATION / 2);

        // Mock exchange rate: 1 collateral = 2 debt
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8);

        // At t=0.5, multiplier is 0.1625 (16.25%)
        // amountOut (collateral) = 1000
        // baseAmountIn = 1000 * 2 = 2000 (debt)
        // amountIn = 2000 * 0.1625 = 325
        uint256 amountIn = auctionRebalancer.getAmountIn(1000);
        assertEq(amountIn, 325);
    }

    function test_getAmountIn_OverCollateralized_AtEnd() public {
        // Create over-collateralized auction
        _setLeverageTokenCollateralRatio(MAX_RATIO + 1);

        _createAuction();

        // Warp to end of auction
        vm.warp(AUCTION_START_TIME + DEFAULT_DURATION);

        // Mock exchange rate: 1 collateral = 0.5 debt (inverse of 1 debt = 2 collateral)
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(0.5e8);

        // At end, price is DEFAULT_MIN_PRICE_MULTIPLIER (100%)
        // amountOut (debt) = 1000
        // baseAmountIn = 1000 * 2 = 2000 (collateral)
        // amountIn = 2000 * 0.1 = 2000
        uint256 amountIn = auctionRebalancer.getAmountIn(1000);
        assertEq(amountIn, 200);
    }

    function test_getAmountIn_UnderCollateralized_AtEnd() public {
        // Create under-collateralized auction
        _setLeverageTokenCollateralRatio(MIN_RATIO - 1);

        _createAuction();

        // Warp to end of auction
        vm.warp(AUCTION_START_TIME + DEFAULT_DURATION);

        // Mock exchange rate: 1 collateral = 2 debt
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8);

        // At end, price is DEFAULT_MIN_PRICE_MULTIPLIER (100%)
        // amountOut (collateral) = 1000
        // baseAmountIn = 1000 * 2 = 2000 (debt)
        // amountIn = 2000 * 0.1 = 200
        uint256 amountIn = auctionRebalancer.getAmountIn(1000);
        assertEq(amountIn, 200);
    }

    function testFuzz_getAmountIn_AmountDecreasesDuringAuction(uint256 timeElapsed1, uint256 timeElapsed2) public {
        timeElapsed1 = bound(timeElapsed1, 0, DEFAULT_DURATION);
        timeElapsed2 = bound(timeElapsed2, 0, DEFAULT_DURATION);
        vm.assume(timeElapsed1 < timeElapsed2);
        vm.assume(timeElapsed2 - timeElapsed1 > 3);

        // Create auction (over-collateralized)
        _setLeverageTokenCollateralRatio(MAX_RATIO + 1);

        _createAuction();

        // Mock exchange rate: 1 collateral = 0.5 debt (inverse of 1 debt = 2 collateral)
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(0.5e8);

        // Check amounts at two different times
        vm.warp(AUCTION_START_TIME + timeElapsed1);
        uint256 amountIn1 = auctionRebalancer.getAmountIn(1e18);

        vm.warp(AUCTION_START_TIME + timeElapsed2);
        uint256 amountIn2 = auctionRebalancer.getAmountIn(1e18);

        // Amount should decrease as time passes
        assertTrue(amountIn1 > amountIn2);
    }

    function testFuzz_getAmountIn_ScalesWithAmountOut(uint256 amountOut) public {
        amountOut = bound(amountOut, 1, 1e30); // Reasonable bounds to avoid overflow

        // Create auction (over-collateralized)
        _setLeverageTokenCollateralRatio(MAX_RATIO + 1);

        _createAuction();

        // Mock exchange rate: 1 collateral = 0.5 debt (inverse of 1 debt = 2 collateral)
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(0.5e8);

        // Get amounts for 1x and 2x
        uint256 amountIn1 = auctionRebalancer.getAmountIn(amountOut);
        uint256 amountIn2 = auctionRebalancer.getAmountIn(amountOut * 2);

        // Amount should scale linearly
        assertLe(amountIn2, amountIn1 * 2 + 1);
        assertGe(amountIn2, amountIn1 * 2);
    }
}
