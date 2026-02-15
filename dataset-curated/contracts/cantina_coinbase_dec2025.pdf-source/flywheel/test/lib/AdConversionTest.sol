// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {FlywheelTest} from "./FlywheelTest.sol";

import {Flywheel} from "../../src/Flywheel.sol";
import {AdConversion} from "../../src/hooks/AdConversion.sol";

/// @notice Common test helpers for AdConversion hook testing
abstract contract AdConversionTest is FlywheelTest {
    AdConversion public hook;

    // Common event IDs for testing
    bytes16 public constant TEST_EVENT_ID_1 = bytes16(0x1234567890abcdef1234567890abcdef);
    bytes16 public constant TEST_EVENT_ID_2 = bytes16(0xabcdef1234567890abcdef1234567890);
    bytes16 public constant OFAC_EVENT_ID = bytes16(uint128(999));

    // Common test values
    string public constant TEST_CLICK_ID_1 = "click_123";
    string public constant TEST_CLICK_ID_2 = "click_456";
    string public constant OFAC_CLICK_ID = "ofac_sanctioned_funds";
    address public constant BURN_ADDRESS = address(0xdead);

    /// @notice Sets up complete AdConversion test environment with default registry
    function _setupAdConversionTest() internal {
        _setupFlywheelInfrastructure();
        _registerDefaultPublishers();

        // Deploy AdConversion hook
        hook = new AdConversion(address(flywheel), address(referralCodeRegistry));
    }

    /// @notice Sets up complete AdConversion test environment with custom registry
    function _setupAdConversionTest(address publisherRegistryAddress) internal {
        _setupFlywheelInfrastructure();
        _registerDefaultPublishers();

        // Deploy AdConversion hook
        hook = new AdConversion(address(flywheel), publisherRegistryAddress);
    }

    /// @notice Creates basic conversion configs for testing
    function _createBasicConversionConfigs() internal pure returns (AdConversion.ConversionConfigInput[] memory) {
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);

        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/offchain"});

        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/onchain"});

        return configs;
    }

    /// @notice Creates a campaign with basic conversion configs
    function _createBasicCampaign(uint256 nonce) internal returns (address) {
        return _createBasicCampaignWithDeadline(nonce, 7 days); // Use 7 days as standard default
    }

    /// @notice Creates a campaign with basic conversion configs and custom attribution deadline
    function _createBasicCampaignWithDeadline(uint256 nonce, uint48 attributionWindow) internal returns (address) {
        AdConversion.ConversionConfigInput[] memory configs = _createBasicConversionConfigs();
        string[] memory allowedRefCodes = new string[](0);

        bytes memory hookData = abi.encode(
            ATTRIBUTION_PROVIDER,
            ADVERTISER,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            attributionWindow,
            uint16(500) // 5% default attribution provider fee
        );

        return flywheel.createCampaign(address(hook), nonce, hookData);
    }

    /// @notice Creates a campaign with allowlist enabled
    function _createCampaignWithAllowlist(uint256 nonce, string[] memory allowedRefCodes) internal returns (address) {
        return _createCampaignWithAllowlistAndDeadline(nonce, allowedRefCodes, 7 days); // Use 7 days as standard default
    }

    /// @notice Creates a campaign with allowlist enabled and custom attribution deadline
    function _createCampaignWithAllowlistAndDeadline(
        uint256 nonce,
        string[] memory allowedRefCodes,
        uint48 attributionWindow
    ) internal returns (address) {
        AdConversion.ConversionConfigInput[] memory configs = _createBasicConversionConfigs();

        bytes memory hookData = abi.encode(
            ATTRIBUTION_PROVIDER,
            ADVERTISER,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            attributionWindow,
            uint16(500) // 5% default attribution provider fee
        );

        return flywheel.createCampaign(address(hook), nonce, hookData);
    }

    /// @notice Creates a basic campaign with custom attribution provider fee
    function _createBasicCampaignWithFee(uint256 nonce, uint16 attributionProviderFeeBps) internal returns (address) {
        AdConversion.ConversionConfigInput[] memory configs = _createBasicConversionConfigs();
        string[] memory allowedRefCodes = new string[](0);

        bytes memory hookData = abi.encode(
            ATTRIBUTION_PROVIDER,
            ADVERTISER,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            uint48(7 days), // Default attribution window
            attributionProviderFeeBps
        );

        return flywheel.createCampaign(address(hook), nonce, hookData);
    }

    /// @notice Creates an offchain attribution with default values
    function _createOffchainAttribution(string memory publisherRefCode, uint256 payoutAmount, address payoutRecipient)
        internal
        view
        returns (AdConversion.Attribution[] memory)
    {
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);

        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: TEST_EVENT_ID_1,
                clickId: TEST_CLICK_ID_1,
                configId: 1, // Offchain config
                publisherRefCode: publisherRefCode,
                timestamp: uint32(block.timestamp),
                payoutRecipient: payoutRecipient,
                payoutAmount: payoutAmount
            }),
            logBytes: "" // Empty for offchain
        });

        return attributions;
    }

    /// @notice Creates an onchain attribution with default values
    function _createOnchainAttribution(string memory publisherRefCode, uint256 payoutAmount, address payoutRecipient)
        internal
        view
        returns (AdConversion.Attribution[] memory)
    {
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);

        AdConversion.Log memory log =
            AdConversion.Log({chainId: block.chainid, transactionHash: keccak256("test_transaction"), index: 0});

        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: TEST_EVENT_ID_2,
                clickId: TEST_CLICK_ID_2,
                configId: 2, // Onchain config
                publisherRefCode: publisherRefCode,
                timestamp: uint32(block.timestamp),
                payoutRecipient: payoutRecipient,
                payoutAmount: payoutAmount
            }),
            logBytes: abi.encode(log)
        });

        return attributions;
    }

    /// @notice Creates OFAC funds re-routing attribution
    function _createOfacReroutingAttribution(uint256 amount) internal view returns (AdConversion.Attribution[] memory) {
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);

        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: OFAC_EVENT_ID,
                clickId: OFAC_CLICK_ID,
                configId: 0, // No config - unregistered conversion
                publisherRefCode: "", // No publisher
                timestamp: uint32(block.timestamp),
                payoutRecipient: BURN_ADDRESS,
                payoutAmount: amount
            }),
            logBytes: "" // Offchain event
        });

        return attributions;
    }

    /// @notice Processes attribution through Flywheel reward function
    function _processAttributionThroughFlywheel(address campaign, AdConversion.Attribution[] memory attributions)
        internal
    {
        bytes memory attributionData = abi.encode(attributions);

        vm.prank(ATTRIBUTION_PROVIDER);
        flywheel.send(campaign, address(token), attributionData);
    }

    /// @notice Adds publisher to campaign allowlist
    function _addPublisherToAllowlist(address campaign, string memory refCode, address caller) internal {
        vm.prank(caller);
        hook.addAllowedPublisherRefCode(campaign, refCode);
    }

    /// @notice Asserts conversion config properties
    function _assertConversionConfig(
        address campaign,
        uint256 configId,
        bool expectedIsActive,
        bool expectedIsEventOnchain,
        string memory expectedMetadataUrl
    ) internal view {
        AdConversion.ConversionConfig memory config = hook.getConversionConfig(campaign, uint16(configId));

        assertEq(config.isActive, expectedIsActive);
        assertEq(config.isEventOnchain, expectedIsEventOnchain);
        assertEq(config.metadataURI, expectedMetadataUrl);
    }

    /// @notice Asserts publisher is allowed in campaign
    function _assertPublisherAllowed(address campaign, string memory refCode, bool expected) internal view {
        assertEq(hook.isPublisherRefCodeAllowed(campaign, refCode), expected);
    }

    /// @notice Runs complete offchain attribution test
    function _runOffchainAttributionTest(
        address campaign,
        string memory publisherRefCode,
        uint256 payoutAmount,
        uint16 feeBps
    ) internal {
        // Setup
        _fundCampaign(campaign, INITIAL_TOKEN_BALANCE);
        _activateCampaign(campaign);

        // Create and process attribution
        AdConversion.Attribution[] memory attributions =
            _createOffchainAttribution(publisherRefCode, payoutAmount, address(0));

        _processAttributionThroughFlywheel(campaign, attributions);

        // Calculate expected values
        uint256 expectedFee = _calculateFee(payoutAmount, feeBps);
        uint256 expectedPayout = payoutAmount - expectedFee;

        // Get payout recipient (publisher payout address or payoutRecipient)
        address expectedRecipient;
        if (bytes(publisherRefCode).length != 0) {
            if (keccak256(bytes(publisherRefCode)) == keccak256(bytes(DEFAULT_REF_CODE_1))) {
                expectedRecipient = PUBLISHER_1_PAYOUT;
            } else if (keccak256(bytes(publisherRefCode)) == keccak256(bytes(DEFAULT_REF_CODE_2))) {
                expectedRecipient = PUBLISHER_2_PAYOUT;
            }
        }

        // Verify results
        if (expectedRecipient != address(0)) _assertTokenBalance(expectedRecipient, expectedPayout);
        _assertFeeAllocation(campaign, ATTRIBUTION_PROVIDER, expectedFee);
    }

    /// @notice Runs complete onchain attribution test
    function _runOnchainAttributionTest(
        address campaign,
        string memory publisherRefCode,
        uint256 payoutAmount,
        uint16 feeBps
    ) internal {
        // Setup
        _fundCampaign(campaign, INITIAL_TOKEN_BALANCE);
        _activateCampaign(campaign);

        // Create and process attribution
        AdConversion.Attribution[] memory attributions =
            _createOnchainAttribution(publisherRefCode, payoutAmount, address(0));

        _processAttributionThroughFlywheel(campaign, attributions);

        // Calculate expected values
        uint256 expectedFee = _calculateFee(payoutAmount, feeBps);
        uint256 expectedPayout = payoutAmount - expectedFee;

        // Get payout recipient
        address expectedRecipient;
        if (bytes(publisherRefCode).length != 0) {
            if (keccak256(bytes(publisherRefCode)) == keccak256(bytes(DEFAULT_REF_CODE_1))) {
                expectedRecipient = PUBLISHER_1_PAYOUT;
            } else if (keccak256(bytes(publisherRefCode)) == keccak256(bytes(DEFAULT_REF_CODE_2))) {
                expectedRecipient = PUBLISHER_2_PAYOUT;
            }
        }

        // Verify results
        if (expectedRecipient != address(0)) _assertTokenBalance(expectedRecipient, expectedPayout);
        _assertFeeAllocation(campaign, ATTRIBUTION_PROVIDER, expectedFee);
    }

    /// @notice Runs OFAC re-routing test scenario
    function _runOfacReroutingTest(address campaign, uint256 amount) internal {
        // Setup - no fee for burn transaction
        _fundCampaign(campaign, amount);
        _activateCampaign(campaign);

        // Create and process OFAC rerouting attribution
        AdConversion.Attribution[] memory attributions = _createOfacReroutingAttribution(amount);

        // Expect event emission
        vm.expectEmit(true, false, false, true);
        emit AdConversion.OffchainConversionProcessed(campaign, true, attributions[0].conversion);

        _processAttributionThroughFlywheel(campaign, attributions);

        // Verify funds were sent to burn address
        _assertTokenBalance(BURN_ADDRESS, amount);
        _assertFeeAllocation(campaign, ATTRIBUTION_PROVIDER, 0);
    }
}
