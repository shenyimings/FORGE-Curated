// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {DutchAuctionRebalanceAdapterTest} from "./DutchAuctionRebalanceAdapter.t.sol";

contract IsAuctionValidTest is DutchAuctionRebalanceAdapterTest {
    function test_isAuctionValid_ReturnsFalse_WhenLeverageTokenNotEligible() public {
        // First set ratio to be over-collateralized (eligible for rebalance)
        _setLeverageTokenCollateralRatio(3.1e18);

        _createAuction();

        // Now change ratio to be within bounds (not eligible)
        _setLeverageTokenCollateralRatio(1.5e18);

        assertFalse(auctionRebalancer.isAuctionValid());
    }

    function test_isAuctionValid_ReturnsFalse_WhenCollateralRatioChangedDirection() public {
        // First set ratio to be over-collateralized
        _setLeverageTokenCollateralRatio(3.1e18);

        _createAuction();

        // Now change ratio to be under-collateralized
        _setLeverageTokenCollateralRatio(0.9e18);

        assertFalse(auctionRebalancer.isAuctionValid());
    }

    function test_isAuctionValid_ReturnsFalse_WhenAuctionExpired() public {
        // First set ratio to be over-collateralized
        _setLeverageTokenCollateralRatio(3.1e18);

        _createAuction();

        // Warp to after auction end
        vm.warp(AUCTION_START_TIME + DEFAULT_DURATION + 1);

        assertFalse(auctionRebalancer.isAuctionValid());
    }

    function test_isAuctionValid_ReturnsTrue_WhenAllConditionsMet() public {
        _setLeverageTokenCollateralRatio(3.1e18);

        _createAuction();

        // Warp to middle of auction
        vm.warp(AUCTION_START_TIME + DEFAULT_DURATION / 2);

        assertTrue(auctionRebalancer.isAuctionValid());
    }

    function testFuzz_isAuctionValid_WhenOverCollateralized(uint256 collateralRatio, uint32 timeElapsed) public {
        // Bound collateral ratio to be over max but prevent overflow
        collateralRatio = bound(collateralRatio, MAX_RATIO + 1, type(uint256).max);
        _setLeverageTokenCollateralRatio(collateralRatio);

        _createAuction();

        // Bound time elapsed to be within duration
        timeElapsed = uint32(bound(timeElapsed, 0, DEFAULT_DURATION));
        vm.warp(AUCTION_START_TIME + timeElapsed);

        assertTrue(auctionRebalancer.isAuctionValid());
    }

    function testFuzz_isAuctionValid_WhenUnderCollateralized(uint256 collateralRatio, uint32 timeElapsed) public {
        // Bound collateral ratio to be under min but not zero
        collateralRatio = bound(collateralRatio, 0, MIN_RATIO - 1);
        _setLeverageTokenCollateralRatio(collateralRatio);

        _createAuction();

        // Bound time elapsed to be within duration
        timeElapsed = uint32(bound(timeElapsed, 0, DEFAULT_DURATION));
        vm.warp(AUCTION_START_TIME + timeElapsed);

        assertTrue(auctionRebalancer.isAuctionValid());
    }

    function testFuzz_isAuctionValid_ReturnsFalse_WhenExpired(uint120 timeElapsed, uint120 duration) public {
        _setLeverageTokenCollateralRatio(3.1e18); // Over-collateralized

        // Bound duration to reasonable values
        duration = uint120(bound(duration, 1 hours, 7 days));

        // Set duration
        vm.prank(owner);
        auctionRebalancer.exposed_setAuctionDuration(duration);

        _createAuction();

        // Ensure timeElapsed is greater than duration
        timeElapsed = uint120(bound(timeElapsed, duration + 1, duration + 7 days));
        vm.warp(AUCTION_START_TIME + timeElapsed);

        assertFalse(auctionRebalancer.isAuctionValid());
    }

    function test_isAuctionValid_ReturnsFalse_WhenNotEligible() public {
        auctionRebalancer.mock_isEligible(false);
        assertFalse(auctionRebalancer.isAuctionValid());
    }
}
