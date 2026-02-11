// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Flywheel} from "../src/Flywheel.sol";
import {BuilderCodes} from "../src/BuilderCodes.sol";
import {AdConversion} from "../src/hooks/AdConversion.sol";
import {DummyERC20} from "./mocks/DummyERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PublisherTestSetup, PublisherSetupHelper} from "./helpers/PublisherSetupHelper.sol";

contract AdConversionTest is PublisherTestSetup {
    Flywheel public flywheel;
    BuilderCodes public publisherRegistry;
    AdConversion public hook;
    DummyERC20 public token;

    address public owner = address(0x1);
    address public advertiser = address(0x2);
    address public attributionProvider = address(0x3);
    address public randomUser = address(0x4);

    address public campaign;

    function setUp() public {
        // Deploy contracts
        flywheel = new Flywheel();

        // Deploy BuilderCodes as upgradeable proxy
        BuilderCodes implementation = new BuilderCodes();
        bytes memory initData = abi.encodeWithSelector(
            BuilderCodes.initialize.selector,
            owner,
            address(0x999), // signer address
            "" // empty baseURI
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        publisherRegistry = BuilderCodes(address(proxy));

        hook = new AdConversion(address(flywheel), owner, address(publisherRegistry));

        // Deploy token with initial holders
        address[] memory initialHolders = new address[](1);
        initialHolders[0] = address(this);
        token = new DummyERC20(initialHolders);

        // Register randomUser as a publisher with ref code
        vm.prank(owner);
        publisherRegistry.register("random", randomUser, randomUser);

        // Create a campaign with conversion configs
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/config0"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config1"});

        string[] memory allowedRefCodes = new string[](0);

        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(500)
        );

        campaign = flywheel.createCampaign(address(hook), 1, hookData);
    }

    function test_onReward_valid_onchainConversion() public {
        vm.prank(owner);
        publisherRegistry.register("code1", randomUser, randomUser);

        // Create new campaign with 5% attribution provider fee
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/config0"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config1"});
        string[] memory allowedRefCodes = new string[](0);
        bytes memory campaignHookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(500)
        );
        address testCampaign = flywheel.createCampaign(address(hook), 1001, campaignHookData);

        // Create attribution with logBytes for ONCHAIN config
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 1, // ONCHAIN config (1-indexed)
                publisherRefCode: "code1",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: abi.encode(AdConversion.Log({chainId: block.chainid, transactionHash: bytes32(uint256(1)), index: 0}))
        });

        bytes memory hookData = abi.encode(attributions);

        // Call onReward through flywheel
        vm.prank(address(flywheel));
        (
            Flywheel.Payout[] memory payouts,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        ) = hook.onSend(attributionProvider, testCampaign, address(token), hookData);

        // Verify results
        assertEq(payouts.length, 1);
        assertEq(payouts[0].recipient, randomUser);
        assertEq(payouts[0].amount, 95 ether); // 100 - 5% fee
        assertEq(immediateFees.length, 0);
        assertEq(delayedFees.length, 1);
        assertEq(delayedFees[0].key, bytes32(bytes20(attributionProvider)));
        assertEq(delayedFees[0].amount, 5 ether);
        assertEq(keccak256(delayedFees[0].extraData), keccak256(""));
    }

    function test_onReward_valid_offchainConversion() public {
        vm.prank(owner);
        publisherRegistry.register("code1", randomUser, randomUser);

        // Create new campaign with 5% attribution provider fee
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/config0"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config1"});
        string[] memory allowedRefCodes = new string[](0);
        bytes memory campaignHookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(500)
        );
        address testCampaign = flywheel.createCampaign(address(hook), 1002, campaignHookData);

        // Create attribution without logBytes for OFFCHAIN config
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 2, // OFFCHAIN config (1-indexed)
                publisherRefCode: "code1",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: "" // Empty for offchain
        });

        bytes memory hookData = abi.encode(attributions);

        // Call onReward through flywheel
        vm.prank(address(flywheel));
        (
            Flywheel.Payout[] memory payouts,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        ) = hook.onSend(attributionProvider, testCampaign, address(token), hookData);

        // Verify results
        assertEq(payouts.length, 1);
        assertEq(payouts[0].recipient, randomUser);
        assertEq(payouts[0].amount, 95 ether); // 100 - 5% fee
        assertEq(immediateFees.length, 0);
        assertEq(delayedFees.length, 1);
        assertEq(delayedFees[0].key, bytes32(bytes20(attributionProvider)));
        assertEq(delayedFees[0].amount, 5 ether);
        assertEq(keccak256(delayedFees[0].extraData), keccak256(""));
    }

    function test_onReward_revert_onchainConversionWithoutLogBytes() public {
        // Create attribution without logBytes for ONCHAIN config (invalid)
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 1, // ONCHAIN config (1-indexed)
                publisherRefCode: "",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: "" // Empty logBytes for ONCHAIN is invalid
        });

        bytes memory hookData = abi.encode(attributions);

        // Expect revert
        vm.expectRevert(AdConversion.InvalidConversionType.selector);
        vm.prank(address(flywheel));
        hook.onSend(attributionProvider, campaign, address(token), hookData);
    }

    function test_onReward_revert_offchainConversionWithLogBytes() public {
        // Create attribution with logBytes for OFFCHAIN config (invalid)
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 2, // OFFCHAIN config (1-indexed)
                publisherRefCode: "",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: abi.encode(AdConversion.Log({chainId: block.chainid, transactionHash: bytes32(uint256(1)), index: 0})) // logBytes for OFFCHAIN is invalid
        });

        bytes memory hookData = abi.encode(attributions);

        // Expect revert
        vm.expectRevert(AdConversion.InvalidConversionType.selector);
        vm.prank(address(flywheel));
        hook.onSend(attributionProvider, campaign, address(token), hookData);
    }

    function test_onReward_ofacFundsRerouting() public {
        // Simulate OFAC-sanctioned address
        address ofacAddress = address(0xBAD);
        address burnAddress = address(0xdead);

        // Create a special campaign with 0% fee for burn transactions
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/ofac"});
        string[] memory allowedRefCodes = new string[](0);
        bytes memory campaignHookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/ofac-campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(0)
        );
        address ofacCampaign = flywheel.createCampaign(address(hook), 999, campaignHookData);

        // Give OFAC address some tokens
        token.transfer(ofacAddress, 1000 ether);

        // OFAC address adds funds to campaign by transferring directly
        vm.prank(ofacAddress);
        token.transfer(ofacCampaign, 1000 ether);

        // Attribution provider re-routes the sanctioned funds to burn address
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(999)), // Unique ID for OFAC re-routing
                clickId: "ofac_sanctioned_funds",
                configId: 0, // No config - unregistered conversion
                publisherRefCode: "", // No publisher
                timestamp: uint32(block.timestamp),
                payoutRecipient: burnAddress, // Send to burn address
                payoutAmount: 1000 ether // Full amount
            }),
            logBytes: "" // Offchain event
        });

        bytes memory hookData = abi.encode(attributions);

        // Expect the event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AdConversion.OffchainConversionProcessed(
            ofacCampaign,
            false, // isPublisherPayout - false since funds go to burn address, not publisher
            AdConversion.Conversion({
                eventId: bytes16(uint128(999)),
                clickId: "ofac_sanctioned_funds",
                configId: 0,
                publisherRefCode: "",
                timestamp: uint32(block.timestamp),
                payoutRecipient: burnAddress,
                payoutAmount: 1000 ether
            })
        );

        // Call onReward through flywheel
        vm.prank(address(flywheel));
        (
            Flywheel.Payout[] memory payouts,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        ) = hook.onSend(attributionProvider, ofacCampaign, address(token), hookData);

        // Verify results
        assertEq(payouts.length, 1);
        assertEq(payouts[0].recipient, burnAddress);
        assertEq(payouts[0].amount, 1000 ether); // Full amount sent to burn
        assertEq(immediateFees.length, 0); // no fees
        assertEq(delayedFees.length, 0); // no fees
    }

    function test_createCampaign_emitsConversionConfigAddedEvents() public {
        // Create conversion configs
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/config0"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config1"});

        string[] memory allowedRefCodes = new string[](0);

        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(500)
        );

        // Calculate expected campaign address
        address expectedCampaign = flywheel.predictCampaignAddress(address(hook), 2, hookData);

        // Expect events for each config (with isActive: true added automatically)
        vm.expectEmit(true, true, false, true);
        emit AdConversion.ConversionConfigAdded(
            expectedCampaign,
            1,
            AdConversion.ConversionConfig({
                isActive: true,
                isEventOnchain: true,
                metadataURI: "https://example.com/config0"
            })
        );

        vm.expectEmit(true, true, false, true);
        emit AdConversion.ConversionConfigAdded(
            expectedCampaign,
            2,
            AdConversion.ConversionConfig({
                isActive: true,
                isEventOnchain: false,
                metadataURI: "https://example.com/config1"
            })
        );

        // Create campaign
        address newCampaign = flywheel.createCampaign(address(hook), 2, hookData);

        assertEq(newCampaign, expectedCampaign);
    }

    function test_createCampaign_emitsPublisherAddedToAllowlistEvents() public {
        // Register additional publishers
        vm.startPrank(owner);
        publisherRegistry.register("code1", address(0x1001), address(0x1001));
        publisherRegistry.register("code2", address(0x1002), address(0x1002));
        publisherRegistry.register("code3", address(0x1003), address(0x1003));
        vm.stopPrank();

        // Create empty conversion configs
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](0);

        // Create allowlist
        string[] memory allowedRefCodes = new string[](3);
        allowedRefCodes[0] = "code1";
        allowedRefCodes[1] = "code2";
        allowedRefCodes[2] = "code3";

        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(500)
        );

        // Calculate expected campaign address
        address expectedCampaign = flywheel.predictCampaignAddress(address(hook), 3, hookData);

        // Expect events for each publisher
        vm.expectEmit(true, false, false, true);
        emit AdConversion.PublisherAddedToAllowlist(expectedCampaign, "code1");

        vm.expectEmit(true, false, false, true);
        emit AdConversion.PublisherAddedToAllowlist(expectedCampaign, "code2");

        vm.expectEmit(true, false, false, true);
        emit AdConversion.PublisherAddedToAllowlist(expectedCampaign, "code3");

        // Create campaign
        address newCampaign = flywheel.createCampaign(address(hook), 3, hookData);

        assertEq(newCampaign, expectedCampaign);
    }

    function test_createCampaign_emitsAdCampaignCreatedEvent() public {
        // Register the ref code first
        vm.prank(owner);
        publisherRegistry.register("code1", address(0x1001), address(0x1001));

        // Create conversion configs
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/config"});

        // Create allowlist
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = "code1";

        uint48 attributionDeadline = 7 days;
        string memory uri = "https://example.com/new-campaign";

        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, uri, allowedRefCodes, configs, attributionDeadline, uint16(1000)
        );

        // Calculate expected campaign address
        address expectedCampaign = flywheel.predictCampaignAddress(address(hook), 4, hookData);

        // Expect the campaign creation event
        vm.expectEmit(true, false, false, true);
        emit AdConversion.AdCampaignCreated(expectedCampaign, attributionProvider, advertiser, uri, attributionDeadline);

        // Create campaign
        address newCampaign = flywheel.createCampaign(address(hook), 4, hookData);

        assertEq(newCampaign, expectedCampaign);
    }

    function test_addAllowedPublisherRefCode_emitsEvent() public {
        // Register the ref code before creating campaign
        vm.prank(owner);
        publisherRegistry.register("test_ref_code", address(0x5001), address(0x5001));

        // First create a campaign with allowlist enabled
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](0);
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = "test_ref_code";

        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(500)
        );

        address allowlistCampaign = flywheel.createCampaign(address(hook), 4, hookData);

        // Register a new publisher
        vm.prank(owner);
        publisherRegistry.register("code1", address(0x2001), address(0x2001));

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit AdConversion.PublisherAddedToAllowlist(allowlistCampaign, "code1");

        // Add publisher to allowlist
        vm.prank(advertiser);
        hook.addAllowedPublisherRefCode(allowlistCampaign, "code1");

        // Verify it was added
        assertTrue(hook.isPublisherRefCodeAllowed(allowlistCampaign, "code1"));
    }

    function test_addAllowedPublisherRefCode_redundantCall() public {
        // First create a campaign with allowlist enabled
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](0);
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = "TEST_REF_CODE";

        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, "https://example.com/campaign", allowedRefCodes, configs, 7 days
        );

        address allowlistCampaign = flywheel.createCampaign(address(hook), 4, hookData);

        // Register a new publisher
        vm.prank(owner);
        publisherRegistry.register("code1", address(0x2001), address(0x2001));

        // Add publisher to allowlist first time
        vm.prank(advertiser);
        hook.addAllowedPublisherRefCode(allowlistCampaign, "code1");

        // Verify it was added
        assertTrue(hook.isPublisherRefCodeAllowed(allowlistCampaign, "code1"));

        // Try to add the same publisher again - should not emit event
        vm.recordLogs();
        vm.prank(advertiser);
        hook.addAllowedPublisherRefCode(allowlistCampaign, "code1");

        // Verify no events were emitted (redundant call should be no-op)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "No events should be emitted for redundant calls");

        // Verify publisher is still allowed
        assertTrue(hook.isPublisherRefCodeAllowed(allowlistCampaign, "code1"));
    }

    // =============================================================
    //                    ATTRIBUTION PROVIDER FEE VALIDATION
    // =============================================================

    function test_campaignCreation_revert_feeTooHigh() public {
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

        string[] memory allowedRefCodes = new string[](0);

        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            uint48(7 days),
            uint16(10001) // > 100%, should revert
        );

        vm.expectRevert(abi.encodeWithSelector(AdConversion.InvalidFeeBps.selector, 10001));
        flywheel.createCampaign(address(hook), 123, hookData);
    }

    function test_campaignCreation_maxFeeAllowed() public {
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

        string[] memory allowedRefCodes = new string[](0);

        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            uint48(7 days),
            uint16(10000) // Exactly 100%, should succeed
        );

        address campaign = flywheel.createCampaign(address(hook), 123, hookData);

        // Verify fee is stored correctly
        (,, uint16 feeBps,,,) = hook.state(campaign);
        assertEq(feeBps, 10000);
    }

    function test_campaignSpecificFee_storesCorrectFeeAtCampaignCreation() public {
        // Create new campaign with 5% fee
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/new-campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(500)
        );

        address newCampaign = flywheel.createCampaign(address(hook), 500, hookData);

        // Verify the fee was stored correctly in campaign state
        (,, uint16 storedFee,,,) = hook.state(newCampaign);
        assertEq(storedFee, 500); // Should be 5%
    }

    function test_campaignSpecificFee_differentCampaignsCanHaveDifferentFees() public {
        // Register publisher for testing
        vm.prank(owner);
        publisherRegistry.register("testpub", randomUser, randomUser);

        // Create first campaign with 5% fee
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData1 = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign1",
            allowedRefCodes,
            configs,
            7 days,
            uint16(500)
        );
        address campaign1 = flywheel.createCampaign(address(hook), 501, hookData1);

        // Create second campaign with 15% fee
        bytes memory hookData2 = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign2",
            allowedRefCodes,
            configs,
            7 days,
            uint16(1500)
        );
        address campaign2 = flywheel.createCampaign(address(hook), 502, hookData2);

        // Verify campaigns store different fees
        (,, uint16 fee1,,,) = hook.state(campaign1);
        (,, uint16 fee2,,,) = hook.state(campaign2);
        assertEq(fee1, 500); // 5%
        assertEq(fee2, 1500); // 15%

        // Test that each campaign uses its own fee
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 1,
                publisherRefCode: "testpub",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: ""
        });
        bytes memory rewardData = abi.encode(attributions);

        // Campaign 1 should use 5% fee
        vm.prank(address(flywheel));
        (
            Flywheel.Payout[] memory payouts1,
            Flywheel.Payout[] memory immediateFees1,
            Flywheel.Allocation[] memory delayedFees1
        ) = hook.onSend(attributionProvider, campaign1, address(token), rewardData);
        assertEq(payouts1[0].amount, 95 ether); // 100 - 5% = 95
        assertEq(delayedFees1[0].amount, 5 ether); // 5% fee

        // Campaign 2 should use 15% fee
        vm.prank(address(flywheel));
        (
            Flywheel.Payout[] memory payouts2,
            Flywheel.Payout[] memory immediateFees2,
            Flywheel.Allocation[] memory delayedFees2
        ) = hook.onSend(attributionProvider, campaign2, address(token), rewardData);
        assertEq(payouts2[0].amount, 85 ether); // 100 - 15% = 85
        assertEq(delayedFees2[0].amount, 15 ether); // 15% fee
    }

    function test_campaignSpecificFee_zeroFeeWorks() public {
        // Create campaign with 0% fee
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/zero-fee-campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(0)
        );

        address zeroFeeCampaign = flywheel.createCampaign(address(hook), 503, hookData);

        // Verify 0% fee was stored
        (,, uint16 storedFee,,,) = hook.state(zeroFeeCampaign);
        assertEq(storedFee, 0);

        // Test that reward uses 0% fee
        vm.prank(owner);
        publisherRegistry.register("zeropub", randomUser, randomUser);

        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click789",
                configId: 1,
                publisherRefCode: "zeropub",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: ""
        });

        bytes memory rewardData = abi.encode(attributions);

        vm.prank(address(flywheel));
        (
            Flywheel.Payout[] memory payouts,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        ) = hook.onSend(attributionProvider, zeroFeeCampaign, address(token), rewardData);

        // Should use 0% fee - full amount to publisher
        assertEq(payouts[0].amount, 100 ether); // 100 - 0% = 100
        assertEq(immediateFees.length, 0); // no fees
        assertEq(delayedFees.length, 0); // no fees
    }

    // =============================================================
    //                    CONVERSION CONFIG MANAGEMENT
    // =============================================================

    function test_addConversionConfig_success() public {
        AdConversion.ConversionConfigInput memory newConfig =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/new-config"});

        vm.expectEmit(true, true, false, true);
        emit AdConversion.ConversionConfigAdded(
            campaign,
            3, // Next ID
            AdConversion.ConversionConfig({
                isActive: true,
                isEventOnchain: true,
                metadataURI: "https://example.com/new-config"
            })
        );

        vm.prank(advertiser);
        hook.addConversionConfig(campaign, newConfig);

        // Verify config was added
        AdConversion.ConversionConfig memory retrievedConfig = hook.getConversionConfig(campaign, 3);
        assertTrue(retrievedConfig.isActive);
        assertTrue(retrievedConfig.isEventOnchain);
        assertEq(retrievedConfig.metadataURI, "https://example.com/new-config");
    }

    function test_addConversionConfig_revert_unauthorized() public {
        AdConversion.ConversionConfigInput memory newConfig =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/unauthorized"});

        vm.expectRevert(AdConversion.Unauthorized.selector);
        vm.prank(randomUser);
        hook.addConversionConfig(campaign, newConfig);
    }

    function test_disableConversionConfig_success() public {
        vm.expectEmit(true, true, false, true);
        emit AdConversion.ConversionConfigStatusChanged(campaign, 1, false);

        vm.prank(advertiser);
        hook.disableConversionConfig(campaign, 1);

        AdConversion.ConversionConfig memory config = hook.getConversionConfig(campaign, 1);
        assertFalse(config.isActive);
    }

    function test_disableConversionConfig_revert_unauthorized() public {
        vm.expectRevert(AdConversion.Unauthorized.selector);
        vm.prank(randomUser);
        hook.disableConversionConfig(campaign, 1);
    }

    function test_disableConversionConfig_revert_invalidId() public {
        vm.expectRevert(AdConversion.InvalidConversionConfigId.selector);
        vm.prank(advertiser);
        hook.disableConversionConfig(campaign, 99); // uint8 max is 255
    }

    function test_disableConversionConfig_revert_alreadyDisabled() public {
        // First disable the config
        vm.prank(advertiser);
        hook.disableConversionConfig(campaign, 1);

        // Verify it's disabled
        AdConversion.ConversionConfig memory config = hook.getConversionConfig(campaign, 1);
        assertFalse(config.isActive);

        // Try to disable it again - should revert
        vm.expectRevert(AdConversion.ConversionConfigDisabled.selector);
        vm.prank(advertiser);
        hook.disableConversionConfig(campaign, 1);
    }

    // Note: There's no enableConversionConfig function - configs cannot be re-enabled once disabled
    // This is by design to prevent accidental re-activation of disabled conversion types

    // =============================================================
    //                    PUBLISHER ALLOWLIST MANAGEMENT
    // =============================================================

    // Note: There's no removeAllowedPublisherRefCode function - publishers cannot be removed once added
    // This is by design to prevent accidental removal of authorized publishers

    function test_isPublisherRefCodeAllowed_noAllowlist(uint16 codeNum) public {
        // Campaign with empty allowlist should allow all publishers
        assertTrue(hook.isPublisherRefCodeAllowed(campaign, generateCode(codeNum)));
    }

    // =============================================================
    //                    EDGE CASES AND ERROR HANDLING
    // =============================================================

    function test_onReward_revert_unauthorizedAttributionProvider() public {
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 1,
                publisherRefCode: "code1",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: abi.encode(AdConversion.Log({chainId: block.chainid, transactionHash: bytes32(uint256(1)), index: 0}))
        });

        bytes memory hookData = abi.encode(attributions);

        vm.expectRevert(AdConversion.Unauthorized.selector);
        vm.prank(address(flywheel)); // Called from flywheel but with wrong attribution provider
        hook.onSend(randomUser, campaign, address(token), hookData); // randomUser not the campaign's attribution provider
    }

    function test_onReward_revert_invalidConversionConfigId() public {
        vm.prank(owner);
        publisherRegistry.register("code1", address(0x1001), address(0x1001));

        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 99, // Invalid config ID
                publisherRefCode: "code1",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: ""
        });

        bytes memory hookData = abi.encode(attributions);

        vm.expectRevert(AdConversion.InvalidConversionConfigId.selector);
        vm.prank(address(flywheel));
        hook.onSend(attributionProvider, campaign, address(token), hookData);
    }

    function test_onReward_allowsDisabledConversionConfig() public {
        // Create a new campaign with 10% attribution provider fee for this test
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/config0"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config1"});
        string[] memory allowedRefCodes = new string[](0);
        bytes memory campaignHookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/test-campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(1000) // 10% fee
        );
        address testCampaign = flywheel.createCampaign(address(hook), 999, campaignHookData);

        // Disable config 1
        vm.prank(advertiser);
        hook.disableConversionConfig(testCampaign, 1);

        vm.prank(owner);
        publisherRegistry.register("code1", address(0x1001), address(0x1001));

        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 1, // Disabled config - should still work
                publisherRefCode: "code1",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: abi.encode(AdConversion.Log({chainId: block.chainid, transactionHash: bytes32(uint256(1)), index: 0}))
        });

        bytes memory hookData = abi.encode(attributions);

        // Should succeed even with disabled config
        vm.prank(address(flywheel));
        (
            Flywheel.Payout[] memory payouts,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        ) = hook.onSend(attributionProvider, testCampaign, address(token), hookData);

        // Verify results
        assertEq(payouts.length, 1);
        assertEq(payouts[0].recipient, address(0x1001));
        assertEq(payouts[0].amount, 90 ether); // 100 - 10% fee
        assertEq(immediateFees.length, 0);
        assertEq(delayedFees.length, 1);
        assertEq(delayedFees[0].key, bytes32(bytes20(attributionProvider)));
        assertEq(delayedFees[0].amount, 10 ether);
    }

    function test_onReward_revert_publisherNotInAllowlist() public {
        // Register publishers
        vm.startPrank(owner);
        publisherRegistry.register("notonallowlist", address(0x9999), address(0x9999));
        publisherRegistry.register("code1", address(0x7001), address(0x7001)); // Register the allowlisted code
        vm.stopPrank();

        // Create campaign with specific allowlist that DOESN'T include the registered publisher
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = "code1"; // Only code1 is allowed

        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(500)
        );

        address limitedCashbackCampaign = flywheel.createCampaign(address(hook), 5, hookData);

        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 1,
                publisherRefCode: "notonallowlist", // Registered but not in allowlist
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: ""
        });

        bytes memory rewardData = abi.encode(attributions);

        vm.expectRevert(AdConversion.PublisherNotAllowed.selector);
        vm.prank(address(flywheel));
        hook.onSend(attributionProvider, limitedCashbackCampaign, address(token), rewardData);
    }

    function test_onReward_revert_publisherNotRegistered() public {
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 2,
                publisherRefCode: "code2",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: ""
        });

        bytes memory hookData = abi.encode(attributions);

        vm.expectRevert(AdConversion.InvalidPublisherRefCode.selector);
        vm.prank(address(flywheel));
        hook.onSend(attributionProvider, campaign, address(token), hookData);
    }

    // =============================================================
    //                    BATCH ATTRIBUTION PROCESSING
    // =============================================================

    function test_onReward_batchAttributions() public {
        // Register additional publishers
        vm.startPrank(owner);
        publisherRegistry.register("code1", address(0x1001), address(0x1001));
        publisherRegistry.register("code2", address(0x1002), address(0x1002));
        vm.stopPrank();

        // Create new campaign with 5% attribution provider fee
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/config0"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config1"});
        string[] memory allowedRefCodes = new string[](0);
        bytes memory campaignHookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(500)
        );
        address testCampaign = flywheel.createCampaign(address(hook), 1003, campaignHookData);

        // Create batch of attributions
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](3);

        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click1",
                configId: 1,
                publisherRefCode: "random",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: abi.encode(AdConversion.Log({chainId: block.chainid, transactionHash: bytes32(uint256(1)), index: 0}))
        });

        attributions[1] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(2)),
                clickId: "click2",
                configId: 2,
                publisherRefCode: "code1",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 200 ether
            }),
            logBytes: ""
        });

        attributions[2] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(3)),
                clickId: "click3",
                configId: 2,
                publisherRefCode: "code2",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0x2222), // Custom recipient
                payoutAmount: 150 ether
            }),
            logBytes: ""
        });

        bytes memory hookData = abi.encode(attributions);

        vm.prank(address(flywheel));
        (
            Flywheel.Payout[] memory payouts,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        ) = hook.onSend(attributionProvider, testCampaign, address(token), hookData);

        // Verify results
        assertEq(payouts.length, 3);

        // First attribution: "random" publisher (randomUser)
        assertEq(payouts[0].recipient, randomUser);
        assertEq(payouts[0].amount, 95 ether); // 100 - 5%

        // Second attribution: "code1" publisher
        assertEq(payouts[1].recipient, address(0x1001));
        assertEq(payouts[1].amount, 190 ether); // 200 - 5%

        // Third attribution: Custom recipient
        assertEq(payouts[2].recipient, address(0x2222));
        assertEq(payouts[2].amount, 142.5 ether); // 150 - 5%

        // Total fee: 5% of (100 + 200 + 150) = 22.5 ether
        assertEq(immediateFees.length, 0);
        assertEq(delayedFees.length, 1);
        assertEq(delayedFees[0].key, bytes32(bytes20(attributionProvider)));
        assertEq(delayedFees[0].amount, 22.5 ether);
        assertEq(keccak256(delayedFees[0].extraData), keccak256(""));
    }

    // =============================================================
    //                    STATUS UPDATE HOOKS
    // =============================================================

    function test_onUpdateStatus_success() public {
        vm.prank(address(flywheel));
        hook.onUpdateStatus(
            attributionProvider, campaign, Flywheel.CampaignStatus.INACTIVE, Flywheel.CampaignStatus.ACTIVE, ""
        );
        // Should not revert - hook allows all status transitions
    }

    function test_onUpdateStatus_revert_unauthorized() public {
        vm.expectRevert(AdConversion.Unauthorized.selector);
        vm.prank(address(flywheel)); // Called from flywheel but with wrong sender
        hook.onUpdateStatus(
            randomUser, // randomUser is not the campaign's attribution provider
            campaign,
            Flywheel.CampaignStatus.INACTIVE,
            Flywheel.CampaignStatus.ACTIVE,
            ""
        );
    }

    // =============================================================
    //                    UNSUPPORTED OPERATIONS
    // =============================================================

    function test_onAllocate_revert_unsupported() public {
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 1,
                publisherRefCode: "code1",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: abi.encode(AdConversion.Log({chainId: block.chainid, transactionHash: bytes32(uint256(1)), index: 0}))
        });

        bytes memory hookData = abi.encode(attributions);

        vm.expectRevert(); // Should revert with unsupported operation
        vm.prank(address(flywheel));
        hook.onAllocate(attributionProvider, campaign, address(token), hookData);
    }

    function test_onDeallocate_revert_unsupported() public {
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 1,
                publisherRefCode: "code1",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100 ether
            }),
            logBytes: abi.encode(AdConversion.Log({chainId: block.chainid, transactionHash: bytes32(uint256(1)), index: 0}))
        });

        bytes memory hookData = abi.encode(attributions);

        vm.expectRevert(); // Should revert with unsupported operation
        vm.prank(address(flywheel));
        hook.onDeallocate(attributionProvider, campaign, address(token), hookData);
    }

    function test_onDistribute_revert_unsupported() public {
        vm.expectRevert(); // Should revert with unsupported operation
        vm.prank(address(flywheel));
        hook.onDistribute(attributionProvider, campaign, address(token), "");
    }

    // =============================================================
    //                    CAMPAIGN URI AND METADATA
    // =============================================================

    function test_campaignURI_returnsCorrectURI() public {
        string memory uri = hook.campaignURI(campaign);
        assertEq(uri, "https://example.com/campaign");
    }

    function test_getConversionConfig_returnsCorrectConfig() public {
        AdConversion.ConversionConfig memory config1 = hook.getConversionConfig(campaign, 1);
        assertTrue(config1.isActive);
        assertTrue(config1.isEventOnchain);
        assertEq(config1.metadataURI, "https://example.com/config0");

        AdConversion.ConversionConfig memory config2 = hook.getConversionConfig(campaign, 2);
        assertTrue(config2.isActive);
        assertFalse(config2.isEventOnchain);
        assertEq(config2.metadataURI, "https://example.com/config1");
    }

    function test_getConversionConfig_revert_invalidId() public {
        vm.expectRevert(AdConversion.InvalidConversionConfigId.selector);
        hook.getConversionConfig(campaign, 99);
    }

    function test_campaignCreation_customAttributionDeadline() public {
        // Create campaign with 14-day attribution deadline
        uint48 customDeadline = 14 days;
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, "https://example.com/campaign", allowedRefCodes, configs, customDeadline
        );

        address customCampaign = flywheel.createCampaign(address(hook), 999, hookData);

        // Get campaign state to verify custom attribution window duration
        (,,,, uint48 storedDuration,) = hook.state(customCampaign);
        assertEq(storedDuration, customDeadline);
    }

    function test_campaignCreation_zeroDeadlineAllowed() public {
        // Create campaign with 0 attribution deadline (instant finalization allowed)
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            uint48(0) // Valid - allows instant finalization
        );

        address zeroCampaign = flywheel.createCampaign(address(hook), 998, hookData);

        // Verify zero deadline is stored correctly
        (,,,, uint48 storedDuration,) = hook.state(zeroCampaign);
        assertEq(storedDuration, 0);
    }

    function test_campaignCreation_revert_invalidPrecision() public {
        // Try to create with 1.5 days (not days precision)
        uint48 invalidDeadline = 1 days + 12 hours;
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, "https://example.com/campaign", allowedRefCodes, configs, invalidDeadline
        );

        vm.expectRevert(abi.encodeWithSelector(AdConversion.InvalidAttributionWindow.selector, invalidDeadline));
        flywheel.createCampaign(address(hook), 997, hookData);
    }

    function test_campaignCreation_revert_hoursMinutesPrecision() public {
        // Test various invalid durations that are not in days precision
        uint48[] memory invalidDurations = new uint48[](4);
        invalidDurations[0] = 2 hours; // Just hours
        invalidDurations[1] = 3 days + 5 hours; // Days with hours
        invalidDurations[2] = 7 days + 30 minutes; // Days with minutes
        invalidDurations[3] = 10 days + 45 seconds; // Days with seconds

        for (uint256 i = 0; i < invalidDurations.length; i++) {
            AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
            configs[0] =
                AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

            string[] memory allowedRefCodes = new string[](0);
            bytes memory hookData = abi.encode(
                attributionProvider,
                advertiser,
                "https://example.com/campaign",
                allowedRefCodes,
                configs,
                invalidDurations[i]
            );

            vm.expectRevert(abi.encodeWithSelector(AdConversion.InvalidAttributionWindow.selector, invalidDurations[i]));
            flywheel.createCampaign(address(hook), 996 - i, hookData);
        }
    }

    function test_hasPublisherAllowlist_noAllowlist() public {
        assertEq(hook.hasPublisherAllowlist(campaign), false);
    }

    function test_hasPublisherAllowlist_withAllowlist() public {
        // Register the ref code before creating campaign
        vm.prank(owner);
        publisherRegistry.register("test_ref_code", address(0x6001), address(0x6001));

        // Create campaign with allowlist using ref codes
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = "test_ref_code";

        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/metadata"});

        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(500)
        );

        address campaignWithAllowlist = flywheel.createCampaign(address(hook), 2, hookData);

        assertEq(hook.hasPublisherAllowlist(campaignWithAllowlist), true);
    }

    function test_campaignCreation_oneDayDeadlineAllowed() public {
        // Create campaign with 1 day (minimum) attribution deadline
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            uint48(1 days) // Minimum allowed value
        );

        address minCampaign = flywheel.createCampaign(address(hook), 995, hookData);

        // Should use 1 day
        (,,,, uint48 storedDuration,) = hook.state(minCampaign);
        assertEq(storedDuration, 1 days);
    }

    function test_campaignCreation_sixMonthMaxDeadlineAllowed() public {
        // Create campaign with exactly 180-day (6-month) attribution deadline (maximum allowed)
        uint48 maxDeadline = 180 days;
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, "https://example.com/campaign", allowedRefCodes, configs, maxDeadline
        );

        address maxCampaign = flywheel.createCampaign(address(hook), 994, hookData);

        // Should use the maximum deadline
        (,,,, uint48 storedDuration,) = hook.state(maxCampaign);
        assertEq(storedDuration, maxDeadline);
        assertEq(storedDuration, 180 days); // Verify it's exactly 180 days (6 months)
    }

    function test_campaignCreation_revert_exceedsSixMonthLimit() public {
        // Try to create campaign with 181 days (exceeds 6-month limit)
        uint48 exceededDeadline = 181 days;
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, "https://example.com/campaign", allowedRefCodes, configs, exceededDeadline
        );

        vm.expectRevert(abi.encodeWithSelector(AdConversion.InvalidAttributionWindow.selector, exceededDeadline));
        flywheel.createCampaign(address(hook), 995, hookData);
    }

    function test_campaignCreation_revert_variousExcessiveDeadlines() public {
        // Test various deadlines that exceed the 6-month limit
        uint48[] memory excessiveDeadlines = new uint48[](4);
        excessiveDeadlines[0] = 365 days; // 1 year
        excessiveDeadlines[1] = 200 days; // Just over 6 months
        excessiveDeadlines[2] = 730 days; // 2 years
        excessiveDeadlines[3] = type(uint48).max; // Maximum possible value

        for (uint256 i = 0; i < excessiveDeadlines.length; i++) {
            AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
            configs[0] =
                AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

            string[] memory allowedRefCodes = new string[](0);
            bytes memory hookData = abi.encode(
                attributionProvider,
                advertiser,
                "https://example.com/campaign",
                allowedRefCodes,
                configs,
                excessiveDeadlines[i]
            );

            vm.expectRevert(
                abi.encodeWithSelector(AdConversion.InvalidAttributionWindow.selector, excessiveDeadlines[i])
            );
            flywheel.createCampaign(address(hook), 996 - i, hookData);
        }
    }

    function test_campaignCreation_success_registeredRefCodeInAllowlist() public {
        // Register ref code first
        vm.prank(owner);
        publisherRegistry.register("registered_code", address(0x8001), address(0x8001));

        // Create campaign with registered ref code in allowlist - should succeed
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/config"});

        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = "registered_code"; // This code is registered

        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            uint16(500)
        );

        address newCampaign = flywheel.createCampaign(address(hook), 998, hookData);

        // Verify campaign was created successfully
        assertTrue(newCampaign != address(0));
        assertTrue(hook.hasPublisherAllowlist(newCampaign));
        assertTrue(hook.isPublisherRefCodeAllowed(newCampaign, "registered_code"));
    }

    function test_onUpdateMetadata_success() public {
        bytes memory hookData = abi.encode("test data");

        // Should succeed when called by advertiser
        vm.prank(address(flywheel));
        hook.onUpdateMetadata(advertiser, campaign, hookData);
    }

    function test_onUpdateMetadata_revert_unauthorized() public {
        bytes memory hookData = abi.encode("test data");

        vm.expectRevert(AdConversion.Unauthorized.selector);
        vm.prank(address(flywheel));
        hook.onUpdateMetadata(randomUser, campaign, hookData);
    }

    // =============================================================
    //                    STATE TRANSITION TESTS
    // =============================================================

    // Attribution Provider Permissions

    /// @notice Test attribution provider can activate campaigns (INACTIVE → ACTIVE)
    function test_onlyAttributionProviderCanActivate() public {
        // Verify campaign starts INACTIVE
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.INACTIVE));

        // Attribution provider can activate
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));
    }

    /// @notice Test attribution provider can transition FINALIZING → FINALIZED without deadline wait
    function test_attributionProvider_canTransitionFromFinalizingToFinalized() public {
        // Create campaign and move to ACTIVE
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Advertiser moves to FINALIZING
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Attribution provider CAN transition to FINALIZED (valid transition)
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");

        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
    }

    /// @notice Test attribution provider cannot pause active campaigns (ACTIVE → INACTIVE blocked)
    function test_attributionProvider_cannotPauseCampaign() public {
        // Start with ACTIVE campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));

        // Attribution provider CANNOT pause campaign (ACTIVE → INACTIVE) - now blocked for ALL parties
        vm.prank(attributionProvider);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.INACTIVE, "");

        // Campaign remains ACTIVE
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));
    }

    /// @notice Test attribution provider cannot revert from FINALIZING to ACTIVE
    function test_attributionProvider_cannotRevertFromFinalizingToActive() public {
        // Create campaign and move to ACTIVE
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Advertiser moves to FINALIZING
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");

        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        // Attribution provider should NOT be able to revert to ACTIVE
        vm.prank(attributionProvider);
        vm.expectRevert();
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
    }

    /// @notice Test attribution provider cannot revert from FINALIZING to INACTIVE
    function test_attributionProvider_cannotRevertFromFinalizingToInactive() public {
        // Create campaign and move to ACTIVE
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Advertiser moves to FINALIZING
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");

        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        // Attribution provider should NOT be able to revert to INACTIVE
        vm.prank(attributionProvider);
        vm.expectRevert();
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.INACTIVE, "");
    }

    /// @notice Test attribution provider comprehensive control with pause restrictions
    function test_attributionProviderControlWithPauseRestrictions() public {
        // Attribution Provider can do INACTIVE → ACTIVE
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));

        // Attribution Provider CANNOT do ACTIVE → INACTIVE (pause) - now blocked
        vm.prank(attributionProvider);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.INACTIVE, "");

        // Campaign remains ACTIVE after failed pause attempt
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));

        // Attribution Provider CAN do ACTIVE → FINALIZING
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Campaign transitions to FINALIZING successfully
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        // Attribution Provider can do FINALIZING → FINALIZED (no deadline wait)
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
    }

    // Advertiser Permissions

    /// @notice Test advertiser cannot activate campaigns (INACTIVE → ACTIVE blocked)
    function test_advertiserCannotActivateCampaign() public {
        // Verify campaign starts INACTIVE
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.INACTIVE));

        // Advertiser cannot activate (only attribution provider can)
        vm.prank(advertiser);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Campaign should still be INACTIVE
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.INACTIVE));
    }

    /// @notice Test advertiser limited state transitions (only ACTIVE → FINALIZING allowed)
    function test_advertiserLimitedStateTransitions() public {
        // Start with ACTIVE campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Advertiser CAN do ACTIVE → FINALIZING
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        // Create a second campaign to test ACTIVE → INACTIVE restriction
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](0);
        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData2 = abi.encode(
            attributionProvider, advertiser, "https://example.com/campaign2", allowedRefCodes, configs, 7 days
        );

        address campaign2 = flywheel.createCampaign(address(hook), 999, hookData2);

        // Attribution provider activates second campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign2, Flywheel.CampaignStatus.ACTIVE, "");

        // Advertiser CANNOT do ACTIVE → INACTIVE
        vm.prank(advertiser);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(campaign2, Flywheel.CampaignStatus.INACTIVE, "");
    }

    /// @notice Test advertiser can finalize never-activated campaigns directly (INACTIVE → FINALIZED)
    function test_advertiserCanFinalizeNeverActivatedCampaign() public {
        // Campaign starts INACTIVE and was never activated
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.INACTIVE));

        // Advertiser CANNOT activate (INACTIVE → ACTIVE) - only attribution provider can
        vm.prank(advertiser);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // But Advertiser CAN finalize directly from INACTIVE (fund recovery for never-activated campaigns)
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
    }

    /// @notice Test advertiser can finalize from active (ACTIVE → FINALIZING → FINALIZED)
    function test_advertiserCanFinalizeFromActive() public {
        // Start with ACTIVE campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Advertiser can go directly from ACTIVE → FINALIZING (no need for pause/escape route)
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        // Wait for attribution deadline and finalize
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
    }

    // Security Restrictions

    /// @notice Test no party can pause active campaigns (security improvement)
    function test_noPausingAllowed_securityImprovement() public {
        // Start ACTIVE campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Attribution provider CANNOT pause (ACTIVE → INACTIVE) - security restriction
        vm.prank(attributionProvider);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.INACTIVE, "");

        // Advertiser also CANNOT pause (ACTIVE → INACTIVE)
        vm.prank(advertiser);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.INACTIVE, "");

        // Campaign remains ACTIVE - no party can pause it
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));

        // Only valid transition from ACTIVE is to FINALIZING
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));
    }

    /// @notice Test malicious pause attacks are prevented by new security
    function test_maliciousPause_preventedByNewSecurity() public {
        // Start ACTIVE campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Malicious attribution provider tries to pause (this was previously possible)
        vm.prank(attributionProvider);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.INACTIVE, "");

        // Campaign remains ACTIVE - malicious pause attack is prevented
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));

        // Malicious third party also cannot pause
        vm.prank(address(0xbad));
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.INACTIVE, "");

        // Campaign still remains ACTIVE
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));

        // The only valid transition from ACTIVE is to FINALIZING
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));
    }

    // Deadline and Timing Tests

    /// @notice Test attribution provider sets deadline when entering FINALIZING state
    function test_attributionProvider_setsDeadlineWhenEnteringFinalizing() public {
        // Start with ACTIVE campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        uint256 transitionTime = block.timestamp;
        uint48 expectedDeadline = uint48(transitionTime + 7 days);

        // Expect AttributionDeadlineUpdated event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AdConversion.AttributionDeadlineUpdated(campaign, expectedDeadline);

        // Attribution provider transitions to FINALIZING
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Verify campaign is in FINALIZING state
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        // Verify deadline was set correctly
        (,,,,, uint48 actualDeadline) = hook.state(campaign);
        assertEq(actualDeadline, expectedDeadline);
    }

    /// @notice Test advertiser sets deadline when entering FINALIZING state
    function test_advertiser_setsDeadlineWhenEnteringFinalizing() public {
        // Start with ACTIVE campaign (attribution provider activates)
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        uint256 transitionTime = block.timestamp;
        uint48 expectedDeadline = uint48(transitionTime + 7 days);

        // Expect AttributionDeadlineUpdated event to be emitted
        vm.expectEmit(true, false, false, true);
        emit AdConversion.AttributionDeadlineUpdated(campaign, expectedDeadline);

        // Advertiser transitions to FINALIZING
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Verify campaign is in FINALIZING state
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        // Verify deadline was set correctly
        (,,,,, uint48 actualDeadline) = hook.state(campaign);
        assertEq(actualDeadline, expectedDeadline);
    }

    /// @notice Test deadline calculation with custom attribution window
    function test_deadlineSetting_customAttributionWindow() public {
        // Create campaign with 14-day attribution window
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] = AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "test"});

        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "test-uri",
            new string[](0),
            configs,
            uint48(14 days) // Custom 14-day window
        );

        address customCampaign = flywheel.createCampaign(address(hook), 999, hookData);

        // Activate campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(customCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        uint256 transitionTime = block.timestamp;
        uint48 expectedDeadline = uint48(transitionTime + 14 days);

        // Expect event with 14-day deadline
        vm.expectEmit(true, false, false, true);
        emit AdConversion.AttributionDeadlineUpdated(customCampaign, expectedDeadline);

        // Advertiser transitions to FINALIZING
        vm.prank(advertiser);
        flywheel.updateStatus(customCampaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Verify 14-day deadline was set
        (,,,,, uint48 actualDeadline) = hook.state(customCampaign);
        assertEq(actualDeadline, expectedDeadline);
    }

    /// @notice Test deadline setting with zero attribution window (instant finalization)
    function test_deadlineSetting_zeroAttributionWindow() public {
        // Create campaign with zero attribution window
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] = AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "test"});

        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "test-uri",
            new string[](0),
            configs,
            uint48(0) // Zero attribution window
        );

        address zeroCampaign = flywheel.createCampaign(address(hook), 998, hookData);

        // Activate campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(zeroCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        uint256 transitionTime = block.timestamp;
        uint48 expectedDeadline = uint48(transitionTime + 0); // Should be current timestamp

        // Expect event with zero deadline (current timestamp)
        vm.expectEmit(true, false, false, true);
        emit AdConversion.AttributionDeadlineUpdated(zeroCampaign, expectedDeadline);

        // Attribution provider transitions to FINALIZING
        vm.prank(attributionProvider);
        flywheel.updateStatus(zeroCampaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Verify zero deadline was set (should equal transition timestamp)
        (,,,,, uint48 actualDeadline) = hook.state(zeroCampaign);
        assertEq(actualDeadline, expectedDeadline);

        // Advertiser should be able to finalize immediately since deadline = current timestamp
        vm.prank(advertiser);
        flywheel.updateStatus(zeroCampaign, Flywheel.CampaignStatus.FINALIZED, "");
        assertEq(uint256(flywheel.campaignStatus(zeroCampaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
    }

    /// @notice Test finalization uses per-campaign attribution deadline
    function test_finalization_usesPerCampaignDeadline() public {
        // Create campaign with custom 14-day deadline
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] = AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "test"});

        bytes memory hookData = abi.encode(
            attributionProvider, // attributionProvider
            advertiser, // advertiser
            "test-uri", // uri
            new string[](0), // allowedRefCodes (empty - no allowlist)
            configs, // configs
            uint48(14 days) // campaignAttributionWindow
        );

        address customCampaign = flywheel.createCampaign(address(hook), 99, hookData);

        // Activate and move to finalizing
        vm.prank(attributionProvider);
        flywheel.updateStatus(customCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        vm.prank(advertiser);
        flywheel.updateStatus(customCampaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Should fail before 14 days (campaign-specific deadline)
        vm.warp(block.timestamp + 7 days);
        vm.prank(advertiser);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(customCampaign, Flywheel.CampaignStatus.FINALIZED, "");

        // Should succeed after 14 days
        vm.warp(block.timestamp + 14 days + 1);
        vm.prank(advertiser);
        flywheel.updateStatus(customCampaign, Flywheel.CampaignStatus.FINALIZED, "");
        assertEq(uint256(flywheel.campaignStatus(customCampaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
    }

    /// @notice Test finalization uses minimum deadline (1 day)
    function test_finalization_usesMinimumDeadline() public {
        // Create campaign with minimum 1-day deadline
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] = AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "test"});

        bytes memory hookData = abi.encode(
            attributionProvider, // attributionProvider
            advertiser, // advertiser
            "test-uri", // uri
            new string[](0), // allowedRefCodes (empty - no allowlist)
            configs, // configs
            uint48(1 days) // campaignAttributionWindow - minimum allowed
        );

        address minCampaign = flywheel.createCampaign(address(hook), 100, hookData);

        // Activate and move to finalizing
        vm.prank(attributionProvider);
        flywheel.updateStatus(minCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        vm.prank(advertiser);
        flywheel.updateStatus(minCampaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Should succeed after 1 day minimum
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(advertiser);
        flywheel.updateStatus(minCampaign, Flywheel.CampaignStatus.FINALIZED, "");
        assertEq(uint256(flywheel.campaignStatus(minCampaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
    }

    /// @notice Test instant finalization with zero deadline
    function test_finalization_instantWithZeroDeadline() public {
        // Create campaign with zero deadline (instant finalization)
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] = AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "test"});

        bytes memory hookData = abi.encode(
            attributionProvider, // attributionProvider
            advertiser, // advertiser
            "test-uri", // uri
            new string[](0), // allowedRefCodes (empty - no allowlist)
            configs, // configs
            uint48(0) // campaignAttributionWindow - zero for instant finalization
        );

        address instantCampaign = flywheel.createCampaign(address(hook), 101, hookData);

        // Activate and move to finalizing
        vm.prank(attributionProvider);
        flywheel.updateStatus(instantCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        vm.prank(advertiser);
        flywheel.updateStatus(instantCampaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Should succeed immediately with zero deadline
        vm.prank(advertiser);
        flywheel.updateStatus(instantCampaign, Flywheel.CampaignStatus.FINALIZED, "");

        assertEq(uint256(flywheel.campaignStatus(instantCampaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
    }

    // =============================================================
    //                    SECURITY STATE TRANSITION TESTS
    // =============================================================

    /// @notice Test attribution window bypass vulnerability - ACTIVE → FINALIZED attack
    /// @dev This tests the critical security fix that prevents bypassing attribution windows
    function test_security_attributionWindowBypass_activeToFinalized() public {
        address campaign = flywheel.createCampaign(
            address(hook),
            200,
            abi.encode(
                attributionProvider,
                advertiser,
                "https://example.com/campaign",
                new string[](0),
                _createBasicConversionConfigs(),
                7 days
            )
        );

        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Verify campaign is in ACTIVE state
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));

        // Advertiser attempts to bypass attribution window by going directly ACTIVE → FINALIZED
        vm.prank(advertiser);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");

        // Verify campaign is still ACTIVE
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));
    }

    /// @notice Test that proper state transition flow still works after security fix
    /// @dev Ensures the fix doesn't break legitimate ACTIVE → FINALIZING → FINALIZED flow
    function test_security_legitStateTransitionStillWorks() public {
        address campaign = flywheel.createCampaign(
            address(hook),
            201,
            abi.encode(
                attributionProvider,
                advertiser,
                "https://example.com/campaign",
                new string[](0),
                _createBasicConversionConfigs(),
                7 days
            )
        );

        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Step 1: ACTIVE → FINALIZING (should work)
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        // Step 2: Wait for attribution deadline (7 days for basic campaign)
        vm.warp(block.timestamp + 7 days + 1);

        // Step 3: FINALIZING → FINALIZED (should work)
        vm.prank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
    }

    /// @notice Test attribution provider can still perform valid state transitions
    /// @dev Ensures attribution provider privileges are preserved after security fix
    function test_security_attributionProviderBypassStillWorks() public {
        address campaign = flywheel.createCampaign(
            address(hook),
            202,
            abi.encode(
                attributionProvider,
                advertiser,
                "https://example.com/campaign",
                new string[](0),
                _createBasicConversionConfigs(),
                7 days
            )
        );

        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Attribution provider should be able to go ACTIVE → FINALIZING
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        // Attribution provider should be able to go FINALIZING → FINALIZED (no deadline wait)
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
    }

    /// @notice Test attribution provider CANNOT do INACTIVE → FINALIZED (fund recovery is advertiser-only)
    /// @dev Only advertiser should be able to recover funds from never-activated campaigns
    function test_security_attributionProviderCannotDoFundRecovery() public {
        address inactiveCampaign = flywheel.createCampaign(
            address(hook),
            205,
            abi.encode(
                attributionProvider,
                advertiser,
                "https://example.com/campaign",
                new string[](0),
                _createBasicConversionConfigs(),
                7 days
            )
        );

        // Attribution provider should NOT be able to do INACTIVE → FINALIZED (fund recovery)
        vm.prank(attributionProvider);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(inactiveCampaign, Flywheel.CampaignStatus.FINALIZED, "");

        // Campaign should still be INACTIVE
        assertEq(uint256(flywheel.campaignStatus(inactiveCampaign)), uint256(Flywheel.CampaignStatus.INACTIVE));
    }

    /// @notice Test attribution provider CANNOT do INACTIVE → FINALIZING (must activate first)
    /// @dev Attribution provider cannot skip the ACTIVE phase by going directly to FINALIZING
    function test_security_attributionProviderCannotSkipActivePhase() public {
        address inactiveCampaign = flywheel.createCampaign(
            address(hook),
            208,
            abi.encode(
                attributionProvider,
                advertiser,
                "https://example.com/campaign",
                new string[](0),
                _createBasicConversionConfigs(),
                7 days
            )
        );

        // Attribution provider should NOT be able to do INACTIVE → FINALIZING (skip ACTIVE phase)
        vm.prank(attributionProvider);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(inactiveCampaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Campaign should still be INACTIVE
        assertEq(uint256(flywheel.campaignStatus(inactiveCampaign)), uint256(Flywheel.CampaignStatus.INACTIVE));
    }

    /// @notice Test ONLY attribution provider can activate campaigns (INACTIVE → ACTIVE)
    /// @dev Demonstrates clear role separation for campaign activation
    function test_security_onlyAttributionProviderCanActivate() public {
        address inactiveCampaign = flywheel.createCampaign(
            address(hook),
            206,
            abi.encode(
                attributionProvider,
                advertiser,
                "https://example.com/campaign",
                new string[](0),
                _createBasicConversionConfigs(),
                7 days
            )
        );

        // Advertiser CANNOT activate campaign (INACTIVE → ACTIVE)
        vm.prank(advertiser);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(inactiveCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Random user CANNOT activate campaign
        vm.prank(randomUser);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(inactiveCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Campaign should still be INACTIVE
        assertEq(uint256(flywheel.campaignStatus(inactiveCampaign)), uint256(Flywheel.CampaignStatus.INACTIVE));

        // ONLY attribution provider CAN activate campaign (INACTIVE → ACTIVE)
        vm.prank(attributionProvider);
        flywheel.updateStatus(inactiveCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Campaign should now be ACTIVE
        assertEq(uint256(flywheel.campaignStatus(inactiveCampaign)), uint256(Flywheel.CampaignStatus.ACTIVE));
    }

    /// @notice Test attribution provider CANNOT bypass FINALIZING (ACTIVE → FINALIZED blocked globally)
    /// @dev Even attribution provider must go through proper state flow for security
    function test_security_attributionProviderCanBypassFinalizing() public {
        address activeCampaign = flywheel.createCampaign(
            address(hook),
            207,
            abi.encode(
                attributionProvider,
                advertiser,
                "https://example.com/campaign",
                new string[](0),
                _createBasicConversionConfigs(),
                7 days
            )
        );

        // Activate campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(activeCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Attribution provider CAN bypass FINALIZING (ACTIVE → FINALIZED allowed for them)
        vm.prank(attributionProvider);
        flywheel.updateStatus(activeCampaign, Flywheel.CampaignStatus.FINALIZED, "");

        // Campaign should be FINALIZED
        assertEq(uint256(flywheel.campaignStatus(activeCampaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
    }

    /// @notice Test that INACTIVE → FINALIZED is allowed directly for fund recovery
    /// @dev If attribution provider never activates campaign, advertiser can recover funds immediately
    function test_security_inactiveToFinalizedAllowed() public {
        address inactiveCampaign = flywheel.createCampaign(
            address(hook),
            203,
            abi.encode(
                attributionProvider,
                advertiser,
                "https://example.com/campaign",
                new string[](0),
                _createBasicConversionConfigs(),
                7 days
            )
        );

        // INACTIVE → FINALIZED should be allowed directly (fund recovery scenario, no deadline wait)
        vm.prank(advertiser);
        flywheel.updateStatus(inactiveCampaign, Flywheel.CampaignStatus.FINALIZED, "");
        assertEq(uint256(flywheel.campaignStatus(inactiveCampaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
    }

    /// @notice Test that only ACTIVE → FINALIZED is blocked, not other transitions
    /// @dev Ensures security fix is precise and doesn't break legitimate flows
    function test_security_onlyActiveToFinalizedBlocked() public {
        address activeCampaign = flywheel.createCampaign(
            address(hook),
            204,
            abi.encode(
                attributionProvider,
                advertiser,
                "https://example.com/campaign",
                new string[](0),
                _createBasicConversionConfigs(),
                7 days
            )
        );

        vm.prank(attributionProvider);
        flywheel.updateStatus(activeCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // ACTIVE → FINALIZED blocked (attribution window bypass vulnerability)
        vm.prank(advertiser);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(activeCampaign, Flywheel.CampaignStatus.FINALIZED, "");

        // But ACTIVE → FINALIZING still works
        vm.prank(advertiser);
        flywheel.updateStatus(activeCampaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertEq(uint256(flywheel.campaignStatus(activeCampaign)), uint256(Flywheel.CampaignStatus.FINALIZING));
    }

    function _createBasicConversionConfigs() internal pure returns (AdConversion.ConversionConfigInput[] memory) {
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/offchain"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/onchain"});
        return configs;
    }
}
