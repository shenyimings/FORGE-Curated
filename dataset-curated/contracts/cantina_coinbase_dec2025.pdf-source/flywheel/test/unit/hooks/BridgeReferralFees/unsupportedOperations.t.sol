// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {BridgeReferralFeesTest} from "../../../lib/BridgeReferralFeesTest.sol";

contract UnsupportedOperationsTest is BridgeReferralFeesTest {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when onAllocate is called (BridgeReferralFees uses immediate payouts only)
    function test_onAllocate_revert_unsupported() public {
        vm.expectRevert();
        vm.prank(address(flywheel));
        bridgeReferralFees.onAllocate(address(this), bridgeReferralFeesCampaign, address(usdc), "");
    }

    /// @dev Reverts when onDeallocate is called (BridgeReferralFees uses immediate payouts only)
    function test_onDeallocate_revert_unsupported() public {
        vm.expectRevert();
        vm.prank(address(flywheel));
        bridgeReferralFees.onDeallocate(address(this), bridgeReferralFeesCampaign, address(usdc), "");
    }

    /// @dev Reverts when onDistribute is called (BridgeReferralFees uses immediate payouts only)
    function test_onDistribute_revert_unsupported() public {
        vm.expectRevert();
        vm.prank(address(flywheel));
        bridgeReferralFees.onDistribute(address(this), bridgeReferralFeesCampaign, address(usdc), "");
    }
}
