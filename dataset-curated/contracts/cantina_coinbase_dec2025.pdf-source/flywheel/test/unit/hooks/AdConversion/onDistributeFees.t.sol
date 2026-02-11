// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../../../../src/Flywheel.sol";
import {AdConversion} from "../../../../src/hooks/AdConversion.sol";
import {AdConversionTestBase} from "../../../lib/AdConversionTestBase.sol";
import {console} from "forge-std/console.sol";

contract OnDistributeFeesTest is AdConversionTestBase {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when caller is not the attribution provider
    /// @param unauthorizedCaller Unauthorized caller address (not attribution provider)
    /// @param recipient Fee recipient address
    function test_revert_unauthorizedCaller(address unauthorizedCaller, address recipient) public {
        vm.assume(unauthorizedCaller != attributionProvider1);
        vm.assume(recipient != address(0));

        // Create campaign with attribution provider
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), LARGE_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Prepare fee distribution hook data (only recipient is needed)
        bytes memory hookData = abi.encode(recipient);

        // Should revert when called by unauthorized caller
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnDistributeFees(unauthorizedCaller, testCampaign, address(tokenA), hookData);
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Successfully processes fee distribution by attribution provider with fuzzed amounts
    /// @param recipient Fee recipient address
    /// @param feeBps Fee basis points (constrained to reasonable range)
    /// @param payoutAmount Payout amount to generate fees from
    function test_success_authorizedDistribution(address recipient, uint16 feeBps, uint256 payoutAmount) public {
        vm.assume(recipient != address(0));
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_REASONABLE_FEE_BPS));
        payoutAmount = bound(payoutAmount, MIN_ATTRIBUTION_AMOUNT, MAX_ATTRIBUTION_AMOUNT);

        // Create campaign with custom fee
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps // Use fuzzed fee
        );
        fundCampaign(testCampaign, address(tokenA), LARGE_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Generate fees using utility function
        uint256 expectedFeeAmount = generateFeesWithSingleAttribution(
            testCampaign, address(tokenA), attributionProvider1, payoutAmount, REF_CODE_1
        );

        // Prepare fee distribution hook data
        bytes memory hookData = abi.encode(recipient);

        // Should succeed when called by the authorized attribution provider
        Flywheel.Distribution[] memory distributions =
            callHookOnDistributeFees(attributionProvider1, testCampaign, address(tokenA), hookData);

        // Verify successful distribution with correct fee amount
        assertEq(distributions.length, 1, "Should return one distribution");
        assertEq(distributions[0].recipient, recipient, "Should distribute to correct recipient");
        assertEq(distributions[0].amount, expectedFeeAmount, "Should distribute correct fee amount");
        assertEq(distributions[0].key, bytes32(bytes20(attributionProvider1)), "Should use correct key");
    }

    /// @dev Successfully processes fee distribution with provider as recipient
    /// @param feeBps Fee basis points (constrained to reasonable range)
    /// @param payoutAmount Payout amount to generate fees from
    function test_success_providerAsRecipient(uint16 feeBps, uint256 payoutAmount) public {
        feeBps = uint16(bound(feeBps, 1, MAX_REASONABLE_FEE_BPS)); // 0.01% to 10%
        payoutAmount = bound(payoutAmount, MIN_ATTRIBUTION_AMOUNT, MAX_ATTRIBUTION_AMOUNT);

        // Create campaign with custom fee
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );
        fundCampaign(testCampaign, address(tokenA), LARGE_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Generate fees using utility function
        uint256 expectedFeeAmount = generateFeesWithSingleAttribution(
            testCampaign, address(tokenA), attributionProvider1, payoutAmount, REF_CODE_1
        );

        // Prepare fee distribution hook data (provider distributes to themselves)
        bytes memory hookData = abi.encode(attributionProvider1);

        Flywheel.Distribution[] memory distributions =
            callHookOnDistributeFees(attributionProvider1, testCampaign, address(tokenA), hookData);

        // Verify distribution with correct amount
        assertEq(distributions.length, 1, "Should return one distribution");
        assertEq(distributions[0].recipient, attributionProvider1, "Should distribute to provider as recipient");
        assertEq(distributions[0].amount, expectedFeeAmount, "Should distribute correct fee amount");
        assertEq(distributions[0].key, bytes32(bytes20(attributionProvider1)), "Should use provider key");
    }

    /// @dev Successfully processes fee distribution with different recipient
    /// @param differentRecipient Different fee recipient address
    /// @param feeBps Fee basis points (constrained to reasonable range)
    /// @param payoutAmount Payout amount to generate fees from
    function test_success_differentRecipient(address differentRecipient, uint16 feeBps, uint256 payoutAmount) public {
        vm.assume(differentRecipient != address(0));
        vm.assume(differentRecipient != attributionProvider1);
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_REASONABLE_FEE_BPS));
        payoutAmount = bound(payoutAmount, MIN_ATTRIBUTION_AMOUNT, MAX_ATTRIBUTION_AMOUNT);

        // Create campaign with custom fee
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );
        fundCampaign(testCampaign, address(tokenA), LARGE_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Generate fees using utility function
        uint256 expectedFeeAmount = generateFeesWithSingleAttribution(
            testCampaign, address(tokenA), attributionProvider1, payoutAmount, REF_CODE_2
        );

        // Prepare fee distribution hook data (distribute to different recipient)
        bytes memory hookData = abi.encode(differentRecipient);

        // Should succeed with different recipient
        Flywheel.Distribution[] memory distributions =
            callHookOnDistributeFees(attributionProvider1, testCampaign, address(tokenA), hookData);

        // Verify distribution to different recipient with correct amount
        assertEq(distributions.length, 1, "Should return one distribution");
        assertEq(distributions[0].recipient, differentRecipient, "Should distribute to different recipient");
        assertEq(distributions[0].amount, expectedFeeAmount, "Should distribute correct fee amount");
        assertEq(distributions[0].key, bytes32(bytes20(attributionProvider1)), "Should use provider key");
    }

    /// @dev Successfully processes fee distribution with multiple attributions
    /// @param recipient Fee recipient address
    function test_success_multipleAttributions(address recipient) public {
        vm.assume(recipient != address(0));

        uint16 feeBps = DEFAULT_FEE_BPS; // Use constant
        uint256 baseAmount = MULTI_ATTRIBUTION_BASE_AMOUNT; // Use constant for calculated base amount

        // Create campaign with custom fee
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );
        fundCampaign(testCampaign, address(tokenA), LARGE_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Generate fees using utility function for multiple attributions
        uint256 expectedFeeAmount =
            generateFeesWithMultipleAttributions(testCampaign, address(tokenA), attributionProvider1, baseAmount);

        bytes memory hookData = abi.encode(recipient);

        Flywheel.Distribution[] memory distributions =
            callHookOnDistributeFees(attributionProvider1, testCampaign, address(tokenA), hookData);

        // Verify accumulated fees from multiple attributions
        assertEq(distributions.length, 1, "Should return one distribution");
        assertEq(distributions[0].recipient, recipient, "Should distribute to correct recipient");
        assertEq(distributions[0].amount, expectedFeeAmount, "Should distribute total accumulated fee amount");
        assertEq(distributions[0].key, bytes32(bytes20(attributionProvider1)), "Should use provider key");
    }

    /// @dev Successfully processes fee distribution when no accumulated fees exist (zero amount test)
    /// @param recipient Fee recipient address
    function test_success_zeroAccumulatedFees(address recipient) public {
        vm.assume(recipient != address(0));

        // Create campaign without making any send calls to accumulate fees
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), LARGE_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Prepare fee distribution hook data
        bytes memory hookData = abi.encode(recipient);

        // Should succeed even without accumulated fees (returns 0 amount)
        Flywheel.Distribution[] memory distributions =
            callHookOnDistributeFees(attributionProvider1, testCampaign, address(tokenA), hookData);

        // Verify distribution with zero amount
        assertEq(distributions.length, 1, "Should return one distribution");
        assertEq(distributions[0].recipient, recipient, "Should distribute to correct recipient");
        assertEq(distributions[0].amount, 0, "Should have zero amount when no fees allocated");
        assertEq(distributions[0].key, bytes32(bytes20(attributionProvider1)), "Should use provider key");
    }

    /// @dev Handles fee distribution from different campaigns by same provider
    /// @param recipient Fee recipient address
    /// @param payoutAmount1 Payout amount for campaign 1
    /// @param payoutAmount2 Payout amount for campaign 2
    /// @param feeBps1 Fee basis points for campaign 1
    /// @param feeBps2 Fee basis points for campaign 2
    function test_edge_multipleCampaigns(
        address recipient,
        uint256 payoutAmount1,
        uint256 payoutAmount2,
        uint16 feeBps1,
        uint16 feeBps2
    ) public {
        vm.assume(recipient != address(0));

        // Use more restrictive ranges to avoid vm.assume rejections
        feeBps1 = uint16(bound(feeBps1, MIN_FEE_BPS, MAX_REASONABLE_FEE_BPS));
        feeBps2 = uint16(bound(feeBps2, MIN_FEE_BPS, MAX_REASONABLE_FEE_BPS));

        payoutAmount1 = bound(payoutAmount1, MIN_ATTRIBUTION_AMOUNT, MAX_ATTRIBUTION_AMOUNT);
        payoutAmount2 = bound(payoutAmount2, MIN_ATTRIBUTION_AMOUNT, MAX_ATTRIBUTION_AMOUNT);

        // Create first campaign
        address testCampaign1 = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps1
        );
        fundCampaign(testCampaign1, address(tokenA), LARGE_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign1, attributionProvider1);

        // Create second campaign with same provider but different fee
        address testCampaign2 = createCampaign(
            advertiser2,
            attributionProvider1, // Same provider
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps2
        );
        fundCampaign(testCampaign2, address(tokenA), LARGE_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign2, attributionProvider1);

        // Generate fees for both campaigns using utility functions
        uint256 expectedFeeAmount1 = generateFeesWithSingleAttribution(
            testCampaign1, address(tokenA), attributionProvider1, payoutAmount1, REF_CODE_1
        );

        uint256 expectedFeeAmount2 = generateFeesWithSingleAttribution(
            testCampaign2, address(tokenA), attributionProvider1, payoutAmount2, REF_CODE_2
        );

        // Prepare fee distribution hook data
        bytes memory hookData = abi.encode(recipient);

        // Test fee distribution from both campaigns
        Flywheel.Distribution[] memory distributions1 =
            callHookOnDistributeFees(attributionProvider1, testCampaign1, address(tokenA), hookData);
        Flywheel.Distribution[] memory distributions2 =
            callHookOnDistributeFees(attributionProvider1, testCampaign2, address(tokenA), hookData);

        // Verify both campaigns handle fee distribution independently with correct amounts
        assertEq(distributions1.length, 1, "Campaign 1 should return one distribution");
        assertEq(distributions1[0].recipient, recipient, "Campaign 1 should distribute to correct recipient");
        assertEq(distributions1[0].amount, expectedFeeAmount1, "Campaign 1 should distribute correct fee amount");
        assertEq(distributions1[0].key, bytes32(bytes20(attributionProvider1)), "Campaign 1 should use provider key");

        assertEq(distributions2.length, 1, "Campaign 2 should return one distribution");
        assertEq(distributions2[0].recipient, recipient, "Campaign 2 should distribute to correct recipient");
        assertEq(distributions2[0].amount, expectedFeeAmount2, "Campaign 2 should distribute correct fee amount");
        assertEq(distributions2[0].key, bytes32(bytes20(attributionProvider1)), "Campaign 2 should use provider key");
    }
}
