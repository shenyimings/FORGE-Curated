// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../../src/Flywheel.sol";
import {AdConversion} from "../../src/hooks/AdConversion.sol";
import {AdConversionTestBase} from "../lib/AdConversionTestBase.sol";
import {LibString} from "solady/utils/LibString.sol";

contract AdConversionIntegrationTest is AdConversionTestBase {
    // ========================================
    // STRUCTS FOR STACK DEPTH MANAGEMENT
    // ========================================

    /// @dev Multi-token campaign test parameters
    struct MultiTokenParams {
        address advertiser;
        address attributionProvider;
        address publisher;
        address tokenAddr1;
        address tokenAddr2;
        uint256 funding1;
        uint256 funding2;
        uint256 attribution1;
        uint256 attribution2;
        uint16 feeBps;
    }

    /// @dev Balance tracking for multi-token operations
    struct BalanceTracker {
        uint256 publisher1Before;
        uint256 publisher2Before;
        uint256 provider1Before;
        uint256 provider2Before;
        uint256 advertiser1Before;
        uint256 advertiser2Before;
    }

    /// @dev Fee and payout calculations
    struct FeeCalculation {
        uint256 fee1;
        uint256 payout1;
        uint256 fee2;
        uint256 payout2;
        uint256 remaining1;
        uint256 remaining2;
    }

    // ========================================
    // END-TO-END CAMPAIGN LIFECYCLE TESTS
    // ========================================

    /// @dev Complete successful campaign lifecycle from creation to finalization
    function test_integration_completeCampaignLifecycle(
        uint256 campaignFunding,
        uint256 attributionAmount,
        uint16 feeBps
    ) public {
        campaignFunding = bound(campaignFunding, MIN_CAMPAIGN_FUNDING, MAX_CAMPAIGN_FUNDING);
        attributionAmount = bound(attributionAmount, MIN_ATTRIBUTION_AMOUNT, campaignFunding / 2);
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, adConversion.MAX_BPS()));

        // Create campaign
        address campaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0),
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        assertCampaignStatus(campaign, Flywheel.CampaignStatus.INACTIVE);
        assertCampaignState(campaign, advertiser1, attributionProvider1, feeBps, DEFAULT_ATTRIBUTION_WINDOW);
        assertConversionConfigCount(campaign, 2);

        // Fund campaign
        fundCampaign(campaign, address(tokenA), campaignFunding);
        assertTokenBalance(address(tokenA), campaign, campaignFunding);

        // Activate campaign
        activateCampaign(campaign, attributionProvider1);
        assertCampaignStatus(campaign, Flywheel.CampaignStatus.ACTIVE);

        // Create attribution
        AdConversion.Attribution memory attribution =
            createOffchainAttribution(REF_CODE_1, publisherPayout1, attributionAmount);

        // Calculate expected fee before processing
        uint256 expectedFeeAmount = (attributionAmount * feeBps) / adConversion.MAX_BPS();
        uint256 expectedPayoutAmount = attributionAmount - expectedFeeAmount;

        // Record initial balances
        uint256 publisherBalanceBefore = tokenA.balanceOf(publisherPayout1);
        uint256 attributionProviderBalanceBefore = tokenA.balanceOf(attributionProvider1);

        // Process attribution
        processAttribution(campaign, address(tokenA), attribution, attributionProvider1);

        // Verify payout
        assertTokenBalance(address(tokenA), publisherPayout1, publisherBalanceBefore + expectedPayoutAmount);

        // Verify fee allocation
        assertAllocatedFee(campaign, address(tokenA), attributionProvider1, expectedFeeAmount);

        // Campaign should still be active with reduced balance
        // Note: Only the payout amount is deducted from campaign, fees stay until distributed
        assertCampaignStatus(campaign, Flywheel.CampaignStatus.ACTIVE);
        assertTokenBalance(address(tokenA), campaign, campaignFunding - expectedPayoutAmount);

        // Finalize campaign
        finalizeCampaign(campaign, attributionProvider1);
        assertCampaignStatus(campaign, Flywheel.CampaignStatus.FINALIZED);

        // Distribute fees
        vm.prank(attributionProvider1);
        flywheel.distributeFees(campaign, address(tokenA), abi.encode(attributionProvider1));

        // Verify fee distribution
        assertAttributionProviderInvariants(
            campaign, address(tokenA), attributionProvider1, attributionProviderBalanceBefore, expectedFeeAmount
        );

        // Withdraw remaining funds
        uint256 remainingBalance = tokenA.balanceOf(campaign);
        vm.prank(advertiser1);
        flywheel.withdrawFunds(campaign, address(tokenA), abi.encode(advertiser1, remainingBalance));

        // Verify campaign completion - after fees are distributed, balance should be funding - attribution
        assertCampaignCompletedLifecycle(campaign, address(tokenA), attributionProvider1);

        // Final invariant check
        assertCampaignInvariants(campaign, address(tokenA));
    }

    /// @dev Campaign lifecycle with multiple publishers and attributions - using fixed values for stability
    function test_integration_multiPublisherCampaign() public {
        address advertiser = advertiser1;
        address attributionProvider = attributionProvider1;
        uint256 campaignFunding = 100 ether;
        uint16 feeBps = 500; // 5% fees

        // Use fixed publisher data for predictable results
        address[] memory publishers = new address[](2);
        publishers[0] = publisherPayout1;
        publishers[1] = publisherPayout2;

        uint256[] memory attributionAmounts = new uint256[](2);
        attributionAmounts[0] = 5 ether;
        attributionAmounts[1] = 3 ether;

        uint256 numPublishers = 2; // Fixed number

        // Register publishers and create allowlist
        string[] memory allowlist = new string[](numPublishers);
        allowlist[0] = REF_CODE_1; // "pub1"
        allowlist[1] = REF_CODE_2; // "pub2"

        // Create campaign with allowlist
        address campaign = createCampaign(
            advertiser, attributionProvider, allowlist, _createDefaultConfigs(), DEFAULT_ATTRIBUTION_WINDOW, feeBps
        );

        // Fund and activate campaign
        fundCampaign(campaign, address(tokenA), campaignFunding);
        activateCampaign(campaign, attributionProvider);

        // Process attributions for each publisher
        uint256 totalFeesGenerated = 0;
        uint256[] memory expectedPayouts = new uint256[](numPublishers);

        for (uint256 i = 0; i < numPublishers; i++) {
            // Create attribution
            AdConversion.Attribution memory attribution =
                createOffchainAttribution(allowlist[i], publishers[i], attributionAmounts[i]);

            // Calculate expected amounts
            uint256 feeAmount = (attributionAmounts[i] * feeBps) / adConversion.MAX_BPS();
            expectedPayouts[i] = attributionAmounts[i] - feeAmount;
            totalFeesGenerated += feeAmount;

            // Record initial balance
            uint256 publisherBalanceBefore = tokenA.balanceOf(publishers[i]);

            // Process attribution
            processAttribution(campaign, address(tokenA), attribution, attributionProvider);

            // Verify payout
            assertTokenBalance(address(tokenA), publishers[i], publisherBalanceBefore + expectedPayouts[i]);
        }

        // Verify total fee allocation
        assertAllocatedFee(campaign, address(tokenA), attributionProvider, totalFeesGenerated);

        // Verify campaign balance (only payouts are sent, fees stay in campaign)
        uint256 totalAttributionAmount = attributionAmounts[0] + attributionAmounts[1]; // 5 + 3 = 8 ether
        uint256 totalPayoutAmount = totalAttributionAmount - totalFeesGenerated;
        uint256 expectedCampaignBalance = campaignFunding - totalPayoutAmount;
        assertTokenBalance(address(tokenA), campaign, expectedCampaignBalance);

        // Finalize campaign and verify completion
        finalizeCampaign(campaign, attributionProvider);
        assertCampaignStatus(campaign, Flywheel.CampaignStatus.FINALIZED);

        // Verify final invariants
        assertCampaignInvariants(campaign, address(tokenA));
    }

    /// @dev Campaign with both onchain and offchain conversions
    /// @param advertiser Advertiser address
    /// @param attributionProvider Attribution provider address
    /// @param publisher Publisher address
    /// @param publisherRefCode Publisher reference code
    /// @param campaignFunding Initial campaign funding amount
    /// @param offchainAmount Offchain conversion amount
    /// @param onchainAmount Onchain conversion amount
    /// @param feeBps Attribution provider fee in basis points
    function test_integration_mixedConversionTypes(
        address advertiser,
        address attributionProvider,
        address publisher,
        string memory publisherRefCode,
        uint256 campaignFunding,
        uint256 offchainAmount,
        uint256 onchainAmount,
        uint16 feeBps
    ) public {
        // Constrain inputs
        vm.assume(advertiser != address(0) && attributionProvider != address(0) && publisher != address(0));
        vm.assume(advertiser != attributionProvider);
        campaignFunding = bound(campaignFunding, MIN_CAMPAIGN_FUNDING, 1000 ether); // Cap at reasonable amount
        offchainAmount = bound(offchainAmount, MIN_ATTRIBUTION_AMOUNT, campaignFunding / 10);
        onchainAmount = bound(onchainAmount, MIN_ATTRIBUTION_AMOUNT, campaignFunding / 10);
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, 1000)); // Cap fees at 10%

        // Ensure total doesn't exceed funding
        vm.assume(offchainAmount + onchainAmount <= campaignFunding / 2); // More conservative

        // Use REF_CODE_1 as registered publisher
        string memory refCode = REF_CODE_1;

        // Create campaign without allowlist (allows any publisher)
        address campaign = createCampaign(
            advertiser,
            attributionProvider,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        // Fund and activate campaign
        fundCampaign(campaign, address(tokenA), campaignFunding);
        activateCampaign(campaign, attributionProvider);

        // Record initial publisher balance
        uint256 publisherBalanceBefore = tokenA.balanceOf(publisherPayout1);

        // Process offchain attribution (uses config ID 1 - offchain)
        AdConversion.Attribution memory offchainAttribution =
            createOffchainAttribution(refCode, publisherPayout1, offchainAmount);

        processAttribution(campaign, address(tokenA), offchainAttribution, attributionProvider);

        // Process onchain attribution (uses config ID 2 - onchain)
        AdConversion.Attribution memory onchainAttribution =
            createOnchainAttribution(refCode, publisherPayout1, onchainAmount);

        processAttribution(campaign, address(tokenA), onchainAttribution, attributionProvider);

        // Calculate expected totals (per-attribution rounding like the contract)
        uint256 totalAttributionAmount = offchainAmount + onchainAmount;
        uint256 totalFeeAmount =
            ((offchainAmount * feeBps) / adConversion.MAX_BPS()) + ((onchainAmount * feeBps) / adConversion.MAX_BPS()); // Calculate per attribution
        uint256 totalPayoutAmount = totalAttributionAmount - totalFeeAmount;

        // Verify publisher received both payouts
        assertTokenBalance(address(tokenA), publisherPayout1, publisherBalanceBefore + totalPayoutAmount);

        // Verify total fee allocation
        assertAllocatedFee(campaign, address(tokenA), attributionProvider, totalFeeAmount);

        // Verify campaign balance reduction (only payouts are sent, fees stay in campaign)
        uint256 expectedCampaignBalance = campaignFunding - totalPayoutAmount;
        assertTokenBalance(address(tokenA), campaign, expectedCampaignBalance);

        // Verify both config types were used correctly
        assertConversionConfigCount(campaign, 2);

        // Finalize campaign
        finalizeCampaign(campaign, attributionProvider);
        assertCampaignStatus(campaign, Flywheel.CampaignStatus.FINALIZED);

        // Final invariant check
        assertCampaignInvariants(campaign, address(tokenA));
    }

    /// @dev Campaign with fund recovery scenario (never activated)
    /// @param advertiser Advertiser address
    /// @param attributionProvider Attribution provider address
    /// @param campaignFunding Initial campaign funding amount
    /// @param feeBps Attribution provider fee in basis points
    function test_integration_fundRecoveryScenario(
        address advertiser,
        address attributionProvider,
        uint256 campaignFunding,
        uint16 feeBps
    ) public {
        // Constrain inputs
        vm.assume(advertiser != address(0) && attributionProvider != address(0));
        vm.assume(advertiser != attributionProvider);
        campaignFunding = bound(campaignFunding, MIN_CAMPAIGN_FUNDING, MAX_CAMPAIGN_FUNDING);
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, adConversion.MAX_BPS()));

        // Create campaign
        address campaign = createCampaign(
            advertiser,
            attributionProvider,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        assertCampaignStatus(campaign, Flywheel.CampaignStatus.INACTIVE);

        // Fund campaign but never activate it
        fundCampaign(campaign, address(tokenA), campaignFunding);
        assertTokenBalance(address(tokenA), campaign, campaignFunding);

        // Record advertiser's initial balance
        uint256 advertiserBalanceBefore = tokenA.balanceOf(advertiser);

        // Advertiser can directly finalize an inactive campaign (fund recovery)
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "Fund recovery");

        assertCampaignStatus(campaign, Flywheel.CampaignStatus.FINALIZED);

        // No fees should be allocated since no attributions were processed
        assertAllocatedFee(campaign, address(tokenA), attributionProvider, 0);

        // Withdraw all funds back to advertiser
        uint256 remainingBalance = tokenA.balanceOf(campaign);
        vm.prank(advertiser);
        flywheel.withdrawFunds(campaign, address(tokenA), abi.encode(advertiser, remainingBalance));

        // Verify advertiser recovered all funds
        assertTokenBalance(address(tokenA), advertiser, advertiserBalanceBefore + campaignFunding);

        // Campaign should be empty
        assertTokenBalance(address(tokenA), campaign, 0);

        // Verify campaign completed lifecycle correctly
        assertCampaignCompletedLifecycle(campaign, address(tokenA), attributionProvider);

        // Final invariant check
        assertCampaignInvariants(campaign, address(tokenA));
    }

    // ========================================
    // PUBLISHER ALLOWLIST INTEGRATION TESTS
    // ========================================

    /// @dev Campaign with dynamic allowlist management during operation
    /// @param advertiser Advertiser address
    /// @param attributionProvider Attribution provider address
    /// @param publisher Publisher address
    /// @param publisherRefCode Publisher reference code
    /// @param campaignFunding Initial campaign funding amount
    /// @param attributionAmount Attribution payout amount
    /// @param feeBps Attribution provider fee in basis points
    function test_integration_dynamicAllowlistManagement(
        address advertiser,
        address attributionProvider,
        address publisher,
        string memory publisherRefCode,
        uint256 campaignFunding,
        uint256 attributionAmount,
        uint16 feeBps
    ) public {
        // Constrain inputs
        vm.assume(advertiser != address(0) && attributionProvider != address(0));
        vm.assume(advertiser != attributionProvider);
        campaignFunding = bound(campaignFunding, MIN_CAMPAIGN_FUNDING, 1000 ether); // Cap at reasonable amount
        attributionAmount = bound(attributionAmount, MIN_ATTRIBUTION_AMOUNT, campaignFunding / 10); // Conservative for 2 attributions + fees
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, 1000)); // Cap fees at 10%

        // Create initial allowlist with REF_CODE_1 only
        string[] memory initialAllowlist = new string[](1);
        initialAllowlist[0] = REF_CODE_1;

        address campaign = createCampaign(
            advertiser,
            attributionProvider,
            initialAllowlist,
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        // Verify initial allowlist state
        assertTrue(adConversion.hasPublisherAllowlist(campaign), "Campaign should have allowlist");
        assertTrue(adConversion.isPublisherRefCodeAllowed(campaign, REF_CODE_1), "REF_CODE_1 should be allowed");
        assertFalse(
            adConversion.isPublisherRefCodeAllowed(campaign, REF_CODE_2), "REF_CODE_2 should not be allowed initially"
        );

        // Fund and activate campaign
        fundCampaign(campaign, address(tokenA), campaignFunding);
        activateCampaign(campaign, attributionProvider);

        // Process attribution with allowed ref code
        AdConversion.Attribution memory attribution1 =
            createOffchainAttribution(REF_CODE_1, publisherPayout1, attributionAmount);
        processAttribution(campaign, address(tokenA), attribution1, attributionProvider);

        // Add REF_CODE_2 to allowlist during active campaign
        vm.prank(advertiser);
        adConversion.addAllowedPublisherRefCode(campaign, REF_CODE_2);

        // Verify REF_CODE_2 is now allowed
        assertTrue(adConversion.isPublisherRefCodeAllowed(campaign, REF_CODE_2), "REF_CODE_2 should now be allowed");

        // Process attribution with newly allowed ref code
        AdConversion.Attribution memory attribution2 =
            createOffchainAttribution(REF_CODE_2, publisherPayout2, attributionAmount);
        processAttribution(campaign, address(tokenA), attribution2, attributionProvider);

        // Add REF_CODE_3 as well
        vm.prank(advertiser);
        adConversion.addAllowedPublisherRefCode(campaign, REF_CODE_3);

        // Verify REF_CODE_3 is now allowed
        assertTrue(adConversion.isPublisherRefCodeAllowed(campaign, REF_CODE_3), "REF_CODE_3 should now be allowed");

        // Calculate expected fee and remaining balance (per-attribution rounding like the contract)
        uint256 totalAttributionAmount = attributionAmount * 2;
        uint256 totalFeeAmount = ((attributionAmount * feeBps) / adConversion.MAX_BPS()) * 2; // Calculate per attribution
        uint256 totalPayoutAmount = totalAttributionAmount - totalFeeAmount;
        uint256 expectedCampaignBalance = campaignFunding - totalPayoutAmount;

        // Verify fee allocation and balance
        assertAllocatedFee(campaign, address(tokenA), attributionProvider, totalFeeAmount);
        assertTokenBalance(address(tokenA), campaign, expectedCampaignBalance);

        // Finalize campaign
        finalizeCampaign(campaign, attributionProvider);

        // Verify all ref codes remain in allowlist even after finalization
        assertTrue(adConversion.isPublisherRefCodeAllowed(campaign, REF_CODE_1), "REF_CODE_1 should still be allowed");
        assertTrue(adConversion.isPublisherRefCodeAllowed(campaign, REF_CODE_2), "REF_CODE_2 should still be allowed");
        assertTrue(adConversion.isPublisherRefCodeAllowed(campaign, REF_CODE_3), "REF_CODE_3 should still be allowed");

        // Final invariant check
        assertCampaignInvariants(campaign, address(tokenA));
    }

    // ========================================
    // CONVERSION CONFIG INTEGRATION TESTS
    // ========================================

    /// @dev Campaign with dynamic conversion config management - using fixed values for stability
    function test_integration_conversionConfigManagement() public {
        address advertiser = advertiser1;
        address attributionProvider = attributionProvider1;
        uint256 campaignFunding = 100 ether;
        uint256 attributionAmount = 1 ether; // Conservative amount for 3 attributions + fees
        uint16 feeBps = 500; // 5% fees

        // Create campaign with default configs (2 configs)
        address campaign = createCampaign(
            advertiser,
            attributionProvider,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        // Verify initial config count
        assertConversionConfigCount(campaign, 2);

        // Fund and activate campaign
        fundCampaign(campaign, address(tokenA), campaignFunding);
        activateCampaign(campaign, attributionProvider);

        // Process attribution with config 1 (offchain)
        AdConversion.Attribution memory attribution1 =
            createOffchainAttribution(REF_CODE_1, publisherPayout1, attributionAmount);
        processAttribution(campaign, address(tokenA), attribution1, attributionProvider);

        // Process attribution with config 2 (onchain)
        AdConversion.Attribution memory attribution2 =
            createOnchainAttribution(REF_CODE_2, publisherPayout2, attributionAmount);
        processAttribution(campaign, address(tokenA), attribution2, attributionProvider);

        // Add new conversion config during active campaign
        AdConversion.ConversionConfigInput memory newConfig = AdConversion.ConversionConfigInput({
            isEventOnchain: true, metadataURI: "https://new-config.example.com/metadata"
        });

        vm.prank(advertiser);
        adConversion.addConversionConfig(campaign, newConfig);

        // Verify config count increased
        assertConversionConfigCount(campaign, 3);

        // Verify new config properties
        assertConversionConfig(campaign, 3, true, true, "https://new-config.example.com/metadata");

        // Create attribution using new config ID 3 (onchain)
        AdConversion.Attribution memory attribution3 =
            createOnchainAttribution(REF_CODE_3, publisherPayout3, attributionAmount);
        attribution3.conversion.configId = 3; // Set to use new config
        processAttribution(campaign, address(tokenA), attribution3, attributionProvider);

        // Disable config 1 during active campaign
        vm.prank(advertiser);
        adConversion.disableConversionConfig(campaign, 1);

        // Verify config 1 is now disabled
        assertConversionConfig(campaign, 1, false, false, "https://campaign.example.com/offchain-config");

        // Config count should remain the same
        assertConversionConfigCount(campaign, 3);

        // Calculate expected totals
        uint256 totalAttributionAmount = attributionAmount * 3;
        uint256 totalFeeAmount = (totalAttributionAmount * feeBps) / adConversion.MAX_BPS();
        uint256 totalPayoutAmount = totalAttributionAmount - totalFeeAmount; // Only payouts are sent immediately
        uint256 expectedCampaignBalance = campaignFunding - totalPayoutAmount; // Fees stay in campaign until distributed

        // Verify fee allocation and balance
        assertAllocatedFee(campaign, address(tokenA), attributionProvider, totalFeeAmount);
        assertTokenBalance(address(tokenA), campaign, expectedCampaignBalance);

        // Finalize campaign
        finalizeCampaign(campaign, attributionProvider);

        // Verify config state persists after finalization
        assertConversionConfigCount(campaign, 3);
        assertConversionConfig(campaign, 1, false, false, "https://campaign.example.com/offchain-config"); // Still disabled
        assertConversionConfig(campaign, 2, true, true, "https://campaign.example.com/onchain-config"); // Still active
        assertConversionConfig(campaign, 3, true, true, "https://new-config.example.com/metadata"); // Still active

        // Final invariant check
        assertCampaignInvariants(campaign, address(tokenA));
    }

    // ========================================
    // FEE COLLECTION INTEGRATION TESTS
    // ========================================

    /// @dev Complete fee collection workflow with varying fee rates
    /// @param advertiser Advertiser address
    /// @param attributionProvider Attribution provider address
    /// @param publisher Publisher address
    /// @param publisherRefCode Publisher reference code
    /// @param campaignFunding Initial campaign funding amount
    /// @param attributionAmount Attribution payout amount
    /// @param feeBps Attribution provider fee in basis points
    function test_integration_completeFeeCollectionWorkflow(
        address advertiser,
        address attributionProvider,
        address publisher,
        string memory publisherRefCode,
        uint256 campaignFunding,
        uint256 attributionAmount,
        uint16 feeBps
    ) public {
        // Constrain inputs
        vm.assume(advertiser != address(0) && attributionProvider != address(0));
        vm.assume(advertiser != attributionProvider);
        campaignFunding = bound(campaignFunding, MIN_CAMPAIGN_FUNDING, MAX_CAMPAIGN_FUNDING);
        attributionAmount = bound(attributionAmount, MIN_ATTRIBUTION_AMOUNT, campaignFunding / 3);
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, adConversion.MAX_BPS()));

        // Create campaign
        address campaign = createCampaign(
            advertiser,
            attributionProvider,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        // Fund and activate campaign
        fundCampaign(campaign, address(tokenA), campaignFunding);
        activateCampaign(campaign, attributionProvider);

        // Record initial attribution provider balance
        uint256 providerBalanceBefore = tokenA.balanceOf(attributionProvider);

        // Process multiple attributions to accumulate fees
        uint256 totalAttributionAmount = 0;
        uint256 totalFeeAmount = 0;

        for (uint256 i = 0; i < 3; i++) {
            AdConversion.Attribution memory attribution =
                createOffchainAttribution(REF_CODE_1, publisherPayout1, attributionAmount);
            attribution.conversion.eventId = bytes16(uint128(block.timestamp + i));

            processAttribution(campaign, address(tokenA), attribution, attributionProvider);

            uint256 feeAmount = (attributionAmount * feeBps) / adConversion.MAX_BPS();
            totalAttributionAmount += attributionAmount;
            totalFeeAmount += feeAmount;
        }

        // Verify fee accumulation
        assertAllocatedFee(campaign, address(tokenA), attributionProvider, totalFeeAmount);

        // Finalize campaign
        finalizeCampaign(campaign, attributionProvider);

        // Distribute fees
        vm.prank(attributionProvider);
        flywheel.distributeFees(campaign, address(tokenA), abi.encode(attributionProvider));

        // Verify fee distribution
        assertTokenBalance(address(tokenA), attributionProvider, providerBalanceBefore + totalFeeAmount);

        // No more fees should be allocated after distribution
        assertAllocatedFee(campaign, address(tokenA), attributionProvider, 0);

        // Verify remaining campaign balance
        uint256 expectedRemainingBalance = campaignFunding - totalAttributionAmount;
        assertTokenBalance(address(tokenA), campaign, expectedRemainingBalance);

        // Advertiser can withdraw remaining funds (if any)
        uint256 advertiserBalanceBefore = tokenA.balanceOf(advertiser);
        uint256 remainingBalance = tokenA.balanceOf(campaign);

        if (remainingBalance > 0) {
            vm.prank(advertiser);
            flywheel.withdrawFunds(campaign, address(tokenA), abi.encode(advertiser, remainingBalance));
        }

        // Verify fund withdrawal
        assertTokenBalance(address(tokenA), advertiser, advertiserBalanceBefore + expectedRemainingBalance);
        assertTokenBalance(address(tokenA), campaign, 0);

        // Verify campaign completed lifecycle
        assertCampaignCompletedLifecycle(campaign, address(tokenA), attributionProvider);

        // Final invariant check
        assertCampaignInvariants(campaign, address(tokenA));
    }

    // ========================================
    // MULTI-TOKEN INTEGRATION TESTS
    // ========================================

    /// @dev Campaign with multiple token types - using fixed values for stability
    function test_integration_multiTokenCampaign() public {
        MultiTokenParams memory params = MultiTokenParams({
            advertiser: advertiser1,
            attributionProvider: attributionProvider1,
            publisher: publisherPayout1,
            tokenAddr1: address(tokenA),
            tokenAddr2: address(tokenB),
            funding1: 50 ether,
            funding2: 30 ether,
            attribution1: 5 ether,
            attribution2: 3 ether,
            feeBps: 500 // 5% fees
        });

        address campaign = _createAndFundMultiTokenCampaign(params);
        _processMultiTokenAttributions(campaign, params);
        _finalizeAndDistributeMultiTokenFees(campaign, params);
        _verifyMultiTokenFinalState(campaign, params);
    }

    function _createAndFundMultiTokenCampaign(MultiTokenParams memory params) internal returns (address campaign) {
        // Create campaign
        campaign = createCampaign(
            params.advertiser,
            params.attributionProvider,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            params.feeBps
        );

        // Fund campaign with both tokens
        fundCampaign(campaign, params.tokenAddr1, params.funding1);
        fundCampaign(campaign, params.tokenAddr2, params.funding2);

        // Verify funding
        assertTokenBalance(params.tokenAddr1, campaign, params.funding1);
        assertTokenBalance(params.tokenAddr2, campaign, params.funding2);

        // Activate campaign
        activateCampaign(campaign, params.attributionProvider);
    }

    function _processMultiTokenAttributions(address campaign, MultiTokenParams memory params) internal {
        BalanceTracker memory balances = BalanceTracker({
            publisher1Before: tokenA.balanceOf(publisherPayout1),
            publisher2Before: tokenB.balanceOf(publisherPayout1),
            provider1Before: tokenA.balanceOf(params.attributionProvider),
            provider2Before: tokenB.balanceOf(params.attributionProvider),
            advertiser1Before: 0, // Will be set later
            advertiser2Before: 0 // Will be set later
        });

        // Process attribution for token1
        AdConversion.Attribution memory attribution1 =
            createOffchainAttribution(REF_CODE_1, publisherPayout1, params.attribution1);
        processAttribution(campaign, params.tokenAddr1, attribution1, params.attributionProvider);

        // Process attribution for token2
        AdConversion.Attribution memory attribution2 =
            createOffchainAttribution(REF_CODE_1, publisherPayout1, params.attribution2);
        attribution2.conversion.eventId = bytes16(uint128(block.timestamp + 1)); // Different event ID
        processAttribution(campaign, params.tokenAddr2, attribution2, params.attributionProvider);

        _verifyMultiTokenPayouts(campaign, params, balances);
    }

    function _verifyMultiTokenPayouts(address campaign, MultiTokenParams memory params, BalanceTracker memory balances)
        internal
    {
        FeeCalculation memory calc = FeeCalculation({
            fee1: (params.attribution1 * params.feeBps) / adConversion.MAX_BPS(),
            payout1: 0, // Will be calculated
            fee2: (params.attribution2 * params.feeBps) / adConversion.MAX_BPS(),
            payout2: 0, // Will be calculated
            remaining1: 0, // Will be set later
            remaining2: 0 // Will be set later
        });

        calc.payout1 = params.attribution1 - calc.fee1;
        calc.payout2 = params.attribution2 - calc.fee2;

        // Verify payouts
        assertTokenBalance(params.tokenAddr1, publisherPayout1, balances.publisher1Before + calc.payout1);
        assertTokenBalance(params.tokenAddr2, publisherPayout1, balances.publisher2Before + calc.payout2);

        // Verify fee allocations
        assertAllocatedFee(campaign, params.tokenAddr1, params.attributionProvider, calc.fee1);
        assertAllocatedFee(campaign, params.tokenAddr2, params.attributionProvider, calc.fee2);

        // Verify campaign balances (only payouts are sent, fees stay in campaign)
        assertTokenBalance(params.tokenAddr1, campaign, params.funding1 - calc.payout1);
        assertTokenBalance(params.tokenAddr2, campaign, params.funding2 - calc.payout2);
    }

    function _finalizeAndDistributeMultiTokenFees(address campaign, MultiTokenParams memory params) internal {
        BalanceTracker memory balances = BalanceTracker({
            publisher1Before: 0, // Not needed here
            publisher2Before: 0, // Not needed here
            provider1Before: tokenA.balanceOf(params.attributionProvider),
            provider2Before: tokenB.balanceOf(params.attributionProvider),
            advertiser1Before: tokenA.balanceOf(params.advertiser),
            advertiser2Before: tokenB.balanceOf(params.advertiser)
        });

        FeeCalculation memory calc = FeeCalculation({
            fee1: (params.attribution1 * params.feeBps) / adConversion.MAX_BPS(),
            payout1: 0, // Not needed
            fee2: (params.attribution2 * params.feeBps) / adConversion.MAX_BPS(),
            payout2: 0, // Not needed
            remaining1: tokenA.balanceOf(campaign),
            remaining2: tokenB.balanceOf(campaign)
        });

        // Finalize campaign
        finalizeCampaign(campaign, params.attributionProvider);

        // Distribute fees for both tokens
        vm.startPrank(params.attributionProvider);
        flywheel.distributeFees(campaign, params.tokenAddr1, abi.encode(params.attributionProvider));
        flywheel.distributeFees(campaign, params.tokenAddr2, abi.encode(params.attributionProvider));
        vm.stopPrank();

        // Verify fee distributions
        assertTokenBalance(params.tokenAddr1, params.attributionProvider, balances.provider1Before + calc.fee1);
        assertTokenBalance(params.tokenAddr2, params.attributionProvider, balances.provider2Before + calc.fee2);

        // Update remaining balances after fee distribution
        calc.remaining1 = tokenA.balanceOf(campaign);
        calc.remaining2 = tokenB.balanceOf(campaign);

        // Withdraw remaining funds for both tokens
        vm.startPrank(params.advertiser);
        if (calc.remaining1 > 0) {
            flywheel.withdrawFunds(campaign, params.tokenAddr1, abi.encode(params.advertiser, calc.remaining1));
        }
        if (calc.remaining2 > 0) {
            flywheel.withdrawFunds(campaign, params.tokenAddr2, abi.encode(params.advertiser, calc.remaining2));
        }
        vm.stopPrank();

        // Verify final fund withdrawals
        assertTokenBalance(
            params.tokenAddr1, params.advertiser, balances.advertiser1Before + (params.funding1 - params.attribution1)
        );
        assertTokenBalance(
            params.tokenAddr2, params.advertiser, balances.advertiser2Before + (params.funding2 - params.attribution2)
        );
    }

    function _verifyMultiTokenFinalState(address campaign, MultiTokenParams memory params) internal {
        // Campaigns should be empty
        assertTokenBalance(params.tokenAddr1, campaign, 0);
        assertTokenBalance(params.tokenAddr2, campaign, 0);

        // Final invariant checks for both tokens
        assertCampaignInvariants(campaign, params.tokenAddr1);
        assertCampaignInvariants(campaign, params.tokenAddr2);
    }

    // ========================================
    // SECURITY INTEGRATION TESTS
    // ========================================

    /// @dev Attribution window bypass vulnerability prevention
    /// @param advertiser Advertiser address
    /// @param attributionProvider Attribution provider address
    /// @param publisher Publisher address
    /// @param publisherRefCode Publisher reference code
    /// @param campaignFunding Initial campaign funding amount
    /// @param attributionAmount Attribution payout amount
    /// @param attributionWindow Attribution window in days
    /// @param feeBps Attribution provider fee in basis points
    function test_integration_attributionWindowBypassPrevention(
        address advertiser,
        address attributionProvider,
        address publisher,
        string memory publisherRefCode,
        uint256 campaignFunding,
        uint256 attributionAmount,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs
        vm.assume(advertiser != address(0) && attributionProvider != address(0));
        vm.assume(advertiser != attributionProvider);
        campaignFunding = bound(campaignFunding, MIN_CAMPAIGN_FUNDING, MAX_CAMPAIGN_FUNDING);
        attributionAmount = bound(attributionAmount, MIN_ATTRIBUTION_AMOUNT, campaignFunding / 2);
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, adConversion.MAX_BPS()));

        // Constrain attribution window to valid range (1-180 days)
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 1, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds

        // Create campaign with specific attribution window
        address campaign = createCampaign(
            advertiser,
            attributionProvider,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            attributionWindow,
            feeBps
        );

        // Fund and activate campaign
        fundCampaign(campaign, address(tokenA), campaignFunding);
        activateCampaign(campaign, attributionProvider);

        // Process attribution
        AdConversion.Attribution memory attribution =
            createOffchainAttribution(REF_CODE_1, publisherPayout1, attributionAmount);
        processAttribution(campaign, address(tokenA), attribution, attributionProvider);

        // Advertiser moves campaign to FINALIZING
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertCampaignStatus(campaign, Flywheel.CampaignStatus.FINALIZING);

        // Time passes but not enough for attribution window to expire
        uint256 partialTime = attributionWindow / 2;
        vm.warp(block.timestamp + partialTime);

        // Advertiser should NOT be able to finalize before attribution window expires
        vm.expectRevert(AdConversion.Unauthorized.selector);
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");

        // Attribution provider should still be able to finalize (bypass allowed)
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");
        assertCampaignStatus(campaign, Flywheel.CampaignStatus.FINALIZED);

        // Verify campaign completed correctly despite bypass
        assertCampaignInvariants(campaign, address(tokenA));
    }

    /// @dev Malicious pause attack prevention
    /// @param advertiser Advertiser address
    /// @param attributionProvider Attribution provider address
    /// @param maliciousActor Malicious actor address
    /// @param campaignFunding Initial campaign funding amount
    /// @param feeBps Attribution provider fee in basis points
    function test_integration_maliciousPauseAttackPrevention(
        address advertiser,
        address attributionProvider,
        address maliciousActor,
        uint256 campaignFunding,
        uint16 feeBps
    ) public {
        // Constrain inputs
        vm.assume(advertiser != address(0) && attributionProvider != address(0) && maliciousActor != address(0));
        vm.assume(advertiser != attributionProvider);
        vm.assume(maliciousActor != advertiser && maliciousActor != attributionProvider);
        campaignFunding = bound(campaignFunding, MIN_CAMPAIGN_FUNDING, MAX_CAMPAIGN_FUNDING);
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, adConversion.MAX_BPS()));

        // Create campaign
        address campaign = createCampaign(
            advertiser,
            attributionProvider,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps
        );

        // Fund and activate campaign
        fundCampaign(campaign, address(tokenA), campaignFunding);
        activateCampaign(campaign, attributionProvider);

        // Malicious actor should NOT be able to pause the campaign
        // AdConversion hook doesn't support pause functionality, so this should revert
        vm.expectRevert();
        vm.prank(maliciousActor);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.INACTIVE, "malicious pause");

        // Campaign should still be active
        assertCampaignStatus(campaign, Flywheel.CampaignStatus.ACTIVE);

        // Process normal attribution to show campaign still works (use small amount to avoid solvency issues)
        uint256 attributionAmount = campaignFunding / 10; // Use smaller amount to ensure solvency
        AdConversion.Attribution memory attribution =
            createOffchainAttribution(REF_CODE_1, publisherPayout1, attributionAmount);
        processAttribution(campaign, address(tokenA), attribution, attributionProvider);

        // Verify attribution was processed successfully
        uint256 expectedFee = (attributionAmount * feeBps) / adConversion.MAX_BPS();
        assertAllocatedFee(campaign, address(tokenA), attributionProvider, expectedFee);

        // Malicious actor should NOT be able to finalize campaign
        vm.expectRevert();
        vm.prank(maliciousActor);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "malicious finalize");

        // Campaign should still be active
        assertCampaignStatus(campaign, Flywheel.CampaignStatus.ACTIVE);

        // Legitimate finalization should still work
        finalizeCampaign(campaign, attributionProvider);
        assertCampaignStatus(campaign, Flywheel.CampaignStatus.FINALIZED);

        // Distribute fees first to avoid solvency issues
        vm.prank(attributionProvider);
        flywheel.distributeFees(campaign, address(tokenA), abi.encode(attributionProvider));

        // Malicious actor should NOT be able to withdraw funds
        vm.expectRevert();
        vm.prank(maliciousActor);
        flywheel.withdrawFunds(campaign, address(tokenA), "");

        // Only advertiser should be able to withdraw remaining funds (if any)
        uint256 advertiserBalanceBefore = tokenA.balanceOf(advertiser);
        uint256 remainingBalance = tokenA.balanceOf(campaign);

        if (remainingBalance > 0) {
            vm.prank(advertiser);
            flywheel.withdrawFunds(campaign, address(tokenA), abi.encode(advertiser, remainingBalance));
        }

        // Verify funds went to correct recipient
        uint256 expectedWithdrawal = campaignFunding - attributionAmount;
        assertTokenBalance(address(tokenA), advertiser, advertiserBalanceBefore + expectedWithdrawal);

        // Final invariant check
        assertCampaignInvariants(campaign, address(tokenA));
    }

    // ========================================
    // METADATA UPDATE INTEGRATION TESTS
    // ========================================

    /// @dev Campaign metadata updates during different lifecycle phases
    /// @param advertiser Advertiser address
    /// @param attributionProvider Attribution provider address
    /// @param publisher Publisher address
    /// @param publisherRefCode Publisher reference code
    /// @param campaignFunding Initial campaign funding amount
    /// @param attributionAmount Attribution payout amount
    /// @param newMetadata New metadata to set
    /// @param feeBps Attribution provider fee in basis points
    function test_integration_metadataUpdatesAcrossLifecycle(
        address advertiser,
        address attributionProvider,
        address publisher,
        string memory publisherRefCode,
        uint256 campaignFunding,
        uint256 attributionAmount,
        string memory newMetadata,
        uint16 feeBps
    ) public {
        // Constrain inputs
        vm.assume(advertiser != address(0) && attributionProvider != address(0));
        vm.assume(advertiser != attributionProvider);
        vm.assume(publisher != advertiser && publisher != attributionProvider);
        campaignFunding = bound(campaignFunding, MIN_CAMPAIGN_FUNDING, MAX_CAMPAIGN_FUNDING);
        attributionAmount = bound(attributionAmount, MIN_ATTRIBUTION_AMOUNT, campaignFunding / 2);
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, adConversion.MAX_BPS()));

        // Create campaign with initial metadata
        address campaign = createCampaignWithURI(
            advertiser,
            attributionProvider,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            feeBps,
            "https://initial.example.com/metadata"
        );

        // Verify initial metadata (URI is stored directly)
        string memory initialExpectedURI = "https://initial.example.com/metadata";
        assertCampaignURI(campaign, initialExpectedURI);

        // Test metadata update during INACTIVE phase
        vm.prank(advertiser);
        flywheel.updateMetadata(campaign, bytes(newMetadata));

        // Note: AdConversion hook only provides authorization for metadata updates
        // The actual metadata update logic is handled by Flywheel, not the hook
        // So the hook just validates the caller is authorized

        // Fund campaign
        fundCampaign(campaign, address(tokenA), campaignFunding);

        // Test metadata update during INACTIVE phase (still before activation)
        vm.prank(attributionProvider);
        flywheel.updateMetadata(campaign, "attribution provider metadata");

        // Activate campaign
        activateCampaign(campaign, attributionProvider);

        // Test metadata update during ACTIVE phase
        vm.prank(advertiser);
        flywheel.updateMetadata(campaign, "active phase metadata");

        // Process attribution
        AdConversion.Attribution memory attribution =
            createOffchainAttribution(REF_CODE_1, publisherPayout1, attributionAmount);
        processAttribution(campaign, address(tokenA), attribution, attributionProvider);

        // Test metadata update during ACTIVE phase with ongoing attributions
        vm.prank(attributionProvider);
        flywheel.updateMetadata(campaign, "mid-campaign update");

        // Move to FINALIZING
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Test metadata update during FINALIZING phase
        vm.prank(advertiser);
        flywheel.updateMetadata(campaign, "finalizing phase metadata");

        // Finalize campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");

        // Test unauthorized metadata updates are blocked
        vm.expectRevert();
        vm.prank(publisher);
        flywheel.updateMetadata(campaign, "unauthorized update");

        // Verify campaign state is still consistent
        assertCampaignStatus(campaign, Flywheel.CampaignStatus.FINALIZED);

        // Calculate expected fee
        uint256 expectedFee = (attributionAmount * feeBps) / adConversion.MAX_BPS();
        assertAllocatedFee(campaign, address(tokenA), attributionProvider, expectedFee);

        // Final invariant check
        assertCampaignInvariants(campaign, address(tokenA));
    }
}
