// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../../../../src/Flywheel.sol";
import {AdConversion} from "../../../../src/hooks/AdConversion.sol";
import {AdConversionTestBase} from "../../../lib/AdConversionTestBase.sol";

contract OnWithdrawFundsTest is AdConversionTestBase {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when caller is not the advertiser
    /// @param unauthorizedCaller Unauthorized caller address (not advertiser)
    /// @param recipient Withdrawal recipient address
    /// @param amount Withdrawal amount
    function test_revert_unauthorizedCaller(address unauthorizedCaller, address recipient, uint256 amount) public {
        // Constrain inputs to reasonable ranges
        amount = bound(amount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_CAMPAIGN_FUNDING);
        vm.assume(unauthorizedCaller != advertiser1);
        vm.assume(recipient != address(0));

        // Create and finalize campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);
        finalizeCampaign(testCampaign, attributionProvider1);

        // Prepare withdrawal hook data
        bytes memory hookData = abi.encode(recipient, amount);

        // Should revert when called by unauthorized caller
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnWithdrawFunds(unauthorizedCaller, testCampaign, address(tokenA), hookData);
    }

    /// @dev Reverts when campaign is not in FINALIZED status
    /// @param recipient Withdrawal recipient address
    /// @param amount Withdrawal amount
    /// @param currentStatus Current non-finalized campaign status
    function test_revert_campaignNotFinalized(address recipient, uint256 amount, uint8 currentStatus) public {
        // Constrain inputs to reasonable ranges
        amount = bound(amount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_CAMPAIGN_FUNDING);
        currentStatus = uint8(bound(currentStatus, 0, 2)); // INACTIVE(0), ACTIVE(1), FINALIZING(2) - NOT FINALIZED(3)
        vm.assume(recipient != address(0));

        // Create campaign and set to non-finalized status
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        if (currentStatus >= 1) {
            activateCampaign(testCampaign, attributionProvider1);
        }
        if (currentStatus >= 2) {
            // Set to FINALIZING but don't complete finalization
            vm.prank(advertiser1);
            flywheel.updateStatus(testCampaign, Flywheel.CampaignStatus.FINALIZING, "");
        }
        // Don't finalize - should be in INACTIVE, ACTIVE, or FINALIZING status

        // Prepare withdrawal hook data
        bytes memory hookData = abi.encode(recipient, amount);

        // Should revert when campaign is not finalized
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnWithdrawFunds(advertiser1, testCampaign, address(tokenA), hookData);
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Successfully processes fund withdrawal by advertiser from finalized campaign
    /// @param recipient Withdrawal recipient address
    /// @param amount Withdrawal amount
    function test_success_authorizedWithdrawal(address recipient, uint256 amount) public {
        // Constrain inputs to reasonable ranges
        amount = bound(amount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_CAMPAIGN_FUNDING);
        vm.assume(recipient != address(0));

        // Create and finalize campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);
        finalizeCampaign(testCampaign, attributionProvider1);

        // Prepare withdrawal hook data
        bytes memory hookData = abi.encode(recipient, amount);

        // Should succeed when called by authorized advertiser on finalized campaign
        Flywheel.Payout memory payout = callHookOnWithdrawFunds(advertiser1, testCampaign, address(tokenA), hookData);

        // Verify successful withdrawal
        assertEq(payout.recipient, recipient, "Should withdraw to correct recipient");
        assertEq(payout.amount, amount, "Should withdraw correct amount");
        assertEq(payout.extraData, "", "Should have empty extra data");
    }

    /// @dev Successfully processes withdrawal with advertiser as recipient
    /// @param amount Withdrawal amount
    function test_success_advertiserAsRecipient(uint256 amount) public {
        // Constrain inputs to reasonable ranges
        amount = bound(amount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_CAMPAIGN_FUNDING);

        // Create and finalize campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);
        finalizeCampaign(testCampaign, attributionProvider1);

        // Prepare withdrawal hook data (advertiser withdraws to themselves)
        bytes memory hookData = abi.encode(advertiser1, amount);

        // Should succeed with advertiser as recipient
        Flywheel.Payout memory payout = callHookOnWithdrawFunds(advertiser1, testCampaign, address(tokenA), hookData);

        // Verify withdrawal to advertiser
        assertEq(payout.recipient, advertiser1, "Should withdraw to advertiser as recipient");
        assertEq(payout.amount, amount, "Should withdraw correct amount");
        assertEq(payout.extraData, "", "Should have empty extra data");
    }

    /// @dev Successfully processes withdrawal with different recipient
    /// @param differentRecipient Different withdrawal recipient address
    /// @param amount Withdrawal amount
    function test_success_differentRecipient(address differentRecipient, uint256 amount) public {
        // Constrain inputs
        amount = bound(amount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_CAMPAIGN_FUNDING);
        vm.assume(differentRecipient != address(0));
        vm.assume(differentRecipient != advertiser1);

        // Create and finalize campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);
        finalizeCampaign(testCampaign, attributionProvider1);

        // Prepare withdrawal hook data (withdraw to different recipient)
        bytes memory hookData = abi.encode(differentRecipient, amount);

        // Should succeed with different recipient
        Flywheel.Payout memory payout = callHookOnWithdrawFunds(advertiser1, testCampaign, address(tokenA), hookData);

        // Verify withdrawal to different recipient
        assertEq(payout.recipient, differentRecipient, "Should withdraw to different recipient");
        assertEq(payout.amount, amount, "Should withdraw correct amount");
        assertEq(payout.extraData, "", "Should have empty extra data");
    }

    /// @dev Successfully processes withdrawal with native token
    /// @param recipient Withdrawal recipient address
    /// @param amount Withdrawal amount
    function test_success_nativeToken(address recipient, uint256 amount) public {
        // Constrain inputs
        amount = bound(amount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_CAMPAIGN_FUNDING);
        vm.assume(recipient != address(0));

        // Create and finalize campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);
        finalizeCampaign(testCampaign, attributionProvider1);

        // Prepare withdrawal hook data
        bytes memory hookData = abi.encode(recipient, amount);

        // Test with native token (address(0))
        Flywheel.Payout memory payout = callHookOnWithdrawFunds(advertiser1, testCampaign, address(0), hookData);

        // Verify withdrawal for native token
        assertEq(payout.recipient, recipient, "Should withdraw to correct recipient");
        assertEq(payout.amount, amount, "Should withdraw correct amount");
        assertEq(payout.extraData, "", "Should have empty extra data");
    }

    // ========================================
    // EDGE CASES
    // ========================================

    /// @dev Handles withdrawal of zero amount
    /// @param recipient Withdrawal recipient address
    function test_edge_zeroAmount(address recipient) public {
        vm.assume(recipient != address(0));

        // Create and finalize campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);
        finalizeCampaign(testCampaign, attributionProvider1);

        // Prepare withdrawal hook data with zero amount
        bytes memory hookData = abi.encode(recipient, 0);

        // Should succeed even with zero amount
        Flywheel.Payout memory payout = callHookOnWithdrawFunds(advertiser1, testCampaign, address(tokenA), hookData);

        // Verify zero amount withdrawal
        assertEq(payout.recipient, recipient, "Should withdraw to correct recipient");
        assertEq(payout.amount, 0, "Should withdraw zero amount");
        assertEq(payout.extraData, "", "Should have empty extra data");
    }

    /// @dev Handles withdrawal of maximum uint256 amount
    /// @param recipient Withdrawal recipient address
    function test_edge_maximumAmount(address recipient) public {
        vm.assume(recipient != address(0));

        // Create and finalize campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);
        finalizeCampaign(testCampaign, attributionProvider1);

        // Prepare withdrawal hook data with maximum amount
        uint256 maxAmount = type(uint256).max;
        bytes memory hookData = abi.encode(recipient, maxAmount);

        // Should succeed with maximum amount (hook doesn't validate against campaign balance)
        Flywheel.Payout memory payout = callHookOnWithdrawFunds(advertiser1, testCampaign, address(tokenA), hookData);

        // Verify maximum amount withdrawal
        assertEq(payout.recipient, recipient, "Should withdraw to correct recipient");
        assertEq(payout.amount, maxAmount, "Should withdraw maximum amount");
        assertEq(payout.extraData, "", "Should have empty extra data");
    }

    /// @dev Handles multiple withdrawals from same campaign
    /// @param recipient1 First withdrawal recipient
    /// @param recipient2 Second withdrawal recipient
    /// @param amount1 First withdrawal amount
    /// @param amount2 Second withdrawal amount
    function test_edge_multipleWithdrawals(address recipient1, address recipient2, uint256 amount1, uint256 amount2)
        public
    {
        // Constrain inputs
        amount1 = bound(amount1, MIN_ATTRIBUTION_AMOUNT, DEFAULT_CAMPAIGN_FUNDING / 2);
        amount2 = bound(amount2, MIN_ATTRIBUTION_AMOUNT, DEFAULT_CAMPAIGN_FUNDING / 2);
        vm.assume(recipient1 != address(0));
        vm.assume(recipient2 != address(0));

        // Create and finalize campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);
        finalizeCampaign(testCampaign, attributionProvider1);

        // First withdrawal
        bytes memory hookData1 = abi.encode(recipient1, amount1);
        Flywheel.Payout memory payout1 = callHookOnWithdrawFunds(advertiser1, testCampaign, address(tokenA), hookData1);

        // Second withdrawal
        bytes memory hookData2 = abi.encode(recipient2, amount2);
        Flywheel.Payout memory payout2 = callHookOnWithdrawFunds(advertiser1, testCampaign, address(tokenA), hookData2);

        // Verify both withdrawals succeed independently
        assertEq(payout1.recipient, recipient1, "First withdrawal should go to recipient1");
        assertEq(payout1.amount, amount1, "First withdrawal should have amount1");
        assertEq(payout1.extraData, "", "First withdrawal should have empty extra data");

        assertEq(payout2.recipient, recipient2, "Second withdrawal should go to recipient2");
        assertEq(payout2.amount, amount2, "Second withdrawal should have amount2");
        assertEq(payout2.extraData, "", "Second withdrawal should have empty extra data");
    }
}
