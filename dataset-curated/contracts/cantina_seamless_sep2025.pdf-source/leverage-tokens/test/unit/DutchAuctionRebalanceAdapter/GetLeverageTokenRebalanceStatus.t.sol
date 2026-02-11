// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {DutchAuctionRebalanceAdapterTest} from "./DutchAuctionRebalanceAdapter.t.sol";

contract GetLeverageTokenRebalanceStatusTest is DutchAuctionRebalanceAdapterTest {
    function test_getLeverageTokenRebalanceStatus_Eligible_UnderCollateralized() public {
        // Set current ratio to be below min (e.g., 1.4x)
        _setLeverageTokenCollateralRatio(1.4e18);

        (bool isEligible, bool isOverCollateralized) = auctionRebalancer.getLeverageTokenRebalanceStatus();
        assertTrue(isEligible);
        assertFalse(isOverCollateralized);
    }

    function test_getLeverageTokenRebalanceStatus_Eligible_OverCollateralized() public {
        // Set current ratio to be above max (e.g., 3.1x)
        _setLeverageTokenCollateralRatio(3.1e18);

        (bool isEligible, bool isOverCollateralized) = auctionRebalancer.getLeverageTokenRebalanceStatus();
        assertTrue(isEligible);
        assertTrue(isOverCollateralized);
    }

    function testFuzz_getLeverageTokenRebalanceStatus(uint256 targetRatio, uint256 currentRatio) public {
        _mockLeverageTokenTargetCollateralRatio(targetRatio);
        _setLeverageTokenCollateralRatio(currentRatio);

        (bool isEligible, bool isOverCollateralized) = auctionRebalancer.getLeverageTokenRebalanceStatus();

        assertTrue(isEligible);

        if (currentRatio < targetRatio) {
            assertFalse(isOverCollateralized);
        } else if (currentRatio > targetRatio) {
            assertTrue(isOverCollateralized);
        }
    }
}
