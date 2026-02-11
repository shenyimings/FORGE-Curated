// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AdConversion} from "../../../../src/hooks/AdConversion.sol";
import {AdConversionTestBase} from "../../../lib/AdConversionTestBase.sol";

contract DisableConversionConfigTest is AdConversionTestBase {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when caller is not the advertiser
    /// @param unauthorizedCaller Unauthorized caller address (not advertiser)
    function test_revert_unauthorizedCaller(address unauthorizedCaller) public {
        vm.assume(unauthorizedCaller != advertiser1);

        // Create campaign with some configs
        address testCampaign = createBasicCampaign();

        // Should revert when called by unauthorized caller
        vm.prank(unauthorizedCaller);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        adConversion.disableConversionConfig(testCampaign, 1);
    }

    /// @dev Reverts when conversion config ID does not exist
    /// @param invalidConfigId Invalid conversion config ID
    function test_revert_configDoesNotExist(uint16 invalidConfigId) public {
        vm.assume(invalidConfigId > 2);

        // Create campaign with only 2 default configs
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(), // 2 default configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Verify we only have 2 configs (the defaults)
        assertEq(adConversion.conversionConfigCount(testCampaign), 2, "Should have 2 default configs");

        // Should revert when trying to disable non-existent config ID
        vm.prank(advertiser1);
        vm.expectRevert(AdConversion.InvalidConversionConfigId.selector);
        adConversion.disableConversionConfig(testCampaign, invalidConfigId);
    }

    /// @dev Reverts when trying to disable config ID 0 (reserved)
    function test_revert_configIdZero() public {
        // Create campaign with configs
        address testCampaign = createBasicCampaign();

        // Should revert when trying to disable config ID 0 (reserved)
        vm.prank(advertiser1);
        vm.expectRevert(AdConversion.InvalidConversionConfigId.selector);
        adConversion.disableConversionConfig(testCampaign, 0);
    }

    /// @dev Reverts when conversion config is already inactive
    function test_revert_configAlreadyInactive() public {
        // Create campaign with configs
        address testCampaign = createBasicCampaign();

        // First, disable config ID 1
        vm.prank(advertiser1);
        adConversion.disableConversionConfig(testCampaign, 1);

        // Verify config is now inactive
        AdConversion.ConversionConfig memory disabledConfig = adConversion.getConversionConfig(testCampaign, 1);
        assertFalse(disabledConfig.isActive, "Config should be inactive");

        // Should revert when trying to disable already inactive config
        vm.prank(advertiser1);
        vm.expectRevert(AdConversion.ConversionConfigDisabled.selector);
        adConversion.disableConversionConfig(testCampaign, 1);
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Successfully disables active conversion config
    function test_success_disableActiveConfig() public {
        // Create campaign with configs
        address testCampaign = createBasicCampaign();

        // Verify config 1 is initially active
        AdConversion.ConversionConfig memory initialConfig = adConversion.getConversionConfig(testCampaign, 1);
        assertTrue(initialConfig.isActive, "Config should initially be active");

        // Should succeed when disabling active config
        vm.prank(advertiser1);
        adConversion.disableConversionConfig(testCampaign, 1);

        // Verify config is now inactive
        AdConversion.ConversionConfig memory disabledConfig = adConversion.getConversionConfig(testCampaign, 1);
        assertFalse(disabledConfig.isActive, "Config should be inactive after disabling");

        // Verify other properties remain unchanged
        assertEq(disabledConfig.isEventOnchain, initialConfig.isEventOnchain, "Onchain status should remain unchanged");
        assertEq(disabledConfig.metadataURI, initialConfig.metadataURI, "Metadata URI should remain unchanged");
    }

    /// @dev Successfully disables multiple conversion configs
    function test_success_disableMultipleConfigs() public {
        // Create campaign with configs
        address testCampaign = createBasicCampaign();

        // Verify both configs are initially active
        AdConversion.ConversionConfig memory config1 = adConversion.getConversionConfig(testCampaign, 1);
        AdConversion.ConversionConfig memory config2 = adConversion.getConversionConfig(testCampaign, 2);
        assertTrue(config1.isActive, "Config 1 should initially be active");
        assertTrue(config2.isActive, "Config 2 should initially be active");

        vm.startPrank(advertiser1);

        // Disable both configs
        adConversion.disableConversionConfig(testCampaign, 1);
        adConversion.disableConversionConfig(testCampaign, 2);

        vm.stopPrank();

        // Verify both configs are now inactive
        AdConversion.ConversionConfig memory disabledConfig1 = adConversion.getConversionConfig(testCampaign, 1);
        AdConversion.ConversionConfig memory disabledConfig2 = adConversion.getConversionConfig(testCampaign, 2);
        assertFalse(disabledConfig1.isActive, "Config 1 should be inactive");
        assertFalse(disabledConfig2.isActive, "Config 2 should be inactive");
    }

    /// @dev Successfully disables onchain conversion config
    function test_success_disableOnchainConfig() public {
        // Create campaign with 2 default configs + 1 additional onchain config
        AdConversion.ConversionConfigInput[] memory defaultConfigs = _createDefaultConfigs();
        AdConversion.ConversionConfigInput[] memory allConfigs = new AdConversion.ConversionConfigInput[](3);
        allConfigs[0] = defaultConfigs[0];
        allConfigs[1] = defaultConfigs[1];
        allConfigs[2] = AdConversion.ConversionConfigInput({
            isEventOnchain: true, metadataURI: "https://example.com/onchain-config"
        });

        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            allConfigs,
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Verify we have 3 configs total (2 defaults + 1 additional)
        assertEq(adConversion.conversionConfigCount(testCampaign), 3, "Should have 3 configs");

        // Verify config 3 is onchain and active
        AdConversion.ConversionConfig memory onchainConfig = adConversion.getConversionConfig(testCampaign, 3);
        assertTrue(onchainConfig.isActive, "Onchain config should be active");
        assertTrue(onchainConfig.isEventOnchain, "Config should be onchain");

        // Disable the onchain config
        vm.prank(advertiser1);
        adConversion.disableConversionConfig(testCampaign, 3);

        // Verify onchain config is now inactive
        AdConversion.ConversionConfig memory disabledOnchainConfig = adConversion.getConversionConfig(testCampaign, 3);
        assertFalse(disabledOnchainConfig.isActive, "Onchain config should be inactive");
        assertTrue(disabledOnchainConfig.isEventOnchain, "Onchain status should remain unchanged");
    }

    /// @dev Successfully disables offchain conversion config
    function test_success_disableOffchainConfig() public {
        // Create campaign with 2 default configs + 1 additional offchain config
        AdConversion.ConversionConfigInput[] memory defaultConfigs = _createDefaultConfigs();
        AdConversion.ConversionConfigInput[] memory allConfigs = new AdConversion.ConversionConfigInput[](3);
        allConfigs[0] = defaultConfigs[0];
        allConfigs[1] = defaultConfigs[1];
        allConfigs[2] = AdConversion.ConversionConfigInput({
            isEventOnchain: false, metadataURI: "https://example.com/offchain-config"
        });

        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            allConfigs,
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Verify we have 3 configs total (2 defaults + 1 additional)
        assertEq(adConversion.conversionConfigCount(testCampaign), 3, "Should have 3 configs");

        // Verify config 3 is offchain and active
        AdConversion.ConversionConfig memory offchainConfig = adConversion.getConversionConfig(testCampaign, 3);
        assertTrue(offchainConfig.isActive, "Offchain config should be active");
        assertFalse(offchainConfig.isEventOnchain, "Config should be offchain");

        // Disable the offchain config
        vm.prank(advertiser1);
        adConversion.disableConversionConfig(testCampaign, 3);

        // Verify offchain config is now inactive
        AdConversion.ConversionConfig memory disabledOffchainConfig = adConversion.getConversionConfig(testCampaign, 3);
        assertFalse(disabledOffchainConfig.isActive, "Offchain config should be inactive");
        assertFalse(disabledOffchainConfig.isEventOnchain, "Offchain status should remain unchanged");
    }

    // ========================================
    // EDGE CASES
    // ========================================

    /// @dev Successfully disables last remaining active config
    function test_edge_disableLastActiveConfig() public {
        // Create campaign with configs
        address testCampaign = createBasicCampaign();

        // Disable config 1, leaving only config 2 active
        vm.prank(advertiser1);
        adConversion.disableConversionConfig(testCampaign, 1);

        // Verify config 1 is inactive and config 2 is still active
        AdConversion.ConversionConfig memory config1 = adConversion.getConversionConfig(testCampaign, 1);
        AdConversion.ConversionConfig memory config2 = adConversion.getConversionConfig(testCampaign, 2);
        assertFalse(config1.isActive, "Config 1 should be inactive");
        assertTrue(config2.isActive, "Config 2 should still be active");

        // Should succeed in disabling the last active config
        vm.prank(advertiser1);
        adConversion.disableConversionConfig(testCampaign, 2);

        // Verify all configs are now inactive
        AdConversion.ConversionConfig memory finalConfig2 = adConversion.getConversionConfig(testCampaign, 2);
        assertFalse(finalConfig2.isActive, "Config 2 should now be inactive");
    }

    // ========================================
    // EVENT TESTING
    // ========================================

    /// @dev Emits ConversionConfigStatusChanged event with correct parameters
    function test_emitsConversionConfigStatusChanged() public {
        // Create campaign with configs
        address testCampaign = createBasicCampaign();

        // Expect the ConversionConfigStatusChanged event
        vm.expectEmit(true, true, false, true);
        emit AdConversion.ConversionConfigStatusChanged(testCampaign, 1, false);

        // Disable config (should emit event)
        vm.prank(advertiser1);
        adConversion.disableConversionConfig(testCampaign, 1);
    }

    /// @dev Emits multiple events when disabling multiple configs
    function test_emitsMultipleEvents() public {
        // Create campaign with configs
        address testCampaign = createBasicCampaign();

        vm.startPrank(advertiser1);

        // Expect first event
        vm.expectEmit(true, true, false, true);
        emit AdConversion.ConversionConfigStatusChanged(testCampaign, 1, false);
        adConversion.disableConversionConfig(testCampaign, 1);

        // Expect second event
        vm.expectEmit(true, true, false, true);
        emit AdConversion.ConversionConfigStatusChanged(testCampaign, 2, false);
        adConversion.disableConversionConfig(testCampaign, 2);

        vm.stopPrank();
    }

    // ========================================
    // STATE VERIFICATION
    // ========================================

    /// @dev Verifies config count remains unchanged after disabling
    function test_configCountUnchangedAfterDisabling() public {
        // Create campaign with configs
        address testCampaign = createBasicCampaign();

        // Initial count should be 2
        uint16 initialCount = adConversion.conversionConfigCount(testCampaign);
        assertEq(initialCount, 2, "Should initially have 2 configs");

        // Disable a config
        vm.prank(advertiser1);
        adConversion.disableConversionConfig(testCampaign, 1);

        // Count should remain the same
        uint16 countAfterDisabling = adConversion.conversionConfigCount(testCampaign);
        assertEq(countAfterDisabling, initialCount, "Count should remain unchanged after disabling");
    }

    /// @dev Verifies only isActive status changes, other properties remain intact
    function test_onlyActiveStatusChanges() public {
        // Create campaign with configs
        address testCampaign = createBasicCampaign();

        // Get initial config state
        AdConversion.ConversionConfig memory initialConfig = adConversion.getConversionConfig(testCampaign, 1);
        assertTrue(initialConfig.isActive, "Config should initially be active");

        // Disable the config
        vm.prank(advertiser1);
        adConversion.disableConversionConfig(testCampaign, 1);

        // Get config state after disabling
        AdConversion.ConversionConfig memory disabledConfig = adConversion.getConversionConfig(testCampaign, 1);

        // Verify only isActive changed
        assertFalse(disabledConfig.isActive, "Config should be inactive after disabling");
        assertEq(disabledConfig.isEventOnchain, initialConfig.isEventOnchain, "Onchain status should be unchanged");
        assertEq(disabledConfig.metadataURI, initialConfig.metadataURI, "Metadata URI should be unchanged");
    }
}
