// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AdConversion} from "../../../../src/hooks/AdConversion.sol";
import {AdConversionTestBase} from "../../../lib/AdConversionTestBase.sol";
import {LibString} from "solady/utils/LibString.sol";

contract ViewFunctionsTest is AdConversionTestBase {
    /// @notice Helper function to combine default configs with additional configs
    function _createCombinedConfigs(AdConversion.ConversionConfigInput[] memory additionalConfigs)
        internal
        pure
        returns (AdConversion.ConversionConfigInput[] memory)
    {
        AdConversion.ConversionConfigInput[] memory defaultConfigs = _createDefaultConfigs();
        AdConversion.ConversionConfigInput[] memory combined =
            new AdConversion.ConversionConfigInput[](defaultConfigs.length + additionalConfigs.length);

        // Copy default configs first
        for (uint256 i = 0; i < defaultConfigs.length; i++) {
            combined[i] = defaultConfigs[i];
        }

        // Add additional configs
        for (uint256 i = 0; i < additionalConfigs.length; i++) {
            combined[defaultConfigs.length + i] = additionalConfigs[i];
        }

        return combined;
    }

    // ========================================
    // CAMPAIGN URI TESTING
    // ========================================

    /// @dev Returns correct campaign URI
    /// @param expectedURI Expected campaign URI
    function test_campaignURI_returnsCorrectURI(string memory expectedURI) public {
        // Create campaign with specific URI
        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            expectedURI
        );

        assertEq(adConversion.campaignURI(testCampaign), expectedURI, "Campaign URI should match expected format");
    }

    /// @dev Returns empty string for campaign with empty URI
    function test_campaignURI_returnsEmptyString() public {
        // Create campaign with empty URI
        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "" // Empty URI
        );

        // Verify empty URI is returned
        assertEq(adConversion.campaignURI(testCampaign), "", "Campaign URI should be empty string");
    }

    /// @dev Returns correct URI for campaigns with special characters
    function test_campaignURI_specialCharacters() public {
        string memory specialURI = "https://example.com/path?param=value&other=test#fragment";

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            new string[](0),
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            specialURI
        );

        assertEq(adConversion.campaignURI(testCampaign), specialURI, "Special characters should be preserved in URI");
    }

    /// @dev Returns correct URI for campaigns with very long strings
    function test_campaignURI_longString() public {
        string memory longURI =
            "https://example.com/very/long/path/with/many/segments/that/goes/on/and/on/and/on/with/lots/of/characters/to/test/string/handling/capabilities/of/the/contract/implementation/metadata.json";

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            new string[](0),
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            longURI
        );

        assertEq(adConversion.campaignURI(testCampaign), longURI, "Long URIs should be handled correctly");
    }

    // ========================================
    // GET CONVERSION CONFIG TESTING
    // ========================================

    /// @dev Returns correct conversion config for valid ID
    function test_getConversionConfig_returnsCorrectConfig() public {
        // Create campaign with configs
        address testCampaign = createBasicCampaign();

        // Get config 1 (offchain config from defaults - configs[0])
        AdConversion.ConversionConfig memory config1 = adConversion.getConversionConfig(testCampaign, 1);
        assertTrue(config1.isActive, "Config 1 should be active");
        assertFalse(config1.isEventOnchain, "Config 1 should be offchain");
        assertEq(config1.metadataURI, "https://campaign.example.com/offchain-config", "Config 1 metadata should match");

        // Get config 2 (onchain config from defaults - configs[1])
        AdConversion.ConversionConfig memory config2 = adConversion.getConversionConfig(testCampaign, 2);
        assertTrue(config2.isActive, "Config 2 should be active");
        assertTrue(config2.isEventOnchain, "Config 2 should be onchain");
        assertEq(config2.metadataURI, "https://campaign.example.com/onchain-config", "Config 2 metadata should match");
    }

    /// @dev Reverts when conversion config ID does not exist
    /// @param invalidConfigId Non-existent conversion config ID
    function test_getConversionConfig_revert_invalidId(uint16 invalidConfigId) public {
        // Create campaign with only 2 default configs
        address testCampaign = createBasicCampaign();

        // Constrain to invalid range (beyond existing configs)
        invalidConfigId = uint16(bound(invalidConfigId, 3, type(uint16).max));

        // Should revert for non-existent config ID
        vm.expectRevert(AdConversion.InvalidConversionConfigId.selector);
        adConversion.getConversionConfig(testCampaign, invalidConfigId);
    }

    /// @dev Reverts when trying to get config ID zero (reserved)
    function test_getConversionConfig_revert_configIdZero() public {
        // Create campaign with configs
        address testCampaign = createBasicCampaign();

        // Should revert for config ID 0 (reserved)
        vm.expectRevert(AdConversion.InvalidConversionConfigId.selector);
        adConversion.getConversionConfig(testCampaign, 0);
    }

    /// @dev Returns config with correct active status
    function test_getConversionConfig_returnsCorrectActiveStatus() public {
        // Create campaign with configs
        address testCampaign = createBasicCampaign();

        // Initially both configs should be active
        AdConversion.ConversionConfig memory activeConfig = adConversion.getConversionConfig(testCampaign, 1);
        assertTrue(activeConfig.isActive, "Config should initially be active");

        // Disable config 1
        vm.prank(advertiser1);
        adConversion.disableConversionConfig(testCampaign, 1);

        // Now config should be inactive
        AdConversion.ConversionConfig memory inactiveConfig = adConversion.getConversionConfig(testCampaign, 1);
        assertFalse(inactiveConfig.isActive, "Config should be inactive after disabling");

        // Config 2 should still be active
        AdConversion.ConversionConfig memory stillActiveConfig = adConversion.getConversionConfig(testCampaign, 2);
        assertTrue(stillActiveConfig.isActive, "Config 2 should still be active");
    }

    /// @dev Returns config with correct onchain status
    function test_getConversionConfig_returnsCorrectOnchainStatus() public {
        // Create campaign with additional onchain and offchain configs
        AdConversion.ConversionConfigInput[] memory additionalConfigs = new AdConversion.ConversionConfigInput[](2);
        additionalConfigs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/onchain-test"});
        additionalConfigs[1] = AdConversion.ConversionConfigInput({
            isEventOnchain: false, metadataURI: "https://example.com/offchain-test"
        });

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createCombinedConfigs(additionalConfigs), // Use combined configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://example.com/default"
        );

        // Verify onchain config (config ID 3, which is additionalConfigs[0])
        AdConversion.ConversionConfig memory onchainConfig = adConversion.getConversionConfig(testCampaign, 3);
        assertTrue(onchainConfig.isEventOnchain, "Config should be onchain");

        // Verify offchain config (config ID 4, which is additionalConfigs[1])
        AdConversion.ConversionConfig memory offchainConfig = adConversion.getConversionConfig(testCampaign, 4);
        assertFalse(offchainConfig.isEventOnchain, "Config should be offchain");
    }

    /// @dev Returns config with correct metadata URI
    function test_getConversionConfig_returnsCorrectMetadataURI() public {
        string memory customMetadata = "https://custom.example.com/metadata.json";

        // Create campaign with custom metadata config
        AdConversion.ConversionConfigInput[] memory additionalConfigs = new AdConversion.ConversionConfigInput[](1);
        additionalConfigs[0] = AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: customMetadata});

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createCombinedConfigs(additionalConfigs), // Use combined configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://example.com/default"
        );

        // Verify custom metadata is returned correctly (config ID 3, which is additionalConfigs[0])
        AdConversion.ConversionConfig memory customConfig = adConversion.getConversionConfig(testCampaign, 3);
        assertEq(customConfig.metadataURI, customMetadata, "Metadata URI should match custom value");
    }

    /// @dev Returns config with empty metadata URI
    function test_getConversionConfig_emptyMetadataURI() public {
        // Create campaign with empty metadata config
        AdConversion.ConversionConfigInput[] memory additionalConfigs = new AdConversion.ConversionConfigInput[](1);
        additionalConfigs[0] =
            AdConversion.ConversionConfigInput({
                isEventOnchain: true,
                metadataURI: "" // Empty metadata
            });

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createCombinedConfigs(additionalConfigs), // Use combined configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://example.com/default"
        );

        // Verify empty metadata is returned correctly (config ID 3, which is additionalConfigs[0])
        AdConversion.ConversionConfig memory emptyConfig = adConversion.getConversionConfig(testCampaign, 3);
        assertEq(emptyConfig.metadataURI, "", "Metadata URI should be empty");
    }

    // ========================================
    // CONVERSION CONFIG COUNT TESTING
    // ========================================

    /// @dev Returns correct conversion config count
    function test_conversionConfigCount_returnsCorrectCount() public {
        // Create campaign with only default configs
        address testCampaign = createBasicCampaign();
        assertEq(adConversion.conversionConfigCount(testCampaign), 2, "Should have 2 default configs");

        // Add one more config
        AdConversion.ConversionConfigInput memory newConfig =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/new-config"});

        vm.prank(advertiser1);
        adConversion.addConversionConfig(testCampaign, newConfig);

        assertEq(adConversion.conversionConfigCount(testCampaign), 3, "Should have 3 configs after adding one");
    }

    /// @dev Config count doesn't change when disabling configs
    function test_conversionConfigCount_unchangedAfterDisabling() public {
        address testCampaign = createBasicCampaign();
        uint16 initialCount = adConversion.conversionConfigCount(testCampaign);

        // Disable a config
        vm.prank(advertiser1);
        adConversion.disableConversionConfig(testCampaign, 1);

        // Count should remain the same
        assertEq(
            adConversion.conversionConfigCount(testCampaign), initialCount, "Count should not change after disabling"
        );
    }

    // ========================================
    // HAS PUBLISHER ALLOWLIST TESTING
    // ========================================

    /// @dev Returns false when campaign has no allowlist
    function test_hasPublisherAllowlist_noAllowlist() public {
        // Create campaign without allowlist
        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            new string[](0), // Empty allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://campaign.example.com/metadata"
        );

        // Should return false for no allowlist
        assertFalse(adConversion.hasPublisherAllowlist(testCampaign), "Should return false when no allowlist exists");
    }

    /// @dev Returns true when campaign has allowlist
    function test_hasPublisherAllowlist_withAllowlist() public {
        // Create campaign with allowlist
        string[] memory allowlist = new string[](1);
        allowlist[0] = REF_CODE_1;

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            allowlist,
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://campaign.example.com/metadata"
        );

        // Should return true for campaign with allowlist
        assertTrue(adConversion.hasPublisherAllowlist(testCampaign), "Should return true when allowlist exists");
    }

    // ========================================
    // ALLOWED PUBLISHERS TESTING
    // ========================================

    /// @dev Returns true for allowed ref code when allowlist exists
    function test_allowedPublishers_allowedCode() public {
        // Create campaign with allowlist
        string[] memory allowlist = new string[](2);
        allowlist[0] = REF_CODE_1;
        allowlist[1] = REF_CODE_2;

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            allowlist,
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://campaign.example.com/metadata"
        );

        // Should return true for allowed ref codes
        assertTrue(adConversion.allowedPublishers(testCampaign, REF_CODE_1), "REF_CODE_1 should be allowed");
        assertTrue(adConversion.allowedPublishers(testCampaign, REF_CODE_2), "REF_CODE_2 should be allowed");
    }

    /// @dev Returns false for disallowed ref code when allowlist exists
    function test_allowedPublishers_disallowedCode() public {
        // Create campaign with allowlist
        string[] memory allowlist = new string[](1);
        allowlist[0] = REF_CODE_1;

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            allowlist,
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://campaign.example.com/metadata"
        );

        // Should return false for ref codes not in allowlist
        assertFalse(adConversion.allowedPublishers(testCampaign, REF_CODE_2), "REF_CODE_2 should not be allowed");
        assertFalse(adConversion.allowedPublishers(testCampaign, REF_CODE_3), "REF_CODE_3 should not be allowed");
        assertFalse(
            adConversion.allowedPublishers(testCampaign, "unregistered"), "Unregistered code should not be allowed"
        );
    }

    /// @dev Returns false for empty ref code when allowlist exists
    function test_allowedPublishers_emptyCode() public {
        // Create campaign with allowlist
        string[] memory allowlist = new string[](1);
        allowlist[0] = REF_CODE_1;

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            allowlist,
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://campaign.example.com/metadata"
        );

        // Should return false for empty ref code
        assertFalse(adConversion.allowedPublishers(testCampaign, ""), "Empty ref code should not be allowed");
    }

    /// @dev Returns false for any ref code when no allowlist exists
    function test_allowedPublishers_noAllowlist() public {
        // Create campaign without allowlist
        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            new string[](0), // Empty allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://campaign.example.com/metadata"
        );

        // Should return false for any ref code when no allowlist exists
        assertFalse(adConversion.allowedPublishers(testCampaign, REF_CODE_1), "Should return false when no allowlist");
        assertFalse(adConversion.allowedPublishers(testCampaign, REF_CODE_2), "Should return false when no allowlist");
        assertFalse(
            adConversion.allowedPublishers(testCampaign, ""), "Should return false for empty code when no allowlist"
        );
    }

    // ========================================
    // IS PUBLISHER REF CODE ALLOWED TESTING
    // ========================================

    /// @dev Returns true for any ref code when no allowlist exists
    /// @param anyRefCode Any publisher reference code
    function test_isPublisherRefCodeAllowed_noAllowlist(string memory anyRefCode) public {
        // Create campaign without allowlist
        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            new string[](0), // Empty allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://campaign.example.com/metadata"
        );

        // Should return true for any ref code when no allowlist exists
        assertTrue(
            adConversion.isPublisherRefCodeAllowed(testCampaign, anyRefCode),
            "Any ref code should be allowed when no allowlist"
        );
    }

    /// @dev Returns true for allowed ref code when allowlist exists
    function test_isPublisherRefCodeAllowed_allowedCode() public {
        // Create campaign with allowlist
        string[] memory allowlist = new string[](2);
        allowlist[0] = REF_CODE_1;
        allowlist[1] = REF_CODE_2;

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            allowlist,
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://campaign.example.com/metadata"
        );

        // Should return true for allowed ref codes
        assertTrue(adConversion.isPublisherRefCodeAllowed(testCampaign, REF_CODE_1), "REF_CODE_1 should be allowed");
        assertTrue(adConversion.isPublisherRefCodeAllowed(testCampaign, REF_CODE_2), "REF_CODE_2 should be allowed");
    }

    /// @dev Returns false for disallowed ref code when allowlist exists
    function test_isPublisherRefCodeAllowed_disallowedCode() public {
        // Create campaign with allowlist
        string[] memory allowlist = new string[](1);
        allowlist[0] = REF_CODE_1;

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            allowlist,
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://campaign.example.com/metadata"
        );

        // Should return false for ref codes not in allowlist
        assertFalse(
            adConversion.isPublisherRefCodeAllowed(testCampaign, REF_CODE_2), "REF_CODE_2 should not be allowed"
        );
        assertFalse(
            adConversion.isPublisherRefCodeAllowed(testCampaign, REF_CODE_3), "REF_CODE_3 should not be allowed"
        );
        assertFalse(
            adConversion.isPublisherRefCodeAllowed(testCampaign, "unregistered"),
            "Unregistered code should not be allowed"
        );
    }

    /// @dev Returns false for empty ref code when allowlist exists
    function test_isPublisherRefCodeAllowed_emptyCode() public {
        // Create campaign with allowlist
        string[] memory allowlist = new string[](1);
        allowlist[0] = REF_CODE_1;

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            allowlist,
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://campaign.example.com/metadata"
        );

        // Should return false for empty ref code
        assertFalse(adConversion.isPublisherRefCodeAllowed(testCampaign, ""), "Empty ref code should not be allowed");
    }

    // ========================================
    // EDGE CASES
    // ========================================

    /// @dev Handles disabled conversion config
    function test_getConversionConfig_edge_disabledConfig() public {
        // Create campaign with configs
        address testCampaign = createBasicCampaign();

        // Disable config 1 (which is the offchain config at configs[0])
        vm.prank(advertiser1);
        adConversion.disableConversionConfig(testCampaign, 1);

        // Should still be able to retrieve disabled config
        AdConversion.ConversionConfig memory disabledConfig = adConversion.getConversionConfig(testCampaign, 1);
        assertFalse(disabledConfig.isActive, "Disabled config should have isActive = false");

        // Other properties should remain intact (config 1 is offchain with offchain metadata)
        assertFalse(disabledConfig.isEventOnchain, "Onchain status should be preserved");
        assertEq(
            disabledConfig.metadataURI, "https://campaign.example.com/offchain-config", "Metadata should be preserved"
        );
    }

    /// @dev Handles maximum valid config ID
    function test_getConversionConfig_edge_maximumConfigId() public {
        // Create campaign with additional configs to test higher IDs
        AdConversion.ConversionConfigInput[] memory additionalConfigs = new AdConversion.ConversionConfigInput[](3);
        additionalConfigs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/config3"});
        additionalConfigs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config4"});
        additionalConfigs[2] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/config5"});

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createCombinedConfigs(additionalConfigs), // Use combined configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://example.com/default"
        );

        // Should be able to get the maximum valid config ID (5: 2 defaults + 3 additional)
        AdConversion.ConversionConfig memory maxConfig = adConversion.getConversionConfig(testCampaign, 5);
        assertTrue(maxConfig.isActive, "Max config should be active");
        assertTrue(maxConfig.isEventOnchain, "Max config should be onchain");
        assertEq(maxConfig.metadataURI, "https://example.com/config5", "Max config metadata should match");

        // Should revert for ID beyond maximum (6)
        vm.expectRevert(AdConversion.InvalidConversionConfigId.selector);
        adConversion.getConversionConfig(testCampaign, 6);
    }

    // ========================================
    // CONSISTENCY TESTING
    // ========================================

    /// @dev Verifies view functions return consistent data across multiple calls
    function test_viewFunctions_consistency() public {
        // Create campaign with allowlist and configs
        string[] memory allowlist = new string[](2);
        allowlist[0] = REF_CODE_1;
        allowlist[1] = REF_CODE_2;

        address testCampaign = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            allowlist,
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://consistent.example.com/metadata"
        );

        // Check consistency across multiple calls
        string memory expectedURI = "https://consistent.example.com/metadata";
        for (uint256 i = 0; i < 3; i++) {
            assertEq(adConversion.campaignURI(testCampaign), expectedURI, "URI should be consistent");
            assertTrue(adConversion.hasPublisherAllowlist(testCampaign), "Allowlist flag should be consistent");
            assertTrue(
                adConversion.isPublisherRefCodeAllowed(testCampaign, REF_CODE_1), "Allowed code should be consistent"
            );
            assertFalse(
                adConversion.isPublisherRefCodeAllowed(testCampaign, REF_CODE_3), "Disallowed code should be consistent"
            );
            assertEq(adConversion.conversionConfigCount(testCampaign), 2, "Config count should be consistent");
        }
    }

    /// @dev Verifies view functions work correctly with multiple campaigns
    function test_viewFunctions_multipleCampaigns() public {
        // Create two different campaigns
        string[] memory allowlist1 = new string[](1);
        allowlist1[0] = REF_CODE_1;

        string[] memory allowlist2 = new string[](1);
        allowlist2[0] = REF_CODE_2;

        address campaign1 = createCampaignWithURI(
            advertiser1,
            attributionProvider1,
            allowlist1,
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://campaign1.example.com"
        );

        address campaign2 = createCampaignWithURI(
            advertiser2,
            attributionProvider1,
            allowlist2,
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS,
            "https://campaign2.example.com"
        );

        // Verify each campaign has distinct state
        string memory expectedURI1 = "https://campaign1.example.com";
        string memory expectedURI2 = "https://campaign2.example.com";

        assertEq(adConversion.campaignURI(campaign1), expectedURI1, "Campaign1 URI should be distinct");
        assertEq(adConversion.campaignURI(campaign2), expectedURI2, "Campaign2 URI should be distinct");

        assertTrue(adConversion.isPublisherRefCodeAllowed(campaign1, REF_CODE_1), "Campaign1 should allow REF_CODE_1");
        assertFalse(
            adConversion.isPublisherRefCodeAllowed(campaign1, REF_CODE_2), "Campaign1 should not allow REF_CODE_2"
        );

        assertFalse(
            adConversion.isPublisherRefCodeAllowed(campaign2, REF_CODE_1), "Campaign2 should not allow REF_CODE_1"
        );
        assertTrue(adConversion.isPublisherRefCodeAllowed(campaign2, REF_CODE_2), "Campaign2 should allow REF_CODE_2");
    }
}
