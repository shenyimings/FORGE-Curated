// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../../../../src/Flywheel.sol";
import {BridgeReferralFees} from "../../../../src/hooks/BridgeReferralFees.sol";
import {BridgeReferralFeesTest} from "../../../lib/BridgeReferralFeesTest.sol";

contract OnCreateCampaignTest is BridgeReferralFeesTest {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when nonce is not zero (only one campaign allowed)
    /// @param nonZeroNonce Any nonce value except zero
    function test_revert_nonZeroNonce(uint256 nonZeroNonce) public {
        vm.assume(nonZeroNonce != 0);

        vm.expectRevert(BridgeReferralFees.InvalidCampaignInitialization.selector);
        flywheel.createCampaign(address(bridgeReferralFees), nonZeroNonce, "");
    }

    /// @dev Reverts when hookData is not empty (no configuration allowed)
    /// @param nonEmptyHookData Any non-empty bytes data
    function test_revert_nonEmptyHookData(bytes memory nonEmptyHookData) public {
        vm.assume(nonEmptyHookData.length > 0);

        vm.expectRevert(BridgeReferralFees.InvalidCampaignInitialization.selector);
        flywheel.createCampaign(address(bridgeReferralFees), 0, nonEmptyHookData);
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Accepts campaign creation with nonce zero and empty hookData
    function test_success_validParameters() public {
        // Create a new BridgeReferralFees contract to get a different campaign address
        (, address newCampaign) = _createBridgeReferralFeesCampaign();

        // Verify campaign was created successfully
        assertTrue(newCampaign != address(0));

        // Verify campaign starts in INACTIVE status
        assertEq(uint256(flywheel.campaignStatus(newCampaign)), uint256(Flywheel.CampaignStatus.INACTIVE));
    }
}
