// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AdConversion} from "../../../../src/hooks/AdConversion.sol";
import {AdConversionTestBase} from "../../../lib/AdConversionTestBase.sol";

contract AddConversionConfigTest is AdConversionTestBase {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when caller is not the advertiser
    /// @param unauthorizedCaller Unauthorized caller address (not advertiser)
    function test_revert_unauthorizedCaller(address unauthorizedCaller) public {
        vm.assume(unauthorizedCaller != advertiser1);

        // Create campaign with no default configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            emptyConfigs, // No default configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Create config input
        AdConversion.ConversionConfigInput memory configInput =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/config"});

        // Should revert when called by unauthorized caller
        vm.prank(unauthorizedCaller);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        adConversion.addConversionConfig(testCampaign, configInput);
    }

    /// @dev Reverts when conversion config count exceeds maximum limit
    function test_revert_exceedsMaximumConfigs() public {
        // Create campaign with no default configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            emptyConfigs, // No default configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Use Foundry cheatcode to set the conversion config count to maximum
        // The conversionConfigCount mapping is at storage slot 3 in the AdConversion contract
        // For a mapping, the storage location is keccak256(abi.encode(key, slot))
        bytes32 storageSlot = keccak256(abi.encode(testCampaign, uint256(3)));

        // Set the count to type(uint16).max (65535)
        vm.store(address(adConversion), storageSlot, bytes32(uint256(type(uint16).max)));

        // Verify the count was set correctly
        assertEq(adConversion.conversionConfigCount(testCampaign), type(uint16).max, "Should have maximum configs");

        // Create config input
        AdConversion.ConversionConfigInput memory configInput =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/max-config"});

        // Should revert when trying to add one more config beyond the maximum
        vm.prank(advertiser1);
        vm.expectRevert(AdConversion.TooManyConversionConfigs.selector);
        adConversion.addConversionConfig(testCampaign, configInput);
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Successfully adds onchain conversion config
    /// @param metadataURI Config metadata URI
    function test_success_onchainConfig(string memory metadataURI) public {
        // Create campaign with no default configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            emptyConfigs, // No default configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Create onchain config input
        AdConversion.ConversionConfigInput memory configInput =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: metadataURI});

        // Should succeed when adding onchain config
        vm.prank(advertiser1);
        adConversion.addConversionConfig(testCampaign, configInput);

        // Verify config was added
        assertEq(adConversion.conversionConfigCount(testCampaign), 1, "Should have 1 config");

        // Verify config details
        AdConversion.ConversionConfig memory storedConfig = adConversion.getConversionConfig(testCampaign, 1);
        assertTrue(storedConfig.isActive, "Config should be active");
        assertTrue(storedConfig.isEventOnchain, "Config should be onchain");
        assertEq(storedConfig.metadataURI, metadataURI, "Metadata URI should match");
    }

    /// @dev Successfully adds offchain conversion config
    /// @param metadataURI Config metadata URI
    function test_success_offchainConfig(string memory metadataURI) public {
        // Create campaign with no default configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            emptyConfigs, // No default configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Create offchain config input
        AdConversion.ConversionConfigInput memory configInput =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: metadataURI});

        // Should succeed when adding offchain config
        vm.prank(advertiser1);
        adConversion.addConversionConfig(testCampaign, configInput);

        // Verify config was added
        assertEq(adConversion.conversionConfigCount(testCampaign), 1, "Should have 1 config");

        // Verify config details
        AdConversion.ConversionConfig memory storedConfig = adConversion.getConversionConfig(testCampaign, 1);
        assertTrue(storedConfig.isActive, "Config should be active");
        assertFalse(storedConfig.isEventOnchain, "Config should be offchain");
        assertEq(storedConfig.metadataURI, metadataURI, "Metadata URI should match");
    }

    /// @dev Successfully adds multiple conversion configs to same campaign
    function test_success_multipleConfigs() public {
        // Create campaign with no default configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            emptyConfigs, // No default configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Create first config input
        AdConversion.ConversionConfigInput memory config1 =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/config1"});

        // Create second config input
        AdConversion.ConversionConfigInput memory config2 =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config2"});

        vm.startPrank(advertiser1);

        // Add first config
        adConversion.addConversionConfig(testCampaign, config1);
        assertEq(adConversion.conversionConfigCount(testCampaign), 1, "Should have 1 config");

        // Add second config
        adConversion.addConversionConfig(testCampaign, config2);
        assertEq(adConversion.conversionConfigCount(testCampaign), 2, "Should have 2 configs");

        vm.stopPrank();

        // Verify both configs
        AdConversion.ConversionConfig memory storedConfig1 = adConversion.getConversionConfig(testCampaign, 1);
        AdConversion.ConversionConfig memory storedConfig2 = adConversion.getConversionConfig(testCampaign, 2);

        assertTrue(storedConfig1.isActive, "Config 1 should be active");
        assertTrue(storedConfig1.isEventOnchain, "Config 1 should be onchain");
        assertEq(storedConfig1.metadataURI, "https://example.com/config1", "Config 1 metadata should match");

        assertTrue(storedConfig2.isActive, "Config 2 should be active");
        assertFalse(storedConfig2.isEventOnchain, "Config 2 should be offchain");
        assertEq(storedConfig2.metadataURI, "https://example.com/config2", "Config 2 metadata should match");
    }

    /// @dev Successfully adds config with empty metadata URI
    /// @param isOnchain Whether config is onchain or offchain
    function test_success_emptyMetadataURI(bool isOnchain) public {
        // Create campaign with no default configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            emptyConfigs, // No default configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Create config input with empty metadata URI
        AdConversion.ConversionConfigInput memory configInput =
            AdConversion.ConversionConfigInput({isEventOnchain: isOnchain, metadataURI: ""});

        // Should succeed when adding config with empty metadata URI
        vm.prank(advertiser1);
        adConversion.addConversionConfig(testCampaign, configInput);

        // Verify config was added
        assertEq(adConversion.conversionConfigCount(testCampaign), 1, "Should have 1 config");

        // Verify config details
        AdConversion.ConversionConfig memory storedConfig = adConversion.getConversionConfig(testCampaign, 1);
        assertTrue(storedConfig.isActive, "Config should be active");
        assertEq(storedConfig.isEventOnchain, isOnchain, "Config type should match");
        assertEq(storedConfig.metadataURI, "", "Metadata URI should be empty");
    }

    // ========================================
    // EDGE CASES
    // ========================================

    /// @dev Handles adding config with very long metadata URI
    /// @param isOnchain Whether config is onchain or offchain
    function test_edge_longMetadataURI(bool isOnchain) public {
        // Create campaign with no default configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            emptyConfigs, // No default configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Create very long metadata URI
        string memory longMetadataURI =
            "https://example.com/very/long/path/with/many/segments/that/goes/on/and/on/and/on/with/lots/of/characters/to/test/string/handling/capabilities/of/the/contract/implementation/metadata.json";

        // Create config input with long metadata URI
        AdConversion.ConversionConfigInput memory configInput =
            AdConversion.ConversionConfigInput({isEventOnchain: isOnchain, metadataURI: longMetadataURI});

        // Should succeed when adding config with long metadata URI
        vm.prank(advertiser1);
        adConversion.addConversionConfig(testCampaign, configInput);

        // Verify config was added
        assertEq(adConversion.conversionConfigCount(testCampaign), 1, "Should have 1 config");

        // Verify config details
        AdConversion.ConversionConfig memory storedConfig = adConversion.getConversionConfig(testCampaign, 1);
        assertTrue(storedConfig.isActive, "Config should be active");
        assertEq(storedConfig.isEventOnchain, isOnchain, "Config type should match");
        assertEq(storedConfig.metadataURI, longMetadataURI, "Long metadata URI should match");
    }

    /// @dev Handles adding configs with identical metadata URIs (should be allowed)
    /// @param sameMetadataURI Same config metadata URI for both configs
    function test_edge_identicalMetadataURI(string memory sameMetadataURI) public {
        // Create campaign with no default configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            emptyConfigs, // No default configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Create two config inputs with same metadata URI but different types
        AdConversion.ConversionConfigInput memory config1 =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: sameMetadataURI});

        AdConversion.ConversionConfigInput memory config2 =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: sameMetadataURI});

        vm.startPrank(advertiser1);

        // Should succeed when adding configs with identical metadata URIs
        adConversion.addConversionConfig(testCampaign, config1);
        adConversion.addConversionConfig(testCampaign, config2);

        vm.stopPrank();

        // Verify both configs were added with same metadata URI
        assertEq(adConversion.conversionConfigCount(testCampaign), 2, "Should have 2 configs");

        AdConversion.ConversionConfig memory storedConfig1 = adConversion.getConversionConfig(testCampaign, 1);
        AdConversion.ConversionConfig memory storedConfig2 = adConversion.getConversionConfig(testCampaign, 2);

        assertEq(storedConfig1.metadataURI, sameMetadataURI, "Config 1 metadata should match");
        assertEq(storedConfig2.metadataURI, sameMetadataURI, "Config 2 metadata should match");
        assertTrue(storedConfig1.isEventOnchain, "Config 1 should be onchain");
        assertFalse(storedConfig2.isEventOnchain, "Config 2 should be offchain");
    }

    // ========================================
    // CONFIG ID TESTING
    // ========================================

    /// @dev Verifies config IDs are assigned sequentially starting from 1
    function test_assignsSequentialIds() public {
        // Create campaign with no default configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            emptyConfigs, // No default configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        vm.startPrank(advertiser1);

        // Add multiple configs
        for (uint256 i = 1; i <= 5; i++) {
            AdConversion.ConversionConfigInput memory configInput = AdConversion.ConversionConfigInput({
                isEventOnchain: i % 2 == 0,
                metadataURI: string(abi.encodePacked("https://example.com/config", vm.toString(i)))
            });
            adConversion.addConversionConfig(testCampaign, configInput);
        }

        vm.stopPrank();

        // Verify sequential IDs starting from 1
        assertEq(adConversion.conversionConfigCount(testCampaign), 5, "Should have 5 configs");

        for (uint256 i = 1; i <= 5; i++) {
            AdConversion.ConversionConfig memory storedConfig =
                adConversion.getConversionConfig(testCampaign, uint16(i));
            assertTrue(storedConfig.isActive, "All configs should be active");
            assertEq(
                storedConfig.metadataURI,
                string(abi.encodePacked("https://example.com/config", vm.toString(i))),
                "Metadata should match sequence"
            );
        }
    }

    /// @dev Verifies config ID 0 is reserved (never assigned)
    function test_addConversionConfig_reservesIdZero() public {
        // Create campaign with no default configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            emptyConfigs, // No default configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Create config input
        AdConversion.ConversionConfigInput memory configInput =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/first-config"});

        // Add first config
        vm.prank(advertiser1);
        adConversion.addConversionConfig(testCampaign, configInput);

        // Verify first config gets ID 1 (not 0)
        assertEq(adConversion.conversionConfigCount(testCampaign), 1, "Should have 1 config");

        // Verify config exists at ID 1
        AdConversion.ConversionConfig memory storedConfig = adConversion.getConversionConfig(testCampaign, 1);
        assertTrue(storedConfig.isActive, "Config should be active");
        assertEq(storedConfig.metadataURI, "https://example.com/first-config", "Metadata should match");

        // Verify ID 0 would revert (reserved/invalid)
        vm.expectRevert();
        adConversion.getConversionConfig(testCampaign, 0);
    }

    // ========================================
    // EVENT TESTING
    // ========================================

    /// @dev Emits ConversionConfigAdded event with correct parameters
    /// @param metadataURI Config metadata URI
    /// @param isOnchain Whether config is onchain
    function test_addConversionConfig_emitsConversionConfigAdded(string memory metadataURI, bool isOnchain) public {
        // Create campaign with no default configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            emptyConfigs, // No default configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Create config input
        AdConversion.ConversionConfigInput memory configInput =
            AdConversion.ConversionConfigInput({isEventOnchain: isOnchain, metadataURI: metadataURI});

        // Create expected config output
        AdConversion.ConversionConfig memory expectedConfig =
            AdConversion.ConversionConfig({isActive: true, isEventOnchain: isOnchain, metadataURI: metadataURI});

        // Expect the ConversionConfigAdded event
        vm.expectEmit(true, true, false, true);
        emit AdConversion.ConversionConfigAdded(testCampaign, 1, expectedConfig);

        // Add config (should emit event)
        vm.prank(advertiser1);
        adConversion.addConversionConfig(testCampaign, configInput);
    }

    // ========================================
    // STATE VERIFICATION
    // ========================================

    /// @dev Verifies config count is correctly incremented
    function test_addConversionConfig_incrementsConfigCount() public {
        // Create campaign with no default configs
        AdConversion.ConversionConfigInput[] memory emptyConfigs = new AdConversion.ConversionConfigInput[](0);
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            emptyConfigs, // No default configs
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );

        // Initial count should be 0
        assertEq(adConversion.conversionConfigCount(testCampaign), 0, "Initial count should be 0");

        vm.startPrank(advertiser1);

        // Add configs and verify count increments
        for (uint256 i = 1; i <= 3; i++) {
            AdConversion.ConversionConfigInput memory configInput = AdConversion.ConversionConfigInput({
                isEventOnchain: i % 2 == 0,
                metadataURI: string(abi.encodePacked("https://example.com/config", vm.toString(i)))
            });

            adConversion.addConversionConfig(testCampaign, configInput);
            assertEq(
                adConversion.conversionConfigCount(testCampaign),
                i,
                string(abi.encodePacked("Count should be ", vm.toString(i)))
            );
        }

        vm.stopPrank();
    }
}
