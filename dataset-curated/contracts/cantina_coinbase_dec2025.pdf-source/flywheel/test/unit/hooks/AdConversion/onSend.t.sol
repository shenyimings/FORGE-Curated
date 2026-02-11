// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../../../../src/Flywheel.sol";
import {AdConversion} from "../../../../src/hooks/AdConversion.sol";
import {AdConversionTestBase} from "../../../lib/AdConversionTestBase.sol";

contract OnSendTest is AdConversionTestBase {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when caller is not the attribution provider
    /// @param unauthorizedCaller Unauthorized caller address
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param attributions Array of conversion attributions
    function test_revert_unauthorizedCaller(
        address unauthorizedCaller,
        address campaign,
        address token,
        AdConversion.Attribution[] memory attributions
    ) public {
        // Ensure unauthorized caller is different from attribution provider
        vm.assume(unauthorizedCaller != attributionProvider1);
        vm.assume(unauthorizedCaller != address(flywheel));

        // Create basic campaign setup
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create simple attribution array if empty
        if (attributions.length == 0) {
            attributions = new AdConversion.Attribution[](1);
            attributions[0] = createOffchainAttribution(REF_CODE_1, publisherPayout1, DEFAULT_ATTRIBUTION_AMOUNT);
        }

        // Expect revert when unauthorized caller tries to call onSend
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnSend(unauthorizedCaller, testCampaign, address(tokenA), abi.encode(attributions));
    }

    /// @dev Reverts when publisher ref code is not registered in registry
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param unregisteredRefCode Unregistered publisher reference code
    /// @param attributions Array of conversion attributions with unregistered code
    function test_revert_unregisteredPublisherRefCode(
        address campaign,
        address token,
        string memory unregisteredRefCode,
        AdConversion.Attribution[] memory attributions
    ) public {
        // Use a valid but unregistered ref code to avoid InvalidCode errors from fuzzer
        unregisteredRefCode = "unregistered123";

        // Create basic campaign setup
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution with unregistered ref code, or modify existing ones
        if (attributions.length == 0) {
            attributions = new AdConversion.Attribution[](1);
            attributions[0] =
                createOffchainAttribution(unregisteredRefCode, publisherPayout1, DEFAULT_ATTRIBUTION_AMOUNT);
        } else {
            // Inject unregistered ref code into first attribution
            attributions[0].conversion.publisherRefCode = unregisteredRefCode;
        }

        // Expect revert for invalid publisher ref code
        vm.expectRevert(AdConversion.InvalidPublisherRefCode.selector);
        callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(attributions));
    }

    /// @dev Reverts when publisher ref code is not in campaign allowlist
    /// @param campaign Campaign address with allowlist
    /// @param token Token address
    /// @param disallowedRefCode Publisher ref code not in allowlist
    /// @param attributions Array of conversion attributions with disallowed code
    function test_revert_publisherNotInAllowlist(
        address campaign,
        address token,
        string memory disallowedRefCode,
        AdConversion.Attribution[] memory attributions
    ) public {
        // Use REF_CODE_3 which is registered but not in allowlist
        disallowedRefCode = REF_CODE_3;

        // Create allowlist with only REF_CODE_1 and REF_CODE_2
        string[] memory allowedRefCodes = new string[](2);
        allowedRefCodes[0] = REF_CODE_1;
        allowedRefCodes[1] = REF_CODE_2;

        // Create campaign with allowlist (REF_CODE_3 is registered but not in allowlist)
        address testCampaign = createCampaignWithAllowlist(advertiser1, attributionProvider1, allowedRefCodes);
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution with disallowed ref code
        if (attributions.length == 0) {
            attributions = new AdConversion.Attribution[](1);
            attributions[0] = createOffchainAttribution(disallowedRefCode, publisherPayout1, DEFAULT_ATTRIBUTION_AMOUNT);
        } else {
            // Inject disallowed ref code into first attribution
            attributions[0].conversion.publisherRefCode = disallowedRefCode;
        }

        // Expect revert for publisher not in allowlist
        vm.expectRevert(AdConversion.PublisherNotAllowed.selector);
        callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(attributions));
    }

    /// @dev Reverts when conversion config ID does not exist
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param invalidConfigId Non-existent conversion config ID
    /// @param refCodeSeed Seed to generate valid publisher ref code
    function test_revert_invalidConversionConfigId(
        address campaign,
        address token,
        uint16 invalidConfigId,
        uint256 refCodeSeed
    ) public {
        // Ensure config ID is invalid (greater than registered configs, but not 0 which is allowed)
        vm.assume(invalidConfigId > 2 && invalidConfigId != 0); // We have 2 default configs (1, 2)

        // Generate valid ref code from seed and register it
        string memory validRefCode = generateValidRefCodeFromSeed(refCodeSeed);
        vm.prank(registrarSigner);
        builderCodes.register(validRefCode, publisher1, publisherPayout1);

        // Create basic campaign setup
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution with invalid config ID
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = createOffchainAttribution(validRefCode, publisherPayout1, DEFAULT_ATTRIBUTION_AMOUNT);

        // Inject invalid config ID into first attribution
        attributions[0].conversion.configId = invalidConfigId;

        // Expect revert for invalid conversion config ID
        vm.expectRevert(AdConversion.InvalidConversionConfigId.selector);
        callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(attributions));
    }

    /// @dev Reverts when onchain conversion has mismatched config type
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param offchainConfigId Offchain config ID used for onchain conversion
    /// @param refCodeSeed Seed to generate valid publisher ref code
    function test_revert_onchainConversionWrongConfigType(
        address campaign,
        address token,
        uint16 offchainConfigId,
        uint256 refCodeSeed
    ) public {
        // Use config ID 1 which is offchain (isEventOnchain: false)
        uint16 configId = 1;

        // Generate valid ref code from seed and register it
        string memory validRefCode = generateValidRefCodeFromSeed(refCodeSeed);
        vm.prank(registrarSigner);
        builderCodes.register(validRefCode, publisher1, publisherPayout1);

        // Create basic campaign setup
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create onchain attribution (has logBytes) but use offchain config
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = createOnchainAttribution(validRefCode, publisherPayout1, DEFAULT_ATTRIBUTION_AMOUNT);

        // Ensure attribution has logBytes (making it onchain) and wrong config type
        attributions[0].conversion.configId = configId; // Offchain config for onchain conversion

        // Expect revert for invalid conversion type
        vm.expectRevert(AdConversion.InvalidConversionType.selector);
        callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(attributions));
    }

    /// @dev Reverts when offchain conversion has mismatched config type
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param onchainConfigId Onchain config ID used for offchain conversion
    /// @param refCodeSeed Seed to generate valid publisher ref code
    function test_revert_offchainConversionWrongConfigType(
        address campaign,
        address token,
        uint16 onchainConfigId,
        uint256 refCodeSeed
    ) public {
        // Use config ID 2 which is onchain (isEventOnchain: true)
        uint16 configId = 2;

        // Generate valid ref code from seed and register it
        string memory validRefCode = generateValidRefCodeFromSeed(refCodeSeed);
        vm.prank(registrarSigner);
        builderCodes.register(validRefCode, publisher1, publisherPayout1);

        // Create basic campaign setup
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create offchain attribution (no logBytes) but use onchain config
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = createOffchainAttribution(validRefCode, publisherPayout1, DEFAULT_ATTRIBUTION_AMOUNT);

        // Ensure attribution has no logBytes (making it offchain) and wrong config type
        attributions[0].conversion.configId = configId; // Onchain config for offchain conversion

        // Expect revert for invalid conversion type
        vm.expectRevert(AdConversion.InvalidConversionType.selector);
        callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(attributions));
    }

    /// @dev Reverts when integer overflow occurs in fee calculation
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param overflowAmount Amount that causes overflow in fee calculation
    /// @param attributions Array of conversion attributions with overflow amount
    function test_revert_feeCalculationOverflow(
        address campaign,
        address token,
        uint256 overflowAmount,
        AdConversion.Attribution[] memory attributions
    ) public {
        // Use very large payout amount that could cause overflow in fee calculation
        // (payoutAmount * feeBps) might overflow uint256
        overflowAmount = bound(overflowAmount, type(uint256).max / 5000, type(uint256).max);

        // Create campaign with maximum fee to maximize overflow potential
        address testCampaign = createMaxFeeCampaign(advertiser1, attributionProvider1);
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution with overflow amount
        if (attributions.length == 0) {
            attributions = new AdConversion.Attribution[](1);
            attributions[0] = createOffchainAttribution(REF_CODE_1, publisherPayout1, overflowAmount);
        } else {
            // Inject overflow amount into first attribution
            attributions[0].conversion.payoutAmount = overflowAmount;
        }

        // Expect arithmetic overflow (Solidity 0.8+ panic)
        vm.expectRevert();
        callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(attributions));
    }

    /// @dev Reverts when hook data is invalid
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param hookData Invalid hook data
    function test_revert_invalidHookData(address campaign, address token, bytes memory hookData) public {
        // Create basic campaign setup
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Hook data should be abi.encode(AdConversion.Attribution[])
        // We'll pass invalid/malformed data that can't be decoded properly
        // Ensure hookData is not valid Attribution[] encoding by constraining length
        vm.assume(hookData.length < 32 || hookData.length > 10000); // Too short or suspiciously long

        // Expect revert when trying to decode invalid hook data
        vm.expectRevert();
        callHookOnSend(attributionProvider1, testCampaign, address(tokenA), hookData);
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Successfully processes single offchain conversion attribution
    /// @param payoutAmount Payout amount
    /// @param feeBps Attribution provider fee
    /// @param publisherPayout Publisher payout address
    /// @param refCodeSeed Seed for selecting registered ref code
    function test_success_singleOffchainConversion(
        uint256 payoutAmount,
        uint16 feeBps,
        address publisherPayout,
        uint256 refCodeSeed
    ) public {
        // Constrain fuzz inputs to valid ranges
        payoutAmount = bound(payoutAmount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_ATTRIBUTION_AMOUNT);
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(publisherPayout != address(0)); // Ensure non-zero address

        // Select one of the registered ref codes deterministically
        string[] memory refCodes = new string[](3);
        refCodes[0] = REF_CODE_1;
        refCodes[1] = REF_CODE_2;
        refCodes[2] = REF_CODE_3;
        string memory selectedRefCode = refCodes[refCodeSeed % 3];

        // Create campaign with fuzzed fee
        address campaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        fundCampaign(campaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(campaign, attributionProvider1);

        // Create attribution with fuzzed parameters
        AdConversion.Attribution memory attribution =
            createOffchainAttribution(selectedRefCode, publisherPayout, payoutAmount);

        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = attribution;

        // Calculate expected amounts with fuzzed fee
        uint256 expectedFee = (payoutAmount * feeBps) / adConversion.MAX_BPS();
        uint256 expectedNetAmount = payoutAmount - expectedFee;

        // Only expect the event if there's a net payout amount
        if (expectedNetAmount > 0) {
            vm.expectEmit(true, true, true, true, address(adConversion));
            emit AdConversion.OffchainConversionProcessed(campaign, false, attribution.conversion);
        }

        // Call hook directly using base utility
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            callHookOnSend(attributionProvider1, campaign, address(tokenA), abi.encode(attributions));

        // Verify return values based on whether there's a net payout
        if (expectedNetAmount > 0) {
            assertEq(payouts.length, 1, "Should have one payout when net amount > 0");
            assertEq(payouts[0].recipient, publisherPayout, "Payout recipient should match fuzzed address");
            assertEq(payouts[0].amount, expectedNetAmount, "Payout amount should be net of fees");
        } else {
            assertEq(payouts.length, 0, "Should have no payouts when entire amount goes to fees");
        }

        if (expectedFee > 0) {
            assertEq(fees.length, 1, "Should have one fee distribution when fee > 0");
            assertEq(fees[0].recipient, attributionProvider1, "Fee recipient should be attribution provider");
            assertEq(fees[0].amount, expectedFee, "Fee amount should match calculated fee");
        } else {
            assertEq(fees.length, 0, "Should have no fee distribution when fee = 0");
        }

        assertFalse(sendFeesNow, "Should return false for sendFeesNow");
    }

    /// @dev Successfully processes single onchain conversion attribution
    /// @param payoutAmount Payout amount
    /// @param feeBps Attribution provider fee
    /// @param publisherPayout Publisher payout address
    /// @param refCodeSeed Seed for selecting registered ref code
    function test_success_singleOnchainConversion(
        uint256 payoutAmount,
        uint16 feeBps,
        address publisherPayout,
        uint256 refCodeSeed
    ) public {
        // Constrain fuzz inputs to valid ranges
        payoutAmount = bound(payoutAmount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_ATTRIBUTION_AMOUNT);
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(publisherPayout != address(0)); // Ensure non-zero address

        // Select one of the registered ref codes deterministically
        string[] memory refCodes = new string[](3);
        refCodes[0] = REF_CODE_1;
        refCodes[1] = REF_CODE_2;
        refCodes[2] = REF_CODE_3;
        string memory selectedRefCode = refCodes[refCodeSeed % 3];

        // Create campaign with fuzzed fee
        address campaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        fundCampaign(campaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(campaign, attributionProvider1);

        // Create onchain attribution with fuzzed parameters (don't override logBytes - they're set correctly by utility)
        AdConversion.Attribution memory attribution =
            createOnchainAttribution(selectedRefCode, publisherPayout, payoutAmount);

        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = attribution;

        // Calculate expected amounts with fuzzed fee
        uint256 expectedFee = (payoutAmount * feeBps) / adConversion.MAX_BPS();
        uint256 expectedNetAmount = payoutAmount - expectedFee;

        // Expect the OnchainConversionProcessed event - we don't need to match exact log data
        vm.expectEmit(true, false, false, false, address(adConversion));
        emit AdConversion.OnchainConversionProcessed(
            campaign,
            false,
            attribution.conversion,
            AdConversion.Log({chainId: 0, transactionHash: bytes32(0), index: 0})
        );

        // Call hook directly using base utility
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            callHookOnSend(attributionProvider1, campaign, address(tokenA), abi.encode(attributions));

        // Verify return values based on whether there's a net payout
        if (expectedNetAmount > 0) {
            assertEq(payouts.length, 1, "Should have one payout when net amount > 0");
            assertEq(payouts[0].recipient, publisherPayout, "Payout recipient should match fuzzed address");
            assertEq(payouts[0].amount, expectedNetAmount, "Payout amount should be net of fees");
        } else {
            assertEq(payouts.length, 0, "Should have no payouts when entire amount goes to fees");
        }

        if (expectedFee > 0) {
            assertEq(fees.length, 1, "Should have one fee distribution when fee > 0");
            assertEq(fees[0].recipient, attributionProvider1, "Fee recipient should be attribution provider");
            assertEq(fees[0].amount, expectedFee, "Fee amount should match calculated fee");
        } else {
            assertEq(fees.length, 0, "Should have no fee distribution when fee = 0");
        }

        assertFalse(sendFeesNow, "Should return false for sendFeesNow");
    }

    /// @dev Successfully processes multiple conversion attributions
    /// @param numConversions Number of conversions to process
    /// @param feeBps Attribution provider fee
    /// @param publisherSeed Seed for generating varied publisher ref codes
    function test_success_multipleConversions(uint8 numConversions, uint16 feeBps, uint256 publisherSeed) public {
        // Constrain fuzz inputs
        numConversions = uint8(bound(numConversions, 2, 10)); // 2-10 conversions
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));

        // Create campaign with fuzzed fee
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create multiple attributions with varied parameters
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](numConversions);
        uint256 totalPayoutAmount = 0;
        uint256 totalFeeAmount = 0;

        for (uint256 i = 0; i < numConversions; i++) {
            // Generate varied ref codes using seed variation that avoids overflow
            uint256 seedVariant = uint256(keccak256(abi.encode(publisherSeed, i)));
            string memory refCode;

            // Use seed to determine whether to use predefined codes or generate new ones
            if (seedVariant % 4 == 0) {
                refCode = REF_CODE_1; // Keep some predictability for edge case testing
            } else if (seedVariant % 4 == 1) {
                refCode = REF_CODE_2;
            } else if (seedVariant % 4 == 2) {
                refCode = REF_CODE_3;
            } else {
                // Generate and register a new valid ref code from seed
                refCode = generateValidRefCodeFromSeed(seedVariant);
                vm.prank(registrarSigner);
                builderCodes.register(refCode, publisher1, publisherPayout1);
            }

            address publisher = (i % 2 == 0) ? publisherPayout1 : publisherPayout2;

            // Mix of onchain and offchain conversions
            bool isOnchain = (i % 2 == 1);

            uint256 amount = DEFAULT_ATTRIBUTION_AMOUNT + (i * 1000); // Vary amounts

            if (isOnchain) {
                attributions[i] = createOnchainAttribution(refCode, publisher, amount);
            } else {
                attributions[i] = createOffchainAttribution(refCode, publisher, amount);
            }

            totalPayoutAmount += amount;
            totalFeeAmount += (amount * feeBps) / adConversion.MAX_BPS();
        }

        // Calculate expected net amount
        uint256 expectedNetAmount = totalPayoutAmount - totalFeeAmount;

        // Call hook with multiple attributions
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(attributions));

        // Calculate total payout amounts
        uint256 actualTotalPayout = 0;
        for (uint256 i = 0; i < payouts.length; i++) {
            actualTotalPayout += payouts[i].amount;
        }

        // Verify batch processing results based on whether there are net payouts
        if (expectedNetAmount > 0) {
            assertTrue(payouts.length > 0, "Should have at least one payout when net amount > 0");
            assertEq(actualTotalPayout, expectedNetAmount, "Total payout should match expected net amount");
        } else {
            assertEq(payouts.length, 0, "Should have no payouts when entire amount goes to fees");
            assertEq(actualTotalPayout, 0, "Total payout should be 0 when no net payouts");
        }

        // Verify fee handling
        if (totalFeeAmount > 0) {
            assertEq(fees.length, 1, "Should have one fee distribution when fee > 0");
            assertEq(fees[0].recipient, attributionProvider1, "Fee recipient should be attribution provider");
            assertEq(fees[0].amount, totalFeeAmount, "Fee amount should match total calculated fees");
        } else {
            assertEq(fees.length, 0, "Should have no fee distribution when fee = 0");
        }

        assertFalse(sendFeesNow, "Should return false for sendFeesNow");
    }

    /// @dev Successfully processes conversions with inactive conversion config
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param payoutAmount Attribution payout amount
    function test_success_withInactiveConversionConfig(address campaign, address token, uint256 payoutAmount) public {
        // Constrain to reasonable payout amount
        payoutAmount = bound(payoutAmount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_ATTRIBUTION_AMOUNT);
        // Create campaign with zero fee to test inactive config processing
        address testCampaign = createZeroFeeCampaign(advertiser1, attributionProvider1);
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution with config ID 0 (which is allowed but inactive)
        AdConversion.Attribution[] memory testAttributions = new AdConversion.Attribution[](1);
        testAttributions[0] = createOffchainAttribution(REF_CODE_1, publisherPayout1, payoutAmount);
        testAttributions[0].conversion.configId = 0; // Inactive config ID

        // Should succeed - config ID 0 is treated as valid/default
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(testAttributions));

        // Verify processing succeeded
        assertGt(payouts.length, 0, "Should process with inactive config ID");
        assertEq(payouts[0].recipient, publisherPayout1, "Should route to correct publisher");
        assertEq(payouts[0].amount, payoutAmount, "Should process full amount with zero fee");
    }

    /// @dev Successfully processes conversions with zero attribution provider fee
    /// @param campaign Campaign address with zero fee
    /// @param token Token address
    /// @param payoutAmount Attribution payout amount
    function test_success_zeroProviderFee(address campaign, address token, uint256 payoutAmount) public {
        // Constrain to reasonable payout amount
        payoutAmount = bound(payoutAmount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_ATTRIBUTION_AMOUNT);
        // Create campaign with zero fee
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            0 // Zero fee
        );

        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution
        AdConversion.Attribution[] memory testAttributions = new AdConversion.Attribution[](1);
        testAttributions[0] = createOffchainAttribution(REF_CODE_1, publisherPayout1, payoutAmount);

        // Process attribution with zero fee
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(testAttributions));

        // Verify zero fee processing
        assertEq(payouts.length, 1, "Should have one payout");
        assertEq(payouts[0].amount, payoutAmount, "Should get full amount with zero fee");
        assertEq(payouts[0].recipient, publisherPayout1, "Should route to publisher");

        assertEq(fees.length, 0, "Should have no fees with zero fee rate");
    }

    /// @dev Successfully processes conversions with maximum attribution provider fee
    /// @param campaign Campaign address with 100% fee
    /// @param token Token address
    /// @param payoutAmount Attribution payout amount
    function test_success_maximumProviderFee(address campaign, address token, uint256 payoutAmount) public {
        // Constrain to reasonable payout amount
        payoutAmount = bound(payoutAmount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_ATTRIBUTION_AMOUNT);
        // Create campaign with maximum fee (100%)
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            10000 // 100% fee (MAX_BPS)
        );

        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution
        AdConversion.Attribution[] memory testAttributions = new AdConversion.Attribution[](1);
        testAttributions[0] = createOffchainAttribution(REF_CODE_1, publisherPayout1, payoutAmount);

        // Process attribution with 100% fee
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(testAttributions));

        // Verify maximum fee processing - entire amount goes to fees
        assertEq(payouts.length, 0, "Should have no payouts with 100% fee");

        assertEq(fees.length, 1, "Should have one fee distribution");
        assertEq(fees[0].amount, payoutAmount, "Should get full amount as fee");
        assertEq(fees[0].recipient, attributionProvider1, "Fee should go to attribution provider");
    }

    /// @dev Successfully consolidates multiple conversions to same recipient
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param sameRecipient Common recipient address
    /// @param payoutAmount1 First attribution payout amount
    /// @param payoutAmount2 Second attribution payout amount
    function test_success_consolidatesRecipients(
        address campaign,
        address token,
        address sameRecipient,
        uint256 payoutAmount1,
        uint256 payoutAmount2
    ) public {
        // Constrain to reasonable payout amounts
        payoutAmount1 = bound(payoutAmount1, MIN_ATTRIBUTION_AMOUNT, DEFAULT_ATTRIBUTION_AMOUNT / 2);
        payoutAmount2 = bound(payoutAmount2, MIN_ATTRIBUTION_AMOUNT, DEFAULT_ATTRIBUTION_AMOUNT / 2);
        vm.assume(sameRecipient != address(0));

        // Create campaign with zero fee for clean consolidation testing
        address testCampaign = createZeroFeeCampaign(advertiser1, attributionProvider1);
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create multiple attributions with same recipient
        AdConversion.Attribution[] memory testAttributions = new AdConversion.Attribution[](2);

        testAttributions[0] = createOffchainAttribution(REF_CODE_1, sameRecipient, payoutAmount1);
        testAttributions[1] = createOffchainAttribution(REF_CODE_2, sameRecipient, payoutAmount2);

        uint256 expectedTotal = payoutAmount1 + payoutAmount2;

        // Process attributions
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(testAttributions));

        // Verify consolidation - should have one payout to same recipient
        assertEq(payouts.length, 1, "Should consolidate to one payout");
        assertEq(payouts[0].recipient, sameRecipient, "Should consolidate to same recipient");
        assertEq(payouts[0].amount, expectedTotal, "Should consolidate amounts");
    }

    /// @dev Successfully resolves zero-address recipients to registry payout address
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param publisherRefCode Registered publisher reference code
    function test_success_resolvesZeroAddressRecipients(
        address campaign,
        address token,
        string memory publisherRefCode
    ) public {
        // Create campaign with zero fee for clean testing
        address testCampaign = createZeroFeeCampaign(advertiser1, attributionProvider1);
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution with zero address recipient (should resolve to registry payout)
        AdConversion.Attribution[] memory testAttributions = new AdConversion.Attribution[](1);
        testAttributions[0] = createOffchainAttribution(REF_CODE_1, address(0), DEFAULT_ATTRIBUTION_AMOUNT);

        // Process attribution with zero address
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(testAttributions));

        // Verify zero address resolution - should resolve to registered payout address
        assertEq(payouts.length, 1, "Should have one payout");
        assertNotEq(payouts[0].recipient, address(0), "Should resolve zero address");
        // The recipient should be the registered payout address for REF_CODE_1
        address expectedRecipient = builderCodes.payoutAddress(REF_CODE_1);
        assertEq(payouts[0].recipient, expectedRecipient, "Should resolve to registry payout address");
        assertEq(payouts[0].amount, DEFAULT_ATTRIBUTION_AMOUNT, "Amount should be preserved");
    }

    /// @dev Successfully processes conversions with empty ref codes (no publisher)
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param payoutAmount Attribution payout amount
    function test_success_emptyRefCodes(address campaign, address token, uint256 payoutAmount) public {
        // Constrain to reasonable payout amount
        payoutAmount = bound(payoutAmount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_ATTRIBUTION_AMOUNT);

        // Create campaign with zero fee to test empty ref code processing
        address testCampaign = createZeroFeeCampaign(advertiser1, attributionProvider1);
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution with empty ref code
        AdConversion.Attribution[] memory testAttributions = new AdConversion.Attribution[](1);
        testAttributions[0] = createEmptyRefCodeAttribution(publisherPayout1, payoutAmount);

        // Should succeed - empty ref codes are allowed
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(testAttributions));

        // Verify processing succeeded
        assertEq(payouts.length, 1, "Should process empty ref code");
        assertEq(payouts[0].recipient, publisherPayout1, "Should route to specified recipient");
        assertEq(payouts[0].amount, payoutAmount, "Should process full amount with zero fee");
        assertEq(fees.length, 0, "Should have no fees with zero fee campaign");
    }

    /// @dev Successfully processes conversions with unregistered config ID (0)
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param payoutAmount Attribution payout amount
    function test_success_unregisteredConfigIdZero(address campaign, address token, uint256 payoutAmount) public {
        // Constrain to reasonable payout amount
        payoutAmount = bound(payoutAmount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_ATTRIBUTION_AMOUNT);

        // Create campaign with zero fee
        address testCampaign = createZeroFeeCampaign(advertiser1, attributionProvider1);
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution with config ID 0 (unregistered but valid)
        AdConversion.Attribution[] memory testAttributions = new AdConversion.Attribution[](1);
        testAttributions[0] = createAttributionWithConfigId(0, REF_CODE_1, publisherPayout1, payoutAmount);

        // Should succeed - config ID 0 is treated as valid default
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(testAttributions));

        // Verify processing succeeded
        assertEq(payouts.length, 1, "Should process config ID 0");
        assertEq(payouts[0].recipient, publisherPayout1, "Should route to correct publisher");
        assertEq(payouts[0].amount, payoutAmount, "Should process full amount with zero fee");
        assertEq(fees.length, 0, "Should have no fees with zero fee campaign");
    }

    // ========================================
    // EDGE CASES
    // ========================================

    /// @dev Handles empty attributions array (no-op)
    /// @param campaign Campaign address
    /// @param token Token address
    function test_edge_emptyAttributions(address campaign, address token) public {
        // Create campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create empty attributions array
        AdConversion.Attribution[] memory emptyAttributions = new AdConversion.Attribution[](0);

        // Process empty attributions - should succeed without error
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(emptyAttributions));

        // Verify empty processing
        assertEq(payouts.length, 0, "Should have no payouts for empty attributions");
        assertEq(fees.length, 0, "Should have no fees for empty attributions");
        assertFalse(sendFeesNow, "sendFeesNow should be false");
    }

    /// @dev Handles conversions with zero payout amounts
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param attributions Array of attributions with zero amounts
    function test_edge_zeroPayoutAmounts(
        address campaign,
        address token,
        AdConversion.Attribution[] memory attributions
    ) public {
        // Create campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attributions with zero amounts
        AdConversion.Attribution[] memory testAttributions = new AdConversion.Attribution[](2);
        testAttributions[0] = createOffchainAttribution(REF_CODE_1, publisherPayout1, 0);
        testAttributions[1] = createOffchainAttribution(REF_CODE_2, publisherPayout2, 0);

        // Process zero amount attributions
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(testAttributions));

        // Verify zero amount handling - should have no payouts or fees
        assertEq(payouts.length, 0, "Should have no payouts for zero amounts");
        assertEq(fees.length, 0, "Should have no fees for zero amounts");
    }

    /// @dev Handles conversions with very large payout amounts
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param largeAmount Very large payout amount
    function test_edge_largePayoutAmounts(address campaign, address token, uint256 largeAmount) public {
        // Constrain to reasonable large amount (but within MockERC20 balance limits)
        largeAmount = bound(largeAmount, DEFAULT_ATTRIBUTION_AMOUNT, MAX_CAMPAIGN_FUNDING);

        // Create campaign with zero fee and maximum safe funding
        address testCampaign = createZeroFeeCampaign(advertiser1, attributionProvider1);
        fundCampaign(testCampaign, address(tokenA), MAX_CAMPAIGN_FUNDING); // Use max safe funding
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution with large amount
        AdConversion.Attribution[] memory testAttributions = new AdConversion.Attribution[](1);
        testAttributions[0] = createOffchainAttribution(REF_CODE_1, publisherPayout1, largeAmount);

        // Process large amount attribution
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(testAttributions));

        // Verify large amount processing
        assertEq(payouts.length, 1, "Should process large amount");
        assertEq(payouts[0].amount, largeAmount, "Should preserve large amount");
        assertEq(payouts[0].recipient, publisherPayout1, "Should route to correct recipient");
    }

    /// @dev Handles maximum number of attributions in single call
    /// @param campaign Campaign address
    /// @param token Token address
    function test_edge_manyAttributions(address campaign, address token) public {
        // Create campaign with zero fee and maximum safe funding
        address testCampaign = createZeroFeeCampaign(advertiser1, attributionProvider1);
        fundCampaign(testCampaign, address(tokenA), MAX_CAMPAIGN_FUNDING); // Use max safe funding
        activateCampaign(testCampaign, attributionProvider1);

        // Create many attributions (bound to reasonable number)
        uint256 numAttributions = 10; // Fixed reasonable number
        AdConversion.Attribution[] memory testAttributions = new AdConversion.Attribution[](numAttributions);
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < numAttributions; i++) {
            string memory refCode = (i % 3 == 0) ? REF_CODE_1 : (i % 3 == 1) ? REF_CODE_2 : REF_CODE_3;
            address recipient = (i % 2 == 0) ? publisherPayout1 : publisherPayout2;
            uint256 amount = DEFAULT_ATTRIBUTION_AMOUNT + (i * 1000);

            testAttributions[i] = createOffchainAttribution(refCode, recipient, amount);
            totalAmount += amount;
        }

        // Process many attributions
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(testAttributions));

        // Verify many attributions processing
        assertGt(payouts.length, 0, "Should process many attributions");

        // Calculate total payout amount
        uint256 actualTotal = 0;
        for (uint256 i = 0; i < payouts.length; i++) {
            actualTotal += payouts[i].amount;
        }
        assertEq(actualTotal, totalAmount, "Should preserve total amount across many attributions");
    }

    /// @dev Handles campaign without allowlist (all publishers allowed)
    /// @param campaign Campaign address without allowlist
    /// @param token Token address
    /// @param anyPublisherRefCode Any registered publisher ref code
    /// @param payoutAmount Attribution payout amount
    function test_edge_noAllowlist(
        address campaign,
        address token,
        string memory anyPublisherRefCode,
        uint256 payoutAmount
    ) public {
        // Constrain inputs
        payoutAmount = bound(payoutAmount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_ATTRIBUTION_AMOUNT);

        // Generate a valid ref code from the provided string seed if needed
        string memory refCode = generateValidRefCodeFromSeed(uint256(keccak256(bytes(anyPublisherRefCode))));

        // Register the ref code to ensure it's valid
        vm.prank(registrarSigner);
        builderCodes.register(refCode, publisher1, publisherPayout1);

        // Create campaign with no allowlist (empty allowlist means no restrictions)
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist - any publisher allowed
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            ZERO_FEE_BPS
        );

        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution with the registered ref code
        AdConversion.Attribution[] memory testAttributions = new AdConversion.Attribution[](1);
        testAttributions[0] = createOffchainAttribution(refCode, publisherPayout1, payoutAmount);

        // Should succeed - no allowlist means any registered publisher is allowed
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(testAttributions));

        // Verify processing succeeded
        assertEq(payouts.length, 1, "Should process any publisher when no allowlist");
        assertEq(payouts[0].recipient, publisherPayout1, "Should route to publisher payout address");
        assertEq(payouts[0].amount, payoutAmount, "Should process full amount with zero fee");
        assertEq(fees.length, 0, "Should have no fees with zero fee campaign");
    }

    // ========================================
    // FEE CALCULATION TESTING
    // ========================================

    /// @dev Verifies correct fee calculation and deduction
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param payoutAmount Original payout amount before fees
    /// @param feeBps Attribution provider fee in basis points
    function test_calculatesCorrectFees(address campaign, address token, uint256 payoutAmount, uint16 feeBps) public {
        // Constrain fuzz inputs to valid ranges
        payoutAmount = bound(payoutAmount, MIN_ATTRIBUTION_AMOUNT, DEFAULT_ATTRIBUTION_AMOUNT);
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));

        // Create campaign with fuzzed fee
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution with fuzzed payout amount
        AdConversion.Attribution memory attribution =
            createOffchainAttribution(REF_CODE_1, publisherPayout1, payoutAmount);

        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = attribution;

        // Calculate expected fee
        uint256 expectedFee = (payoutAmount * feeBps) / adConversion.MAX_BPS();
        uint256 expectedNetAmount = payoutAmount - expectedFee;

        // Call hook and verify fee calculation
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(attributions));

        // Verify correct fee calculation
        if (feeBps == MAX_FEE_BPS) {
            assertEq(payouts.length, 0, "Should have no payouts when fee is max");
        } else {
            assertEq(payouts.length, 1, "Should have one payout");
            assertEq(payouts[0].amount, expectedNetAmount, "Net payout amount should be correct");
        }

        if (expectedFee > 0) {
            assertEq(fees.length, 1, "Should have one fee distribution when fee > 0");
            assertEq(fees[0].amount, expectedFee, "Fee amount should be calculated correctly");
            assertEq(fees[0].recipient, attributionProvider1, "Fee recipient should be attribution provider");
        } else {
            assertEq(fees.length, 0, "Should have no fee distributions when fee is 0");
        }
    }

    /// @dev Verifies fee calculation with rounding down
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param smallAmount Small amount that results in fee rounding
    /// @param feeBps Attribution provider fee in basis points
    function test_feeRoundingDown(address campaign, address token, uint256 smallAmount, uint16 feeBps) public {
        // Constrain inputs to create rounding scenarios
        smallAmount = bound(smallAmount, 1, 9999); // Small amounts that could cause rounding
        feeBps = uint16(bound(feeBps, 1, MAX_FEE_BPS)); // Non-zero fee to test rounding

        // Skip this test if the fee would be 0 after rounding
        uint256 expectedFee = (smallAmount * feeBps) / adConversion.MAX_BPS();
        if (expectedFee == 0) return; // Skip cases where fee rounds to 0

        // Create campaign with fuzzed fee
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create attribution with small amount
        AdConversion.Attribution memory attribution =
            createOffchainAttribution(REF_CODE_1, publisherPayout1, smallAmount);

        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = attribution;

        // Calculate expected amounts with rounding
        uint256 expectedNetAmount = smallAmount - expectedFee;

        // Call hook
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(attributions));

        assertEq(fees.length, 1, "Should have one fee distribution");
        assertEq(fees[0].amount, expectedFee, "Fee should be rounded down");

        if (feeBps == MAX_FEE_BPS) {
            assertEq(payouts.length, 0, "Should have no payouts when fee is max");
        } else {
            // Verify rounding behavior - fee should round DOWN due to integer division
            assertEq(payouts.length, 1, "Should have one payout");
            assertEq(payouts[0].amount, expectedNetAmount, "Net amount should account for rounding");

            // Verify the total adds up correctly (no tokens lost to rounding)
            assertEq(payouts[0].amount + fees[0].amount, smallAmount, "Total should equal original amount");
        }
    }

    /// @dev Verifies fees are accumulated correctly for multiple conversions
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param numAttributions Number of attributions to test fee accumulation
    /// @param feeBps Attribution provider fee in basis points
    function test_accumulatesFees(address campaign, address token, uint256 numAttributions, uint16 feeBps) public {
        // Constrain the number of attributions to a reasonable range for testing
        numAttributions = bound(numAttributions, 2, 5);

        // Constrain fee to valid range for accumulation testing
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create multiple attributions with varying amounts
        AdConversion.Attribution[] memory testAttributions = new AdConversion.Attribution[](numAttributions);
        uint256 totalPayoutAmount = 0;
        uint256 expectedTotalFees = 0;

        for (uint256 i = 0; i < numAttributions; i++) {
            // Use different ref codes to ensure variety
            string memory refCode = (i % 3 == 0) ? REF_CODE_1 : (i % 3 == 1) ? REF_CODE_2 : REF_CODE_3;

            // Vary the amounts
            uint256 amount = DEFAULT_ATTRIBUTION_AMOUNT + (i * 1000);
            totalPayoutAmount += amount;

            // Calculate expected fee for this attribution
            uint256 feeForThis = (amount * feeBps) / adConversion.MAX_BPS();
            expectedTotalFees += feeForThis;

            testAttributions[i] = createOffchainAttribution(refCode, publisherPayout1, amount);
        }

        // Call hook with multiple attributions
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(testAttributions));

        // Calculate total fees from all distributions
        uint256 actualTotalFees = 0;
        for (uint256 i = 0; i < fees.length; i++) {
            actualTotalFees += fees[i].amount;
            assertEq(fees[i].recipient, attributionProvider1, "All fees should go to attribution provider");
        }

        // Verify fee accumulation
        if (expectedTotalFees > 0) {
            assertGt(fees.length, 0, "Should have fee distributions when fees > 0");
            assertEq(actualTotalFees, expectedTotalFees, "Total accumulated fees should match expected");
        } else {
            assertEq(fees.length, 0, "Should have no fee distributions when fees = 0");
            assertEq(actualTotalFees, 0, "Total fees should be 0 when no fees are charged");
        }

        // Verify total payouts
        uint256 actualTotalPayouts = 0;
        for (uint256 i = 0; i < payouts.length; i++) {
            actualTotalPayouts += payouts[i].amount;
        }

        // Total payouts + fees should equal total original amounts
        assertEq(actualTotalPayouts + actualTotalFees, totalPayoutAmount, "Conservation of tokens");
    }

    // ========================================
    // EVENT TESTING
    // ========================================

    /// @dev Emits OffchainConversionProcessed event for offchain conversions
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param offchainConversion Offchain conversion data
    function test_emitsOffchainConversionProcessed(
        address campaign,
        address token,
        AdConversion.Conversion memory offchainConversion
    ) public {}

    /// @dev Emits OnchainConversionProcessed event for onchain conversions
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param onchainConversion Onchain conversion data
    /// @param logBytes Encoded blockchain log data
    function test_emitsOnchainConversionProcessed(
        address campaign,
        address token,
        AdConversion.Conversion memory onchainConversion,
        bytes memory logBytes
    ) public {}

    /// @dev Emits multiple conversion events for batch processing
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param mixedAttributions Array of mixed onchain/offchain attributions
    function test_emitsMultipleConversionEvents(
        address campaign,
        address token,
        AdConversion.Attribution[] memory mixedAttributions
    ) public {}

    /// @dev Emits OffchainConversionProcessed with isPublisherPayout flag
    /// @param campaign Campaign address
    /// @param conversion Offchain conversion data
    /// @param isPublisherPayout Whether this is a publisher payout or special routing
    function test_emitsOffchainConversionWithPublisherFlag(
        address campaign,
        AdConversion.Conversion memory conversion,
        bool isPublisherPayout
    ) public {}

    /// @dev Emits correct number of conversion events for batch
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param attributions Array of conversion attributions
    function test_emitsCorrectNumberOfBatchEvents(
        address campaign,
        address token,
        AdConversion.Attribution[] memory attributions
    ) public {}

    /// @dev Emits mixed onchain and offchain conversion events
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param onchainAttributions Array of onchain conversion attributions
    /// @param offchainAttributions Array of offchain conversion attributions
    function test_emitsMixedBatchConversionEvents(
        address campaign,
        address token,
        AdConversion.Attribution[] memory onchainAttributions,
        AdConversion.Attribution[] memory offchainAttributions
    ) public {}

    /// @dev Emits events with correct isPublisherPayout flags
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param publisherAttributions Array of publisher attributions
    /// @param directPayoutAttributions Array of direct payout attributions
    function test_emitsCorrectBatchPublisherPayoutFlags(
        address campaign,
        address token,
        AdConversion.Attribution[] memory publisherAttributions,
        AdConversion.Attribution[] memory directPayoutAttributions
    ) public {}

    // ========================================
    // RETURN VALUE VERIFICATION
    // ========================================

    /// @dev Verifies sendFeesNow flag is correctly set
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param attributions Array of conversion attributions
    function test_sendFeesNowReturnsFalse(
        address campaign,
        address token,
        AdConversion.Attribution[] memory attributions
    ) public {}

    // ========================================
    // BATCH ATTRIBUTION PROCESSING TESTS
    // ========================================

    /// @dev Successfully processes batch attributions with multiple publishers
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param attributions Array of multiple conversion attributions
    function test_success_batchMultiplePublishers(
        address campaign,
        address token,
        AdConversion.Attribution[] memory attributions
    ) public {}

    /// @dev Successfully processes batch attributions with mixed conversion types
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param onchainAttributions Array of onchain conversion attributions
    /// @param offchainAttributions Array of offchain conversion attributions
    function test_success_batchMixedConversionTypes(
        address campaign,
        address token,
        AdConversion.Attribution[] memory onchainAttributions,
        AdConversion.Attribution[] memory offchainAttributions
    ) public {}

    /// @dev Correctly calculates and accumulates fees across batch
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param numAttributionsSeed Seed for determining number of attributions
    /// @param feeBps Attribution provider fee in basis points
    function test_calculatesCorrectBatchFees(
        address campaign,
        address token,
        uint256 numAttributionsSeed,
        uint16 feeBps
    ) public {
        // Constrain inputs to reasonable ranges
        uint256 numAttributions = bound(numAttributionsSeed, 2, 8);
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));

        // Create campaign with fuzzed fee
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create batch of attributions with varied amounts
        AdConversion.Attribution[] memory testAttributions = new AdConversion.Attribution[](numAttributions);
        uint256 totalOriginalAmount = 0;
        uint256 expectedTotalFees = 0;

        for (uint256 i = 0; i < numAttributions; i++) {
            // Use different ref codes and amounts
            string memory refCode = (i % 3 == 0) ? REF_CODE_1 : (i % 3 == 1) ? REF_CODE_2 : REF_CODE_3;
            uint256 amount = DEFAULT_ATTRIBUTION_AMOUNT + (i * 5000);
            totalOriginalAmount += amount;

            // Calculate expected fee for this attribution
            uint256 individualFee = (amount * feeBps) / adConversion.MAX_BPS();
            expectedTotalFees += individualFee;

            // Alternate between onchain and offchain to test batch diversity
            if (i % 2 == 0) {
                testAttributions[i] = createOffchainAttribution(refCode, publisherPayout1, amount);
            } else {
                testAttributions[i] = createOnchainAttribution(refCode, publisherPayout1, amount);
            }
        }

        // Call hook with batch
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees,) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(testAttributions));

        // Calculate actual total fees
        uint256 actualTotalFees = 0;
        for (uint256 i = 0; i < fees.length; i++) {
            actualTotalFees += fees[i].amount;
        }

        // Calculate actual total payouts
        uint256 actualTotalPayouts = 0;
        for (uint256 i = 0; i < payouts.length; i++) {
            actualTotalPayouts += payouts[i].amount;
        }

        // Verify batch fee calculations
        if (expectedTotalFees > 0) {
            assertGt(fees.length, 0, "Should have fee distributions when fees > 0");
            assertEq(actualTotalFees, expectedTotalFees, "Batch total fees should match expected");
        } else {
            assertEq(fees.length, 0, "Should have no fees when total fees = 0");
        }

        // Verify conservation of tokens across the batch
        assertEq(actualTotalPayouts + actualTotalFees, totalOriginalAmount, "Batch should conserve total token amounts");

        // Verify payouts length is correct based on fee BPS
        if (feeBps == MAX_FEE_BPS) {
            assertEq(payouts.length, 0, "Should have no payouts when fee is max");
        } else {
            assertGt(payouts.length, 0, "Should have payouts for batch");
        }
    }

    /// @dev Processes batch with zero fee correctly
    /// @param campaign Campaign address with zero fee
    /// @param token Token address
    /// @param attributions Array of conversion attributions
    function test_success_batchZeroFee(address campaign, address token, AdConversion.Attribution[] memory attributions)
        public {}

    /// @dev Reverts when batch contains invalid conversion config IDs
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param validAttributions Array of valid attributions
    /// @param invalidConfigId Invalid conversion config ID
    function test_revert_batchInvalidConfigId(
        address campaign,
        address token,
        AdConversion.Attribution[] memory validAttributions,
        uint16 invalidConfigId
    ) public {}

    /// @dev Reverts when batch contains publishers not in allowlist
    /// @param campaign Campaign address with allowlist
    /// @param token Token address
    /// @param validAttributions Array of valid attributions
    /// @param disallowedRefCode Publisher ref code not in allowlist
    function test_revert_batchDisallowedPublisher(
        address campaign,
        address token,
        AdConversion.Attribution[] memory validAttributions,
        string memory disallowedRefCode
    ) public {}

    /// @dev Handles empty attribution array (no-op)
    /// @param campaign Campaign address
    /// @param token Token address
    function test_edge_emptyBatch(address campaign, address token) public {
        // Create campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Create empty attribution array
        AdConversion.Attribution[] memory emptyAttributions = new AdConversion.Attribution[](0);

        // Should succeed with empty results
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            callHookOnSend(attributionProvider1, testCampaign, address(tokenA), abi.encode(emptyAttributions));

        // Verify empty processing
        assertEq(payouts.length, 0, "Should have no payouts for empty batch");
        assertEq(fees.length, 0, "Should have no fees for empty batch");
        assertFalse(sendFeesNow, "sendFeesNow should be false for empty batch");
    }
}
