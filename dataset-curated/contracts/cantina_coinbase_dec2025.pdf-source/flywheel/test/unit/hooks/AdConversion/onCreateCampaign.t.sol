// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AdConversion} from "../../../../src/hooks/AdConversion.sol";
import {AdConversionTestBase} from "../../../lib/AdConversionTestBase.sol";
import {LibString} from "solady/utils/LibString.sol";

contract OnCreateCampaignTest is AdConversionTestBase {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when same address is used for provider and advertiser
    /// @param sameAddress Same address for advertiser and attribution provider
    function test_revert_sameRoleAddress(address sameAddress) public {
        vm.assume(sameAddress != address(0));

        // Create empty allowlist and configs
        string[] memory emptyAllowlist = new string[](0);
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Should revert when same address is used for provider and advertiser
        bytes memory hookData = abi.encode(
            sameAddress, sameAddress, "https://example.com/campaign", emptyAllowlist, emptyConfigs, 1 days, 1000
        );
        vm.expectRevert(AdConversion.SameRoleAddress.selector);
        flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    /// @dev Reverts when attribution window duration is not in days precision
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param allowedRefCodes Array of allowed publisher ref codes
    /// @param configs Array of conversion configs
    /// @param invalidWindow Attribution window that is not divisible by 1 day
    /// @param feeBps Attribution provider fee in basis points
    function test_revert_invalidAttributionWindowPrecision(
        address attributionProvider,
        address advertiser,
        string memory uri,
        string[] memory allowedRefCodes,
        AdConversion.ConversionConfigInput[] memory configs,
        uint48 invalidWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Generate invalid window that is not divisible by 1 day (86400 seconds)
        invalidWindow = uint48(bound(invalidWindow, 1, 86399)); // 1 day = 86400 seconds

        // Should revert for non-day precision window (expects InvalidAttributionWindow with parameter)
        vm.expectRevert(abi.encodeWithSelector(AdConversion.InvalidAttributionWindow.selector, invalidWindow));
        createCampaignWithURI(advertiser, attributionProvider, allowedRefCodes, configs, invalidWindow, feeBps, uri);
    }

    /// @dev Reverts when attribution window exceeds 180 days maximum
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param allowedRefCodes Array of allowed publisher ref codes
    /// @param configs Array of conversion configs
    /// @param excessiveWindow Attribution window greater than 180 days
    /// @param feeBps Attribution provider fee in basis points
    function test_revert_attributionWindowExceedsMaximum(
        address attributionProvider,
        address advertiser,
        string memory uri,
        string[] memory allowedRefCodes,
        AdConversion.ConversionConfigInput[] memory configs,
        uint48 excessiveWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Generate excessive window greater than 180 days
        excessiveWindow = uint48(bound(excessiveWindow, MAX_ATTRIBUTION_WINDOW + 86400, type(uint48).max)); // Add 1 day

        // Should revert for excessive attribution window (expects InvalidAttributionWindow with parameter)
        vm.expectRevert(abi.encodeWithSelector(AdConversion.InvalidAttributionWindow.selector, excessiveWindow));
        createCampaignWithURI(advertiser, attributionProvider, allowedRefCodes, configs, excessiveWindow, feeBps, uri);
    }

    /// @dev Reverts when attribution provider fee exceeds 100%
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param allowedRefCodes Array of allowed publisher ref codes
    /// @param configs Array of conversion configs
    /// @param attributionWindow Attribution window in days
    /// @param invalidFeeBps Fee BPS greater than MAX_BPS
    function test_revert_invalidFeeBps(
        address attributionProvider,
        address advertiser,
        string memory uri,
        string[] memory allowedRefCodes,
        AdConversion.ConversionConfigInput[] memory configs,
        uint48 attributionWindow,
        uint16 invalidFeeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Generate invalid fee greater than MAX_BPS (10000)
        invalidFeeBps = uint16(bound(invalidFeeBps, MAX_FEE_BPS + 1, type(uint16).max));

        // Should revert for invalid fee
        vm.expectRevert(abi.encodeWithSelector(AdConversion.InvalidFeeBps.selector, invalidFeeBps));
        createCampaignWithURI(
            advertiser,
            attributionProvider,
            new string[](0), // allowedRefCodes
            new AdConversion.ConversionConfigInput[](0), // configs
            attributionWindow,
            invalidFeeBps,
            uri
        );
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Successfully creates campaign with valid parameters
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param attributionWindow Attribution window in days
    /// @param feeBps Attribution provider fee in basis points
    function test_success_basicCampaign(
        address attributionProvider,
        address advertiser,
        string memory uri,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds), between 1 and 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 1, maxDays)); // Min 1 day
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Create empty allowlist and configs for basic campaign
        string[] memory emptyAllowlist = new string[](0);
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Should succeed with valid parameters
        createCampaignWithURI(
            advertiser,
            attributionProvider,
            emptyAllowlist,
            emptyConfigs,
            attributionWindow,
            feeBps,
            "https://campaign.example.com/metadata"
        );
    }

    /// @dev Successfully creates campaign with zero attribution window
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param feeBps Attribution provider fee in basis points
    function test_success_zeroAttributionWindow(
        address attributionProvider,
        address advertiser,
        string memory uri,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Create empty allowlist and configs
        string[] memory emptyAllowlist = new string[](0);
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Should succeed with zero attribution window
        createCampaignWithURI(
            advertiser,
            attributionProvider,
            emptyAllowlist,
            emptyConfigs,
            uint48(0),
            feeBps,
            "https://campaign.example.com/metadata"
        );
    }

    /// @dev Successfully creates campaign with maximum 180-day attribution window
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param feeBps Attribution provider fee in basis points
    function test_success_maximumAttributionWindow(
        address attributionProvider,
        address advertiser,
        string memory uri,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Create empty allowlist and configs
        string[] memory emptyAllowlist = new string[](0);
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Should succeed with maximum attribution window
        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, uri, emptyAllowlist, emptyConfigs, MAX_ATTRIBUTION_WINDOW, feeBps
        );
        flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    /// @dev Successfully creates campaign with zero fee
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param attributionWindow Attribution window in days
    function test_success_zeroFee(
        address attributionProvider,
        address advertiser,
        string memory uri,
        uint48 attributionWindow
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Create empty allowlist and configs
        string[] memory emptyAllowlist = new string[](0);
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Should succeed with zero fee
        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, uri, emptyAllowlist, emptyConfigs, attributionWindow, ZERO_FEE_BPS
        );
        flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    /// @dev Successfully creates campaign with maximum 100% fee
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param attributionWindow Attribution window in days
    function test_success_maximumFee(
        address attributionProvider,
        address advertiser,
        string memory uri,
        uint48 attributionWindow
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Create empty allowlist and configs
        string[] memory emptyAllowlist = new string[](0);
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Should succeed with maximum fee
        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, uri, emptyAllowlist, emptyConfigs, attributionWindow, MAX_FEE_BPS
        );
        flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    /// @dev Successfully creates campaign with publisher allowlist
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param attributionWindow Attribution window in days
    /// @param feeBps Attribution provider fee in basis points
    function test_success_withAllowlist(
        address attributionProvider,
        address advertiser,
        string memory uri,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Use predefined registered ref codes for allowlist
        string[] memory validAllowlist = new string[](2);
        validAllowlist[0] = REF_CODE_1;
        validAllowlist[1] = REF_CODE_2;

        // Create empty configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Should succeed with valid allowlist
        bytes memory hookData =
            abi.encode(attributionProvider, advertiser, uri, validAllowlist, emptyConfigs, attributionWindow, feeBps);
        flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    /// @dev Successfully creates campaign without publisher allowlist
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param attributionWindow Attribution window in days
    /// @param feeBps Attribution provider fee in basis points
    function test_success_withoutAllowlist(
        address attributionProvider,
        address advertiser,
        string memory uri,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Create empty allowlist and configs
        string[] memory emptyAllowlist = new string[](0);
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Should succeed without allowlist
        bytes memory hookData =
            abi.encode(attributionProvider, advertiser, uri, emptyAllowlist, emptyConfigs, attributionWindow, feeBps);
        flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    /// @dev Successfully creates campaign with conversion configs
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param configs Array of conversion configs
    /// @param attributionWindow Attribution window in days
    /// @param feeBps Attribution provider fee in basis points
    function test_success_withConversionConfigs(
        address attributionProvider,
        address advertiser,
        string memory uri,
        AdConversion.ConversionConfigInput[] memory configs,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Create predefined configs instead of using fuzzed input
        AdConversion.ConversionConfigInput[] memory validConfigs = new AdConversion.ConversionConfigInput[](2);
        validConfigs[0] = AdConversion.ConversionConfigInput({
            isEventOnchain: true, metadataURI: "https://example.com/onchain-config"
        });
        validConfigs[1] = AdConversion.ConversionConfigInput({
            isEventOnchain: false, metadataURI: "https://example.com/offchain-config"
        });

        // Create empty allowlist
        string[] memory emptyAllowlist = new string[](0);

        // Should succeed with valid conversion configs
        bytes memory hookData =
            abi.encode(attributionProvider, advertiser, uri, emptyAllowlist, validConfigs, attributionWindow, feeBps);
        flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    /// @dev Successfully creates campaign with empty conversion configs
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param attributionWindow Attribution window in days
    /// @param feeBps Attribution provider fee in basis points
    function test_success_emptyConversionConfigs(
        address attributionProvider,
        address advertiser,
        string memory uri,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Create empty allowlist and configs
        string[] memory emptyAllowlist = new string[](0);
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Should succeed with empty conversion configs
        bytes memory hookData =
            abi.encode(attributionProvider, advertiser, uri, emptyAllowlist, emptyConfigs, attributionWindow, feeBps);
        flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    // ========================================
    // EDGE CASES
    // ========================================

    /// @dev Handles campaign with empty URI
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param attributionWindow Attribution window in days
    /// @param feeBps Attribution provider fee in basis points
    function test_onCreateCampaign_edge_emptyURI(
        address attributionProvider,
        address advertiser,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Create empty allowlist and configs
        string[] memory emptyAllowlist = new string[](0);
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Should succeed with empty URI
        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "", // Empty URI
            emptyAllowlist,
            emptyConfigs,
            attributionWindow,
            feeBps
        );
        flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    /// @dev Handles campaign with same attribution provider and advertiser
    /// @param sameAddress Address for both attribution provider and advertiser
    /// @param uri Campaign URI
    /// @param attributionWindow Attribution window in days
    /// @param feeBps Attribution provider fee in basis points
    function test_onCreateCampaign_edge_sameProviderAndAdvertiser(
        address sameAddress,
        string memory uri,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(sameAddress != address(0));

        // Create empty allowlist and configs
        string[] memory emptyAllowlist = new string[](0);
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Should revert when same address is used for provider and advertiser
        bytes memory hookData = abi.encode(
            sameAddress,
            sameAddress, // Same address for both roles
            uri,
            emptyAllowlist,
            emptyConfigs,
            attributionWindow,
            feeBps
        );
        vm.expectRevert(AdConversion.SameRoleAddress.selector);
        flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    // ========================================
    // EVENT TESTING
    // ========================================

    /// @dev Emits AdCampaignCreated event with correct parameters
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param attributionWindow Attribution window in days
    /// @param feeBps Attribution provider fee in basis points
    function test_onCreateCampaign_emitsAdCampaignCreated(
        address attributionProvider,
        address advertiser,
        string memory uri,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Create empty allowlist and configs
        string[] memory emptyAllowlist = new string[](0);
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Create hookData for prediction
        bytes memory hookData =
            abi.encode(attributionProvider, advertiser, uri, emptyAllowlist, emptyConfigs, attributionWindow, feeBps);

        // Create campaign address for event verification
        address predictedCampaign =
            flywheel.predictCampaignAddress(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);

        // Expect the AdCampaignCreated event
        vm.expectEmit(true, true, false, true);
        emit AdConversion.AdCampaignCreated(predictedCampaign, attributionProvider, advertiser, uri, attributionWindow);

        // Create campaign (should emit event)
        flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    function test_onCreateCampaign_emitsPublisherAddedToAllowlist(
        address attributionProvider,
        address advertiser,
        string memory uri,
        string[] memory allowedRefCodes,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Use predefined allowlist with registered ref codes
        string[] memory validAllowlist = new string[](2);
        validAllowlist[0] = REF_CODE_1;
        validAllowlist[1] = REF_CODE_2;

        // Create empty configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Create hookData for prediction
        bytes memory hookData =
            abi.encode(attributionProvider, advertiser, uri, validAllowlist, emptyConfigs, attributionWindow, feeBps);

        // Create campaign address for event verification
        address predictedCampaign =
            flywheel.predictCampaignAddress(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);

        // Expect PublisherAddedToAllowlist events for each ref code
        vm.expectEmit(true, false, false, true);
        emit AdConversion.PublisherAddedToAllowlist(predictedCampaign, REF_CODE_1);
        vm.expectEmit(true, false, false, true);
        emit AdConversion.PublisherAddedToAllowlist(predictedCampaign, REF_CODE_2);

        // Create campaign with allowlist (should emit events)
        flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    function test_onCreateCampaign_emitsConversionConfigAdded(
        address attributionProvider,
        address advertiser,
        string memory uri,
        AdConversion.ConversionConfigInput[] memory configs,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Create predefined configs instead of using fuzzed input
        AdConversion.ConversionConfigInput[] memory validConfigs = new AdConversion.ConversionConfigInput[](2);
        validConfigs[0] = AdConversion.ConversionConfigInput({
            isEventOnchain: true, metadataURI: "https://example.com/onchain-config"
        });
        validConfigs[1] = AdConversion.ConversionConfigInput({
            isEventOnchain: false, metadataURI: "https://example.com/offchain-config"
        });

        // Create empty allowlist
        string[] memory emptyAllowlist = new string[](0);

        // Create hookData for prediction
        bytes memory hookData =
            abi.encode(attributionProvider, advertiser, uri, emptyAllowlist, validConfigs, attributionWindow, feeBps);

        // Create campaign address for event verification
        address predictedCampaign =
            flywheel.predictCampaignAddress(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);

        // Create expected conversion configs for events
        AdConversion.ConversionConfig memory expectedConfig1 = AdConversion.ConversionConfig({
            isActive: true, isEventOnchain: true, metadataURI: "https://example.com/onchain-config"
        });
        AdConversion.ConversionConfig memory expectedConfig2 = AdConversion.ConversionConfig({
            isActive: true, isEventOnchain: false, metadataURI: "https://example.com/offchain-config"
        });

        // Expect ConversionConfigAdded events
        vm.expectEmit(true, true, false, true);
        emit AdConversion.ConversionConfigAdded(predictedCampaign, 1, expectedConfig1);
        vm.expectEmit(true, true, false, true);
        emit AdConversion.ConversionConfigAdded(predictedCampaign, 2, expectedConfig2);

        // Create campaign with configs (should emit events)
        flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    // ========================================
    // STATE VERIFICATION
    // ========================================

    /// @dev Verifies campaign state is correctly stored
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param allowedRefCodes Array of allowed publisher ref codes
    /// @param configs Array of conversion configs
    /// @param attributionWindow Attribution window in days
    /// @param feeBps Attribution provider fee in basis points

    function test_onCreateCampaign_verifiesStoredState(
        address attributionProvider,
        address advertiser,
        string memory uri,
        string[] memory allowedRefCodes,
        AdConversion.ConversionConfigInput[] memory configs,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Use predefined values for testing
        string[] memory validAllowlist = new string[](1);
        validAllowlist[0] = REF_CODE_1;

        AdConversion.ConversionConfigInput[] memory validConfigs = new AdConversion.ConversionConfigInput[](1);
        validConfigs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/test-config"});

        // Create campaign
        bytes memory hookData =
            abi.encode(attributionProvider, advertiser, uri, validAllowlist, validConfigs, attributionWindow, feeBps);
        address campaign = flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);

        // Verify stored state
        // campaignURI() returns the URI directly as stored
        string memory expectedURI = uri;
        assertEq(
            adConversion.campaignURI(campaign),
            expectedURI,
            "Campaign URI should be stored correctly in expected format"
        );
        assertTrue(adConversion.hasPublisherAllowlist(campaign), "Should have allowlist when provided");
        assertTrue(adConversion.allowedPublishers(campaign, REF_CODE_1), "REF_CODE_1 should be in allowlist");
        assertEq(adConversion.conversionConfigCount(campaign), 1, "Should have 1 conversion config");

        AdConversion.ConversionConfig memory storedConfig = adConversion.getConversionConfig(campaign, 1);
        assertTrue(storedConfig.isActive, "Config should be active");
        assertTrue(storedConfig.isEventOnchain, "Config should be onchain");
        assertEq(storedConfig.metadataURI, "https://example.com/test-config", "Config metadata should match");
    }

    /// @dev Verifies conversion config count is correctly updated
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param configs Array of conversion configs
    /// @param attributionWindow Attribution window in days
    /// @param feeBps Attribution provider fee in basis points
    function test_onCreateCampaign_verifiesConversionConfigCount(
        address attributionProvider,
        address advertiser,
        string memory uri,
        AdConversion.ConversionConfigInput[] memory configs,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Test with 3 predefined configs
        AdConversion.ConversionConfigInput[] memory validConfigs = new AdConversion.ConversionConfigInput[](3);
        validConfigs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/config1"});
        validConfigs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config2"});
        validConfigs[2] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/config3"});

        // Create empty allowlist
        string[] memory emptyAllowlist = new string[](0);

        // Create campaign
        bytes memory hookData =
            abi.encode(attributionProvider, advertiser, uri, emptyAllowlist, validConfigs, attributionWindow, feeBps);
        address campaign = flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);

        // Verify config count
        assertEq(adConversion.conversionConfigCount(campaign), 3, "Should have 3 conversion configs");

        // Verify each config exists and is correct
        for (uint16 i = 1; i <= 3; i++) {
            AdConversion.ConversionConfig memory config = adConversion.getConversionConfig(campaign, i);
            assertTrue(config.isActive, "All configs should be active");
        }
    }

    /// @dev Verifies allowlist mapping is correctly populated
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param uri Campaign URI
    /// @param allowedRefCodes Array of allowed publisher ref codes
    /// @param attributionWindow Attribution window in days
    /// @param feeBps Attribution provider fee in basis points
    function test_onCreateCampaign_verifiesAllowlistMapping(
        address attributionProvider,
        address advertiser,
        string memory uri,
        string[] memory allowedRefCodes,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Use predefined allowlist with registered ref codes
        string[] memory validAllowlist = new string[](3);
        validAllowlist[0] = REF_CODE_1;
        validAllowlist[1] = REF_CODE_2;
        validAllowlist[2] = REF_CODE_3;

        // Create empty configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Create campaign
        bytes memory hookData =
            abi.encode(attributionProvider, advertiser, uri, validAllowlist, emptyConfigs, attributionWindow, feeBps);
        address campaign = flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);

        // Verify allowlist mapping
        assertTrue(adConversion.hasPublisherAllowlist(campaign), "Should have allowlist");
        assertTrue(adConversion.allowedPublishers(campaign, REF_CODE_1), "REF_CODE_1 should be allowed");
        assertTrue(adConversion.allowedPublishers(campaign, REF_CODE_2), "REF_CODE_2 should be allowed");
        assertTrue(adConversion.allowedPublishers(campaign, REF_CODE_3), "REF_CODE_3 should be allowed");

        // Verify unregistered ref code is not allowed
        assertFalse(adConversion.allowedPublishers(campaign, "unregistered"), "Unregistered code should not be allowed");
    }

    /// @dev Verifies campaign metadata URI is correctly stored
    /// @param advertiser Advertiser address
    /// @param attributionProvider Attribution provider address
    /// @param campaignURI Campaign metadata URI
    /// @param attributionWindow Attribution window duration
    /// @param feeBps Attribution provider fee in basis points
    function test_onCreateCampaign_storesCampaignURI(
        address advertiser,
        address attributionProvider,
        string memory campaignURI,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Create empty allowlist and configs
        string[] memory emptyAllowlist = new string[](0);
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Create campaign
        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, campaignURI, emptyAllowlist, emptyConfigs, attributionWindow, feeBps
        );
        address campaign = flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);

        // Verify URI is stored correctly
        // campaignURI() now returns the URI directly (no address concatenation)
        string memory expectedURI = campaignURI;
        assertEq(adConversion.campaignURI(campaign), expectedURI, "Campaign URI should match expected format");
    }

    /// @dev Verifies allowlist flag is correctly set when no allowlist provided
    /// @param advertiser Advertiser address
    /// @param attributionProvider Attribution provider address
    /// @param attributionWindow Attribution window duration
    /// @param feeBps Attribution provider fee in basis points
    function test_onCreateCampaign_setsNoAllowlistFlag(
        address advertiser,
        address attributionProvider,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Create empty allowlist and configs
        string[] memory emptyAllowlist = new string[](0);
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Create campaign
        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, "test-uri", emptyAllowlist, emptyConfigs, attributionWindow, feeBps
        );
        address campaign = flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);

        // Verify no allowlist flag
        assertFalse(adConversion.hasPublisherAllowlist(campaign), "Should not have allowlist when empty array provided");
    }

    /// @dev Verifies allowlist flag is correctly set when allowlist provided
    /// @param advertiser Advertiser address
    /// @param attributionProvider Attribution provider address
    /// @param allowedRefCodes Array of allowed publisher reference codes
    /// @param attributionWindow Attribution window duration
    /// @param feeBps Attribution provider fee in basis points
    function test_onCreateCampaign_setsAllowlistFlag(
        address advertiser,
        address attributionProvider,
        string[] memory allowedRefCodes,
        uint48 attributionWindow,
        uint16 feeBps
    ) public {
        // Constrain inputs to valid ranges
        // Attribution window must be a multiple of 1 day (86400 seconds) and <= 180 days
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 0, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds
        feeBps = uint16(bound(feeBps, MIN_FEE_BPS, MAX_FEE_BPS));
        vm.assume(attributionProvider != address(0));
        vm.assume(advertiser != address(0));
        vm.assume(advertiser != attributionProvider);

        // Use predefined allowlist with at least one ref code
        string[] memory validAllowlist = new string[](1);
        validAllowlist[0] = REF_CODE_1;

        // Create empty configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);

        // Create campaign
        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, "test-uri", validAllowlist, emptyConfigs, attributionWindow, feeBps
        );
        address campaign = flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);

        // Verify allowlist flag
        assertTrue(adConversion.hasPublisherAllowlist(campaign), "Should have allowlist when non-empty array provided");
    }
}
