// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Flywheel} from "../src/Flywheel.sol";
import {BuilderCodes} from "../src/BuilderCodes.sol";
import {Campaign} from "../src/Campaign.sol";
import {AdConversion} from "../src/hooks/AdConversion.sol";
import {SimpleRewards} from "../src/hooks/SimpleRewards.sol";
import {DummyERC20} from "./mocks/DummyERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {FlywheelTestHelpers} from "./helpers/FlywheelTestHelpers.sol";

contract FlywheelTest is FlywheelTestHelpers {
    BuilderCodes public publisherRegistry;
    AdConversion public hook;

    address public advertiser = address(0x1);
    address public attributionProvider = address(0x2);
    address public owner = address(0x3);
    address public publisher1 = address(0x4);
    address public publisher2 = address(0x5);

    address public publisher1Payout = address(0x6);
    address public publisher2Payout = address(0x7);
    address public user = address(0x6);

    uint16 public constant ATTRIBUTION_FEE_BPS = 500; // 5%
    uint256 public constant INITIAL_BALANCE = 1000e18; // 1000 tokens
    address public campaign;

    function setUp() public {
        // Deploy token
        address[] memory initialHolders = new address[](2);
        initialHolders[0] = advertiser;
        initialHolders[1] = attributionProvider;
        token = new DummyERC20(initialHolders);

        // Deploy Flywheel
        flywheel = new Flywheel();

        // Deploy publisher registry
        BuilderCodes impl = new BuilderCodes();
        bytes memory initData = abi.encodeWithSelector(
            BuilderCodes.initialize.selector,
            owner,
            address(0x999), // signer address
            "" // empty baseURI
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        publisherRegistry = BuilderCodes(address(proxy));

        // Register publishers with ref codes
        vm.startPrank(owner);

        // Register publisher1 with ref code "PUBLISHER_1"
        publisherRegistry.register("code1", publisher1, publisher1Payout);

        // Register publisher2 with ref code "PUBLISHER_2"
        publisherRegistry.register("code2", publisher2, publisher2Payout);
        vm.stopPrank();

        // Deploy hook
        hook = new AdConversion(address(flywheel), owner, address(publisherRegistry));

        // Create a basic campaign for tests (without fees)
        _createCampaign();
    }

    function _createCampaign() internal {
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/offchain"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/onchain"});

        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            ATTRIBUTION_FEE_BPS
        );

        campaign = flywheel.createCampaign(address(hook), 1, hookData);
    }

    function test_createCampaign() public {
        // Verify campaign was created correctly
        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(Flywheel.CampaignStatus.INACTIVE));
        assert(flywheel.campaignExists(campaign));
        assertEq(flywheel.campaignHooks(campaign), address(hook));
        assertEq(flywheel.campaignURI(campaign), "https://example.com/campaign");
    }

    function test_campaignLifecycle() public {
        // Start with INACTIVE status
        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(Flywheel.CampaignStatus.INACTIVE));

        // Attribution provider opens campaign (INACTIVE -> ACTIVE)
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(Flywheel.CampaignStatus.ACTIVE));

        // Attribution provider can transition to FINALIZING
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");

        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(Flywheel.CampaignStatus.FINALIZING));

        // Attribution provider can finalize campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");

        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(Flywheel.CampaignStatus.FINALIZED));
    }

    function test_offchainAttribution() public {
        // Set attribution provider fee and create new campaign for this test
        vm.prank(attributionProvider);
        // Attribution fee is now set during campaign creation

        // Create new campaign with fee cached
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/offchain"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/onchain"});
        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            ATTRIBUTION_FEE_BPS
        );
        address testCampaign = flywheel.createCampaign(address(hook), 101, hookData);

        // Activate campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(testCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Fund campaign by transferring tokens directly to the Campaign
        vm.prank(advertiser);
        token.transfer(testCampaign, INITIAL_BALANCE);

        // Create offchain attribution data
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);

        AdConversion.Conversion memory conversion = AdConversion.Conversion({
            eventId: bytes16(0x1234567890abcdef1234567890abcdef),
            clickId: "click_123",
            configId: 1,
            publisherRefCode: "code1",
            timestamp: uint32(block.timestamp),
            payoutRecipient: address(0),
            payoutAmount: 100e18
        });

        attributions[0] = AdConversion.Attribution({
            conversion: conversion,
            logBytes: "" // Empty for offchain
        });

        bytes memory attributionData = abi.encode(attributions);

        // Process attribution with reward (immediate payout)
        vm.prank(attributionProvider);
        flywheel.send(testCampaign, address(token), attributionData);

        // Check that publisher received tokens immediately
        uint256 payoutAmount = 100e18;
        uint256 feeAmount = payoutAmount * ATTRIBUTION_FEE_BPS / 10000;
        uint256 expectedPayout = payoutAmount - feeAmount; // Amount minus fee
        assertEq(token.balanceOf(publisher1Payout), expectedPayout, "Publisher should receive tokens minus fee");

        // Check attribution provider fee is allocated
        uint256 expectedFee = feeAmount;
        assertEq(
            flywheel.allocatedFee(testCampaign, address(token), bytes32(bytes20(attributionProvider))),
            expectedFee,
            "Attribution provider should have fee allocated"
        );
    }

    function test_onchainAttribution() public {
        // Set attribution provider fee and create new campaign for this test
        vm.prank(attributionProvider);
        // Attribution fee is now set during campaign creation

        // Create new campaign with fee cached
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/offchain"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/onchain"});
        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            ATTRIBUTION_FEE_BPS
        );
        address testCampaign = flywheel.createCampaign(address(hook), 102, hookData);

        // Activate campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(testCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Fund campaign by transferring tokens directly to the Campaign
        vm.prank(advertiser);
        token.transfer(testCampaign, INITIAL_BALANCE);

        // Create onchain attribution data
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);

        AdConversion.Conversion memory conversion = AdConversion.Conversion({
            eventId: bytes16(0xabcdef1234567890abcdef1234567890),
            clickId: "click_456",
            configId: 2,
            publisherRefCode: "code2",
            timestamp: uint32(block.timestamp),
            payoutRecipient: address(0),
            payoutAmount: 200 * 10 ** 18
        });

        AdConversion.Log memory log =
            AdConversion.Log({chainId: 1, transactionHash: keccak256("test_transaction"), index: 0});

        attributions[0] = AdConversion.Attribution({
            conversion: conversion,
            logBytes: abi.encode(log) // Encoded log for onchain
        });

        bytes memory attributionData = abi.encode(attributions);

        // Process attribution with reward (immediate payout)
        vm.prank(attributionProvider);
        flywheel.send(testCampaign, address(token), attributionData);

        // Check that publisher received tokens immediately
        uint256 payoutAmount2 = 200 * 10 ** 18;
        uint256 feeAmount2 = payoutAmount2 * ATTRIBUTION_FEE_BPS / 10000;
        uint256 expectedPayout = payoutAmount2 - feeAmount2;
        assertEq(token.balanceOf(publisher2Payout), expectedPayout, "Publisher should receive tokens minus fee");

        // Check attribution provider fee is allocated
        uint256 expectedFee = feeAmount2;
        assertEq(
            flywheel.allocatedFee(testCampaign, address(token), bytes32(bytes20(attributionProvider))),
            expectedFee,
            "Attribution provider should have fee allocated"
        );
    }

    function test_distributeAndWithdraw() public {
        address payoutRecipient = address(0x1222);

        // Set attribution provider fee and create new campaign for this test
        vm.prank(attributionProvider);
        // Attribution fee is now set during campaign creation

        // Create new campaign with fee cached
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/offchain"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/onchain"});
        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            ATTRIBUTION_FEE_BPS
        );
        address testCampaign = flywheel.createCampaign(address(hook), 104, hookData);

        // Activate campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(testCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Fund campaign by transferring tokens directly to the Campaign
        vm.prank(advertiser);
        token.transfer(testCampaign, INITIAL_BALANCE);

        // Create attribution data
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);

        AdConversion.Conversion memory conversion = AdConversion.Conversion({
            eventId: bytes16(0x1234567890abcdef1234567890abcdef),
            clickId: "click_789",
            configId: 1,
            publisherRefCode: "",
            timestamp: uint32(block.timestamp),
            payoutRecipient: payoutRecipient,
            payoutAmount: 50 * 10 ** 18
        });

        attributions[0] = AdConversion.Attribution({conversion: conversion, logBytes: ""});

        bytes memory attributionData = abi.encode(attributions);

        // Process attribution with reward (immediate payout)
        vm.prank(attributionProvider);
        flywheel.send(testCampaign, address(token), attributionData);

        // Verify payoutRecipient received tokens
        uint256 payoutAmount3 = 50 * 10 ** 18;
        uint256 feeAmount3 = payoutAmount3 * ATTRIBUTION_FEE_BPS / 10000;
        uint256 expectedPayout = payoutAmount3 - feeAmount3;
        assertEq(token.balanceOf(payoutRecipient), expectedPayout, "Payout recipient should receive tokens minus fee");

        // Finalize campaign
        vm.startPrank(attributionProvider);
        flywheel.updateStatus(testCampaign, Flywheel.CampaignStatus.FINALIZING, "");
        flywheel.updateStatus(testCampaign, Flywheel.CampaignStatus.FINALIZED, "");
        vm.stopPrank();

        // First, attribution provider collects their fee
        vm.startPrank(attributionProvider);
        flywheel.distributeFees(testCampaign, address(token), abi.encode(attributionProvider));
        vm.stopPrank();

        // Withdraw remaining tokens
        uint256 campaignBalance = token.balanceOf(testCampaign);
        vm.startPrank(advertiser);
        uint256 advertiserBalanceBefore = token.balanceOf(advertiser);
        flywheel.withdrawFunds(testCampaign, address(token), abi.encode(advertiser, campaignBalance));
        uint256 advertiserBalanceAfter = token.balanceOf(advertiser);

        assertEq(
            advertiserBalanceAfter - advertiserBalanceBefore,
            campaignBalance,
            "Advertiser should receive remaining campaign tokens"
        );
        vm.stopPrank();
    }

    function test_distributeFees() public {
        address payoutRecipient = address(0x1222);

        // Set attribution provider fee and create new campaign for this test
        vm.prank(attributionProvider);
        // Attribution fee is now set during campaign creation

        // Create new campaign with fee cached
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/offchain"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/onchain"});
        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            ATTRIBUTION_FEE_BPS
        );
        address testCampaign = flywheel.createCampaign(address(hook), 103, hookData);

        // Activate campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(testCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Fund campaign by transferring tokens directly to the Campaign
        vm.prank(advertiser);
        token.transfer(testCampaign, INITIAL_BALANCE);

        // Create attribution data to generate fees
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);

        AdConversion.Conversion memory conversion = AdConversion.Conversion({
            eventId: bytes16(0x1234567890abcdef1234567890abcdef),
            clickId: "click_fees",
            configId: 1,
            publisherRefCode: "",
            timestamp: uint32(block.timestamp),
            payoutRecipient: payoutRecipient,
            payoutAmount: 100 * 10 ** 18
        });

        attributions[0] = AdConversion.Attribution({conversion: conversion, logBytes: ""});

        bytes memory attributionData = abi.encode(attributions);

        // Process attribution to generate fees
        vm.prank(attributionProvider);
        flywheel.send(testCampaign, address(token), attributionData);

        // Check that fees are available
        uint256 payoutAmount4 = 100 * 10 ** 18;
        uint256 expectedFee = payoutAmount4 * ATTRIBUTION_FEE_BPS / 10000;
        uint256 availableFees =
            flywheel.allocatedFee(testCampaign, address(token), bytes32(bytes20(attributionProvider)));
        assertEq(availableFees, expectedFee, "Should have correct attribution fee allocated");

        // Collect fees as attribution provider
        vm.startPrank(attributionProvider);
        uint256 balanceBefore = token.balanceOf(attributionProvider);
        flywheel.distributeFees(testCampaign, address(token), abi.encode(attributionProvider));
        uint256 balanceAfter = token.balanceOf(attributionProvider);

        assertEq(balanceAfter - balanceBefore, expectedFee, "Attribution provider should receive fee tokens");

        // Check that fees are cleared
        uint256 remainingFees =
            flywheel.allocatedFee(testCampaign, address(token), bytes32(bytes20(attributionProvider)));
        assertEq(remainingFees, 0, "Fees should be cleared after collection");
        vm.stopPrank();
    }

    // =============================================================
    //                    ALLOCATE/DISTRIBUTE FUNCTIONALITY
    // =============================================================

    function test_allocateAndDistribute() public {
        // Test core allocate/distribute functionality using SimpleRewards
        SimpleRewards simpleHook = new SimpleRewards(address(flywheel));
        address manager = address(0x1333);

        // Create SimpleRewards campaign
        bytes memory hookData = abi.encode(manager, manager, "");
        address simpleCampaign = flywheel.createCampaign(address(simpleHook), 100, hookData);

        // Fund and activate campaign
        vm.prank(advertiser);
        token.transfer(simpleCampaign, INITIAL_BALANCE);

        vm.prank(manager);
        flywheel.updateStatus(simpleCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        address recipient = address(0x1444);

        // Test allocate operation
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: recipient, amount: 150e18, extraData: "allocate-test"});

        vm.prank(manager);
        (Flywheel.Allocation[] memory allocateResult) =
            flywheel.allocate(simpleCampaign, address(token), abi.encode(payouts));

        // Verify allocation results
        assertEq(allocateResult.length, 1);
        assertEq(allocateResult[0].amount, 150e18);

        // Verify tokens not transferred yet (allocation phase)
        assertEq(token.balanceOf(recipient), 0);

        // Test distribute operation
        vm.prank(manager);
        (
            Flywheel.Distribution[] memory distributeResult,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        ) = flywheel.distribute(simpleCampaign, address(token), abi.encode(payouts));

        // Verify distribution results
        assertEq(distributeResult.length, 1);
        assertEq(distributeResult[0].amount, 150e18);
        // SimpleRewards charges no fees
        assertEq(immediateFees.length, 0);
        assertEq(delayedFees.length, 0);

        // Verify tokens were transferred
        assertEq(token.balanceOf(recipient), 150e18);
    }

    function test_deallocate() public {
        // Test core deallocate functionality using SimpleRewards
        SimpleRewards simpleHook = new SimpleRewards(address(flywheel));
        address manager = address(0x1555);

        // Create SimpleRewards campaign
        bytes memory hookData = abi.encode(manager, manager, "");
        address simpleCampaign = flywheel.createCampaign(address(simpleHook), 101, hookData);

        // Fund and activate campaign
        vm.prank(advertiser);
        token.transfer(simpleCampaign, INITIAL_BALANCE);

        vm.prank(manager);
        flywheel.updateStatus(simpleCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        address recipient = address(0x1666);

        // First allocate tokens
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: recipient, amount: 100e18, extraData: "deallocate-test"});

        vm.prank(manager);
        flywheel.allocate(simpleCampaign, address(token), abi.encode(payouts));

        // Verify allocation exists
        assertEq(flywheel.allocatedPayout(simpleCampaign, address(token), bytes32(bytes20(recipient))), 100e18);

        // Test deallocate operation
        vm.prank(manager);
        flywheel.deallocate(simpleCampaign, address(token), abi.encode(payouts));

        // Verify allocation was removed
        assertEq(flywheel.allocatedPayout(simpleCampaign, address(token), bytes32(bytes20(recipient))), 0);

        // Verify no tokens were transferred to recipient
        assertEq(token.balanceOf(recipient), 0);
    }

    // =============================================================
    //                    MULTI-TOKEN SUPPORT
    // =============================================================

    function test_multiTokenCampaign() public {
        // Deploy a second token
        address[] memory holders = new address[](1);
        holders[0] = advertiser;
        DummyERC20 token2 = new DummyERC20(holders);

        // Activate campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Fund campaign with both tokens
        vm.startPrank(advertiser);
        token.transfer(campaign, INITIAL_BALANCE);
        token2.transfer(campaign, INITIAL_BALANCE / 2);
        vm.stopPrank();

        // Create attributions for both tokens
        address recipient1 = address(0x1555);
        address recipient2 = address(0x1666);

        // Attribution for token1
        AdConversion.Attribution[] memory attributions1 = new AdConversion.Attribution[](1);
        attributions1[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(0x55555555555555556666666666666666)),
                clickId: "token1_test",
                configId: 1,
                publisherRefCode: "",
                timestamp: uint32(block.timestamp),
                payoutRecipient: recipient1,
                payoutAmount: 50e18
            }),
            logBytes: ""
        });

        // Attribution for token2
        AdConversion.Attribution[] memory attributions2 = new AdConversion.Attribution[](1);
        attributions2[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(0x77777777777777778888888888888888)),
                clickId: "token2_test",
                configId: 1,
                publisherRefCode: "",
                timestamp: uint32(block.timestamp),
                payoutRecipient: recipient2,
                payoutAmount: 25e18
            }),
            logBytes: ""
        });

        // Process both attributions
        vm.startPrank(attributionProvider);
        flywheel.send(campaign, address(token), abi.encode(attributions1));
        flywheel.send(campaign, address(token2), abi.encode(attributions2));
        vm.stopPrank();

        // Verify both recipients received their respective tokens (minus 5% fee)
        uint256 expectedRecipient1Amount = 50e18 * (10000 - 500) / 10000; // 47.5e18 (5% fee deducted)
        uint256 expectedRecipient2Amount = 25e18 * (10000 - 500) / 10000; // 23.75e18 (5% fee deducted)
        assertEq(token.balanceOf(recipient1), expectedRecipient1Amount, "Recipient1 should receive token1");
        assertEq(token2.balanceOf(recipient2), expectedRecipient2Amount, "Recipient2 should receive token2");
    }

    function test_multiTokenFeeCollection() public {
        // Deploy second token
        address[] memory holders = new address[](1);
        holders[0] = advertiser;
        DummyERC20 token2 = new DummyERC20(holders);

        // Set 10% fee for this test and create new campaign
        vm.prank(attributionProvider);
        // Attribution fee (10%) is now set during campaign creation

        // Create new campaign with 10% fee cached
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/offchain"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/onchain"});
        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            ATTRIBUTION_FEE_BPS
        );
        address multiTokenCampaign = flywheel.createCampaign(address(hook), 999, hookData);

        // Activate the new campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(multiTokenCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Fund campaign with both tokens
        vm.startPrank(advertiser);
        token.transfer(multiTokenCampaign, INITIAL_BALANCE);
        token2.transfer(multiTokenCampaign, INITIAL_BALANCE);
        vm.stopPrank();

        // Create attributions that generate fees in both tokens
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(0x99999999999999990000000000000000)),
                clickId: "fee_test",
                configId: 1,
                publisherRefCode: "",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0x1777),
                payoutAmount: 100e18
            }),
            logBytes: ""
        });

        // Process attributions for both tokens
        vm.startPrank(attributionProvider);
        flywheel.send(multiTokenCampaign, address(token), abi.encode(attributions));
        flywheel.send(multiTokenCampaign, address(token2), abi.encode(attributions));
        vm.stopPrank();

        // Verify fees are collected for both tokens
        uint256 expectedFee = 100e18 * 500 / 10000; // 5%
        assertEq(
            flywheel.allocatedFee(multiTokenCampaign, address(token), bytes32(bytes20(attributionProvider))),
            expectedFee
        );
        assertEq(
            flywheel.allocatedFee(multiTokenCampaign, address(token2), bytes32(bytes20(attributionProvider))),
            expectedFee
        );

        // Collect fees for both tokens
        vm.startPrank(attributionProvider);
        flywheel.distributeFees(multiTokenCampaign, address(token), abi.encode(attributionProvider));
        flywheel.distributeFees(multiTokenCampaign, address(token2), abi.encode(attributionProvider));
        vm.stopPrank();

        // Verify attribution provider received fees in both tokens
        // Note: attribution provider started with 1000000e18 initial token balance, so add the fee to that
        assertEq(
            token.balanceOf(attributionProvider), 1000000e18 + expectedFee, "Should receive initial + fee for token1"
        );
        assertEq(token2.balanceOf(attributionProvider), expectedFee, "Should receive fee for token2");
    }

    // =============================================================
    //                    TOKENSTORE INTEGRATION
    // =============================================================

    function test_tokenStoreCloneDeployment() public {
        // Verify Campaign was cloned correctly
        assertTrue(campaign != address(0), "Campaign address should be non-zero");

        // Verify the campaign is a clone of the Campaign implementation
        // The campaign address should have code (cloned contract)
        uint256 codeSize;
        address campaignAddr = campaign;
        assembly {
            codeSize := extcodesize(campaignAddr)
        }
        assertTrue(codeSize > 0, "Campaign should have contract code");
    }

    function test_tokenStoreAccessControl() public {
        // Fund campaign first
        vm.prank(advertiser);
        token.transfer(campaign, INITIAL_BALANCE);

        // Try to call Campaign directly (should fail)
        vm.expectRevert();
        Campaign(payable(campaign)).sendTokens(address(token), advertiser, 100e18);

        // Only Flywheel should be able to call Campaign
        vm.prank(address(flywheel));
        Campaign(payable(campaign)).sendTokens(address(token), advertiser, 100e18);

        // Verify the transfer worked - advertiser should have received the tokens back
        // Note: advertiser's balance should have the 100e18 transferred back plus remaining initial balance
        uint256 expectedBalance = (1000000e18 - INITIAL_BALANCE) + 100e18; // Initial remaining + transfer
        assertEq(token.balanceOf(advertiser), expectedBalance, "Advertiser should receive transferred tokens");
    }

    // =============================================================
    //                    CAMPAIGN ADDRESS PREDICTION
    // =============================================================

    function test_predictCampaignAddress() public {
        // Create hook data for a new campaign
        string[] memory allowedRefs = new string[](0);
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] = AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://test.com"});

        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://test-campaign.com",
            allowedRefs,
            configs,
            7 days,
            ATTRIBUTION_FEE_BPS
        );

        // Predict the campaign address
        address predictedAddress = flywheel.predictCampaignAddress(address(hook), 999, hookData);

        // Create the campaign
        address actualAddress = flywheel.createCampaign(address(hook), 999, hookData);

        // Verify prediction was correct
        assertEq(predictedAddress, actualAddress, "Predicted address should match actual address");
    }

    function test_campaignAddressUniqueness() public {
        string[] memory allowedRefs = new string[](0);
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](0);

        bytes memory hookData1 =
            abi.encode(attributionProvider, advertiser, "campaign1", allowedRefs, configs, 7 days, ATTRIBUTION_FEE_BPS);
        bytes memory hookData2 =
            abi.encode(attributionProvider, advertiser, "campaign2", allowedRefs, configs, 7 days, ATTRIBUTION_FEE_BPS);

        // Same nonce, different data should produce different addresses
        address addr1 = flywheel.predictCampaignAddress(address(hook), 100, hookData1);
        address addr2 = flywheel.predictCampaignAddress(address(hook), 100, hookData2);
        assertTrue(addr1 != addr2, "Different hook data should produce different addresses");

        // Same data, different nonce should produce different addresses
        address addr3 = flywheel.predictCampaignAddress(address(hook), 101, hookData1);
        assertTrue(addr1 != addr3, "Different nonce should produce different addresses");
    }

    // =============================================================
    //                    EDGE CASE STATUS TRANSITIONS
    // =============================================================

    function test_invalidStatusTransitions() public {
        // Go to ACTIVE first
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Try to update to same status (this should fail at Flywheel level)
        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Move to FINALIZING
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Move to FINALIZED
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");

        // Try to change from FINALIZED (should fail at Flywheel level)
        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
    }

    function test_statusUpdateWithHookData() public {
        // Test that hook receives the correct data on status updates
        bytes memory testData = "test_hook_data";

        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, testData);

        // Verify status was updated
        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(Flywheel.CampaignStatus.ACTIVE));
    }

    function test_finalizedStatusImmutable() public {
        // Move to FINALIZED status
        vm.startPrank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");
        vm.stopPrank();

        // Try to change status from FINALIZED (should fail)
        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
    }

    // =============================================================
    //               COMPREHENSIVE PAYOUT FUNCTION TESTING
    // =============================================================

    function test_feeHandling_inAllocateDistributeOperations() public {
        // Test fee handling across allocate/distribute operations with CashbackRewards
        // Deploy CashbackRewards hook that charges no fees but supports full workflow

        address[] memory holders = new address[](1);
        holders[0] = advertiser;
        DummyERC20 feeToken = new DummyERC20(holders);

        // Transfer tokens for campaign funding
        vm.prank(advertiser);
        feeToken.transfer(advertiser, 1000e18);

        // Since CashbackRewards doesn't support fee operations, test with SimpleRewards
        SimpleRewards feeHook = new SimpleRewards(address(flywheel));
        address feeManager = address(0x9100);

        bytes memory hookData = abi.encode(feeManager, feeManager, "");
        address feeCampaign = flywheel.createCampaign(address(feeHook), 200, hookData);

        // Fund campaign
        vm.prank(advertiser);
        feeToken.transfer(feeCampaign, 500e18);

        // Activate campaign
        vm.prank(feeManager);
        flywheel.updateStatus(feeCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        address recipient = address(0x8100);

        // Test allocate operation (no fees expected with SimpleRewards)
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: recipient, amount: 100e18, extraData: "fee-test-allocation"});

        vm.prank(feeManager);
        (Flywheel.Allocation[] memory allocateResult) =
            flywheel.allocate(feeCampaign, address(feeToken), abi.encode(payouts));

        // Verify no fees charged during allocation (SimpleRewards has no fees)
        assertEq(allocateResult.length, 1);
        assertEq(allocateResult[0].amount, 100e18);

        // Test distribute operation
        vm.prank(feeManager);
        (
            Flywheel.Distribution[] memory distributeResult,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        ) = flywheel.distribute(feeCampaign, address(feeToken), abi.encode(payouts));

        // Verify no fees charged during distribution
        assertEq(immediateFees.length, 0);
        assertEq(delayedFees.length, 0);
        assertEq(distributeResult.length, 1);
        assertEq(distributeResult[0].amount, 100e18);

        // Verify tokens were transferred to recipient
        assertEq(feeToken.balanceOf(recipient), 100e18);
    }

    function test_multiToken_allocateDistribute_isolationTesting() public {
        // Test Campaign isolation with multiple tokens and allocate/distribute workflows
        SimpleRewards isolationHook = new SimpleRewards(address(flywheel));
        address isolationManager = address(0x9200);

        bytes memory hookData = abi.encode(isolationManager, isolationManager, "");
        address campaign1 = flywheel.createCampaign(address(isolationHook), 300, hookData);
        address campaign2 = flywheel.createCampaign(address(isolationHook), 301, hookData);

        // Deploy two different tokens
        address[] memory holders = new address[](1);
        holders[0] = isolationManager;
        DummyERC20 tokenA = new DummyERC20(holders);
        DummyERC20 tokenB = new DummyERC20(holders);

        // Fund both campaigns with both tokens
        vm.startPrank(isolationManager);
        tokenA.transfer(campaign1, 1000e18);
        tokenA.transfer(campaign2, 1000e18);
        tokenB.transfer(campaign1, 500e18);
        tokenB.transfer(campaign2, 500e18);

        // Activate both campaigns
        flywheel.updateStatus(campaign1, Flywheel.CampaignStatus.ACTIVE, "");
        flywheel.updateStatus(campaign2, Flywheel.CampaignStatus.ACTIVE, "");
        vm.stopPrank();

        address recipient1 = address(0x8200);
        address recipient2 = address(0x8201);

        // Test cross-campaign isolation during allocate/distribute
        Flywheel.Payout[] memory payouts1 = new Flywheel.Payout[](1);
        payouts1[0] = Flywheel.Payout({recipient: recipient1, amount: 200e18, extraData: "campaign1-isolation"});

        Flywheel.Payout[] memory payouts2 = new Flywheel.Payout[](1);
        payouts2[0] = Flywheel.Payout({recipient: recipient2, amount: 150e18, extraData: "campaign2-isolation"});

        // Allocate in both campaigns with both tokens
        vm.startPrank(isolationManager);
        flywheel.allocate(campaign1, address(tokenA), abi.encode(payouts1));
        flywheel.allocate(campaign1, address(tokenB), abi.encode(payouts1));
        flywheel.allocate(campaign2, address(tokenA), abi.encode(payouts2));
        flywheel.allocate(campaign2, address(tokenB), abi.encode(payouts2));
        vm.stopPrank();

        // Verify no cross-contamination before distribution
        assertEq(tokenA.balanceOf(recipient1), 0);
        assertEq(tokenA.balanceOf(recipient2), 0);
        assertEq(tokenB.balanceOf(recipient1), 0);
        assertEq(tokenB.balanceOf(recipient2), 0);

        // Distribute from campaign1 only
        vm.startPrank(isolationManager);
        flywheel.distribute(campaign1, address(tokenA), abi.encode(payouts1));
        flywheel.distribute(campaign1, address(tokenB), abi.encode(payouts1));
        vm.stopPrank();

        // Verify only campaign1 distributions occurred
        assertEq(tokenA.balanceOf(recipient1), 200e18, "Campaign1 recipient should receive tokenA");
        assertEq(tokenB.balanceOf(recipient1), 200e18, "Campaign1 recipient should receive tokenB");
        assertEq(tokenA.balanceOf(recipient2), 0, "Campaign2 recipient should not receive tokens yet");
        assertEq(tokenB.balanceOf(recipient2), 0, "Campaign2 recipient should not receive tokens yet");

        // Verify campaign balances remain isolated
        assertEq(tokenA.balanceOf(campaign1), 800e18, "Campaign1 tokenA balance should be reduced");
        assertEq(tokenB.balanceOf(campaign1), 300e18, "Campaign1 tokenB balance should be reduced");
        assertEq(tokenA.balanceOf(campaign2), 1000e18, "Campaign2 tokenA balance should be unchanged");
        assertEq(tokenB.balanceOf(campaign2), 500e18, "Campaign2 tokenB balance should be unchanged");

        // Now distribute from campaign2
        vm.startPrank(isolationManager);
        flywheel.distribute(campaign2, address(tokenA), abi.encode(payouts2));
        flywheel.distribute(campaign2, address(tokenB), abi.encode(payouts2));
        vm.stopPrank();

        // Verify final balances show complete isolation
        assertEq(tokenA.balanceOf(recipient1), 200e18, "Recipient1 tokenA should remain unchanged");
        assertEq(tokenB.balanceOf(recipient1), 200e18, "Recipient1 tokenB should remain unchanged");
        assertEq(tokenA.balanceOf(recipient2), 150e18, "Recipient2 should now receive tokenA");
        assertEq(tokenB.balanceOf(recipient2), 150e18, "Recipient2 should now receive tokenB");
    }

    function test_crossHookStateTransitionBehavior() public {
        // Test state transition behavior across different hook types

        // Deploy all three hook types
        SimpleRewards simpleHook = new SimpleRewards(address(flywheel));
        address manager = address(0x9300);

        // Create campaigns with different hooks
        bytes memory hookData = abi.encode(manager, manager, "");
        address simpleCampaign = flywheel.createCampaign(address(simpleHook), 400, hookData);

        // AdConversion campaign already exists from setUp()
        address adCampaign = campaign;

        // Test state transitions for SimpleRewards (Manager-controlled)
        vm.startPrank(manager);

        // Test all valid transitions for SimpleRewards
        assertEq(uint8(flywheel.campaignStatus(simpleCampaign)), uint8(Flywheel.CampaignStatus.INACTIVE));

        // INACTIVE → ACTIVE
        flywheel.updateStatus(simpleCampaign, Flywheel.CampaignStatus.ACTIVE, "simple-activation");
        assertEq(uint8(flywheel.campaignStatus(simpleCampaign)), uint8(Flywheel.CampaignStatus.ACTIVE));

        // ACTIVE → INACTIVE (pause) - SimpleRewards allows all transitions for manager
        flywheel.updateStatus(simpleCampaign, Flywheel.CampaignStatus.INACTIVE, "simple-pause");
        assertEq(uint8(flywheel.campaignStatus(simpleCampaign)), uint8(Flywheel.CampaignStatus.INACTIVE));

        // INACTIVE → FINALIZING (transition from paused state)
        flywheel.updateStatus(simpleCampaign, Flywheel.CampaignStatus.FINALIZING, "simple-finalizing");
        assertEq(uint8(flywheel.campaignStatus(simpleCampaign)), uint8(Flywheel.CampaignStatus.FINALIZING));

        // FINALIZING → FINALIZED (FINALIZING → ACTIVE is not allowed by core Flywheel)
        flywheel.updateStatus(simpleCampaign, Flywheel.CampaignStatus.FINALIZED, "simple-finalized");
        assertEq(uint8(flywheel.campaignStatus(simpleCampaign)), uint8(Flywheel.CampaignStatus.FINALIZED));

        vm.stopPrank();

        // Test AdConversion state transitions (Attribution Provider controlled)
        vm.startPrank(attributionProvider);

        // Ad campaign starts INACTIVE
        assertEq(uint8(flywheel.campaignStatus(adCampaign)), uint8(Flywheel.CampaignStatus.INACTIVE));

        // INACTIVE → ACTIVE
        flywheel.updateStatus(adCampaign, Flywheel.CampaignStatus.ACTIVE, "ad-activation");
        assertEq(uint8(flywheel.campaignStatus(adCampaign)), uint8(Flywheel.CampaignStatus.ACTIVE));

        // ACTIVE → INACTIVE (pause) - NO LONGER ALLOWED for attribution providers (security improvement)
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(adCampaign, Flywheel.CampaignStatus.INACTIVE, "ad-pause");

        // Campaign remains ACTIVE after failed pause attempt
        assertEq(uint8(flywheel.campaignStatus(adCampaign)), uint8(Flywheel.CampaignStatus.ACTIVE));

        // Attribution provider can still do ACTIVE → FINALIZING
        flywheel.updateStatus(adCampaign, Flywheel.CampaignStatus.FINALIZING, "ad-finalizing");
        assertEq(uint8(flywheel.campaignStatus(adCampaign)), uint8(Flywheel.CampaignStatus.FINALIZING));

        vm.stopPrank();

        // Test that advertiser cannot do FINALIZING → FINALIZED without waiting (should work for attribution provider)
        // Note: We can't test FINALIZING → ACTIVE as that's blocked by core Flywheel state machine

        // Attribution provider can finalize from FINALIZING
        vm.prank(attributionProvider);
        flywheel.updateStatus(adCampaign, Flywheel.CampaignStatus.FINALIZED, "ad-finalized");
        assertEq(uint8(flywheel.campaignStatus(adCampaign)), uint8(Flywheel.CampaignStatus.FINALIZED));
    }

    function test_stateDependentPayoutFunctionAvailability() public {
        // Test that payout functions are only available in appropriate states
        SimpleRewards stateHook = new SimpleRewards(address(flywheel));
        address stateManager = address(0x9400);

        bytes memory hookData = abi.encode(stateManager, stateManager, "");
        address stateCampaign = flywheel.createCampaign(address(stateHook), 500, hookData);

        // Fund campaign
        vm.prank(advertiser);
        token.transfer(stateCampaign, 1000e18);

        address recipient = address(0x8400);
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: recipient, amount: 100e18, extraData: "state-test"});

        // Test INACTIVE state - no payout functions should work
        assertEq(uint8(flywheel.campaignStatus(stateCampaign)), uint8(Flywheel.CampaignStatus.INACTIVE));

        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(stateManager);
        flywheel.send(stateCampaign, address(token), abi.encode(payouts));

        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(stateManager);
        flywheel.allocate(stateCampaign, address(token), abi.encode(payouts));

        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(stateManager);
        flywheel.distribute(stateCampaign, address(token), abi.encode(payouts));

        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(stateManager);
        flywheel.deallocate(stateCampaign, address(token), abi.encode(payouts));

        // Activate campaign - all payout functions should work
        vm.prank(stateManager);
        flywheel.updateStatus(stateCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Test all payout functions in ACTIVE state
        vm.startPrank(stateManager);
        flywheel.send(stateCampaign, address(token), abi.encode(payouts));

        // Test allocate/distribute/deallocate cycle properly
        flywheel.allocate(stateCampaign, address(token), abi.encode(payouts));
        flywheel.distribute(stateCampaign, address(token), abi.encode(payouts));

        // Allocate again before deallocate (since distribute consumed the allocation)
        flywheel.allocate(stateCampaign, address(token), abi.encode(payouts));
        flywheel.deallocate(stateCampaign, address(token), abi.encode(payouts));
        vm.stopPrank();

        // Move to FINALIZING - payout functions should still work
        vm.prank(stateManager);
        flywheel.updateStatus(stateCampaign, Flywheel.CampaignStatus.FINALIZING, "");

        vm.startPrank(stateManager);
        flywheel.send(stateCampaign, address(token), abi.encode(payouts));

        // Test allocate/distribute/deallocate cycle properly in FINALIZING state
        flywheel.allocate(stateCampaign, address(token), abi.encode(payouts));
        flywheel.distribute(stateCampaign, address(token), abi.encode(payouts));

        // Allocate again before deallocate
        flywheel.allocate(stateCampaign, address(token), abi.encode(payouts));
        flywheel.deallocate(stateCampaign, address(token), abi.encode(payouts));
        vm.stopPrank();

        // Move to FINALIZED - no payout functions should work
        vm.prank(stateManager);
        flywheel.updateStatus(stateCampaign, Flywheel.CampaignStatus.FINALIZED, "");

        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(stateManager);
        flywheel.send(stateCampaign, address(token), abi.encode(payouts));

        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(stateManager);
        flywheel.allocate(stateCampaign, address(token), abi.encode(payouts));

        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(stateManager);
        flywheel.distribute(stateCampaign, address(token), abi.encode(payouts));

        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(stateManager);
        flywheel.deallocate(stateCampaign, address(token), abi.encode(payouts));
    }

    function test_tokenStore_clonePatternEfficiency() public {
        // Test Campaign clone pattern efficiency and isolation

        // Deploy multiple campaigns to test clone efficiency
        SimpleRewards cloneHook = new SimpleRewards(address(flywheel));
        address cloneManager = address(0x9500);

        bytes memory hookData = abi.encode(cloneManager, cloneManager, "");

        // Create multiple campaigns and measure clone efficiency
        address[] memory campaigns = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            campaigns[i] = flywheel.createCampaign(address(cloneHook), 600 + i, hookData);

            // Verify each campaign has contract code (is a clone)
            uint256 codeSize;
            address campaignAddr = campaigns[i];
            assembly {
                codeSize := extcodesize(campaignAddr)
            }
            assertTrue(codeSize > 0, "Campaign should have contract code from clone");

            // Verify each campaign address is unique
            for (uint256 j = 0; j < i; j++) {
                assertTrue(campaigns[i] != campaigns[j], "Campaign addresses should be unique");
            }
        }
    }

    function test_tokenStore_withdrawalPermissionValidation() public {
        // Test withdrawal permissions are properly validated per hook type

        // Test with SimpleRewards (Manager withdrawal)
        SimpleRewards withdrawHook = new SimpleRewards(address(flywheel));
        address withdrawManager = address(0x9600);

        bytes memory hookData = abi.encode(withdrawManager, withdrawManager, "");
        address withdrawCampaign = flywheel.createCampaign(address(withdrawHook), 700, hookData);

        // Fund campaign
        vm.prank(advertiser);
        token.transfer(withdrawCampaign, 500e18);

        // Finalize campaign
        vm.startPrank(withdrawManager);
        flywheel.updateStatus(withdrawCampaign, Flywheel.CampaignStatus.ACTIVE, "");
        flywheel.updateStatus(withdrawCampaign, Flywheel.CampaignStatus.FINALIZING, "");
        flywheel.updateStatus(withdrawCampaign, Flywheel.CampaignStatus.FINALIZED, "");
        vm.stopPrank();

        uint256 campaignBalance = token.balanceOf(withdrawCampaign);
        assertEq(campaignBalance, 500e18, "Campaign should have funded balance");

        // Test unauthorized withdrawal fails
        vm.expectRevert();
        vm.prank(advertiser); // Not the manager
        flywheel.withdrawFunds(
            withdrawCampaign,
            address(token),
            abi.encode(Flywheel.Payout({recipient: advertiser, amount: campaignBalance, extraData: ""}))
        );

        // Test authorized manager withdrawal succeeds
        uint256 managerBalanceBefore = token.balanceOf(withdrawManager);
        vm.prank(withdrawManager);
        flywheel.withdrawFunds(
            withdrawCampaign,
            address(token),
            abi.encode(Flywheel.Payout({recipient: withdrawManager, amount: campaignBalance, extraData: ""}))
        );

        uint256 managerBalanceAfter = token.balanceOf(withdrawManager);
        assertEq(managerBalanceAfter - managerBalanceBefore, campaignBalance, "Manager should receive withdrawal");
        assertEq(token.balanceOf(withdrawCampaign), 0, "Campaign balance should be zero after withdrawal");
    }

    function test_distribute_coreFlywheelFunctionality() public {
        // Deploy SimpleRewards hook that supports all payout functions
        SimpleRewards simpleHook = new SimpleRewards(address(flywheel));
        address manager = address(0x9000);

        // Create campaign with SimpleRewards hook
        bytes memory hookData = abi.encode(manager, manager, "");
        address simpleCampaign = flywheel.createCampaign(address(simpleHook), 100, hookData);

        // Deploy second token for multi-token testing
        address[] memory holders = new address[](1);
        holders[0] = manager;
        DummyERC20 token2 = new DummyERC20(holders);

        // Transfer tokens to manager for funding campaign
        vm.prank(advertiser);
        token.transfer(manager, 2000e18);

        // Fund campaign with both tokens
        vm.startPrank(manager);
        token.transfer(simpleCampaign, 1000e18);
        token2.transfer(simpleCampaign, 1000e6); // Different decimals (6 vs 18)

        // Activate campaign
        flywheel.updateStatus(simpleCampaign, Flywheel.CampaignStatus.ACTIVE, "");
        vm.stopPrank();

        // Test distribute() function with first token
        address recipient1 = address(0x8001);
        address recipient2 = address(0x8002);

        // Create payout data for allocation
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](2);
        payouts[0] = Flywheel.Payout({recipient: recipient1, amount: 100e18, extraData: "allocation-1"});
        payouts[1] = Flywheel.Payout({recipient: recipient2, amount: 150e18, extraData: "allocation-2"});

        // Step 1: Allocate tokens (reserve for future distribution)
        vm.prank(manager);
        flywheel.allocate(simpleCampaign, address(token), abi.encode(payouts));

        // Verify tokens not transferred yet
        assertEq(token.balanceOf(recipient1), 0);
        assertEq(token.balanceOf(recipient2), 0);

        // Step 2: Test distribute() - the core missing functionality
        vm.prank(manager);
        (
            Flywheel.Distribution[] memory distributionsResult,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        ) = flywheel.distribute(simpleCampaign, address(token), abi.encode(payouts));

        // Verify distribute() results
        assertEq(distributionsResult.length, 2);
        assertEq(distributionsResult[0].recipient, recipient1);
        assertEq(distributionsResult[0].amount, 100e18);
        assertEq(distributionsResult[1].recipient, recipient2);
        assertEq(distributionsResult[1].amount, 150e18);
        // SimpleRewards has no fees
        assertEq(immediateFees.length, 0);
        assertEq(delayedFees.length, 0);

        // Verify tokens were transferred
        assertEq(token.balanceOf(recipient1), 100e18);
        assertEq(token.balanceOf(recipient2), 150e18);
    }

    function test_multiToken_allocateDistributeWorkflow() public {
        // Deploy SimpleRewards hook for multi-token testing
        SimpleRewards simpleHook = new SimpleRewards(address(flywheel));
        address manager = address(0x9001);

        // Create campaign
        bytes memory hookData = abi.encode(manager, manager, "");
        address multiTokenCampaign = flywheel.createCampaign(address(simpleHook), 101, hookData);

        // Deploy additional tokens with different decimals
        address[] memory holders = new address[](1);
        holders[0] = manager;
        DummyERC20 usdc = new DummyERC20(holders); // 6 decimals
        DummyERC20 weth = new DummyERC20(holders); // 18 decimals (from DummyERC20 default)

        // Transfer tokens to manager for funding campaign
        vm.prank(advertiser);
        token.transfer(manager, 1000e18);

        // Fund campaign with multiple tokens
        vm.startPrank(manager);
        token.transfer(multiTokenCampaign, 1000e18);
        usdc.transfer(multiTokenCampaign, 1000e6);
        weth.transfer(multiTokenCampaign, 5e18);

        flywheel.updateStatus(multiTokenCampaign, Flywheel.CampaignStatus.ACTIVE, "");
        vm.stopPrank();

        address recipient = address(0x8003);

        // Test allocate/distribute workflow across multiple tokens

        // Token 1: Original token (18 decimals)
        Flywheel.Payout[] memory tokanPayouts = new Flywheel.Payout[](1);
        tokanPayouts[0] = Flywheel.Payout({recipient: recipient, amount: 200e18, extraData: "token-allocation"});

        vm.prank(manager);
        flywheel.allocate(multiTokenCampaign, address(token), abi.encode(tokanPayouts));

        // Token 2: USDC (6 decimals)
        Flywheel.Payout[] memory usdcPayouts = new Flywheel.Payout[](1);
        usdcPayouts[0] = Flywheel.Payout({recipient: recipient, amount: 100e6, extraData: "usdc-allocation"});

        vm.prank(manager);
        flywheel.allocate(multiTokenCampaign, address(usdc), abi.encode(usdcPayouts));

        // Token 3: WETH (18 decimals)
        Flywheel.Payout[] memory wethPayouts = new Flywheel.Payout[](1);
        wethPayouts[0] = Flywheel.Payout({recipient: recipient, amount: 1e18, extraData: "weth-allocation"});

        vm.prank(manager);
        flywheel.allocate(multiTokenCampaign, address(weth), abi.encode(wethPayouts));

        // Verify no tokens transferred yet (allocation phase)
        assertEq(token.balanceOf(recipient), 0);
        assertEq(usdc.balanceOf(recipient), 0);
        assertEq(weth.balanceOf(recipient), 0);

        // Now distribute each token allocation

        vm.prank(manager);
        flywheel.distribute(multiTokenCampaign, address(token), abi.encode(tokanPayouts));

        vm.prank(manager);
        flywheel.distribute(multiTokenCampaign, address(usdc), abi.encode(usdcPayouts));

        vm.prank(manager);
        flywheel.distribute(multiTokenCampaign, address(weth), abi.encode(wethPayouts));

        // Verify all tokens were distributed correctly
        assertEq(token.balanceOf(recipient), 200e18);
        assertEq(usdc.balanceOf(recipient), 100e6);
        assertEq(weth.balanceOf(recipient), 1e18);

        // Verify campaign balances reduced
        assertEq(token.balanceOf(multiTokenCampaign), 800e18);
        assertEq(usdc.balanceOf(multiTokenCampaign), 900e6);
        assertEq(weth.balanceOf(multiTokenCampaign), 4e18);
    }

    function test_allocateDistribute_complexWorkflows() public {
        // Test complex allocate→distribute workflows with partial distributions
        SimpleRewards simpleHook = new SimpleRewards(address(flywheel));
        address manager = address(0x9002);

        bytes memory hookData = abi.encode(manager, manager, "");
        address complexCampaign = flywheel.createCampaign(address(simpleHook), 102, hookData);

        // Transfer tokens to manager for funding campaign
        vm.prank(advertiser);
        token.transfer(manager, 1000e18);

        // Fund and activate campaign
        vm.startPrank(manager);
        token.transfer(complexCampaign, 1000e18);
        flywheel.updateStatus(complexCampaign, Flywheel.CampaignStatus.ACTIVE, "");
        vm.stopPrank();

        address recipient1 = address(0x8004);
        address recipient2 = address(0x8005);
        address recipient3 = address(0x8006);

        // Phase 1: Large allocation
        Flywheel.Payout[] memory largeAllocation = new Flywheel.Payout[](3);
        largeAllocation[0] = Flywheel.Payout({recipient: recipient1, amount: 100e18, extraData: ""});
        largeAllocation[1] = Flywheel.Payout({recipient: recipient2, amount: 200e18, extraData: ""});
        largeAllocation[2] = Flywheel.Payout({recipient: recipient3, amount: 300e18, extraData: ""});

        vm.prank(manager);
        flywheel.allocate(complexCampaign, address(token), abi.encode(largeAllocation));

        // Phase 2: Partial distribution (only first two recipients)
        Flywheel.Payout[] memory partialDistribution = new Flywheel.Payout[](2);
        partialDistribution[0] = Flywheel.Payout({recipient: recipient1, amount: 100e18, extraData: ""});
        partialDistribution[1] = Flywheel.Payout({recipient: recipient2, amount: 200e18, extraData: ""});

        vm.prank(manager);
        flywheel.distribute(complexCampaign, address(token), abi.encode(partialDistribution));

        // Verify partial distribution
        assertEq(token.balanceOf(recipient1), 100e18);
        assertEq(token.balanceOf(recipient2), 200e18);
        assertEq(token.balanceOf(recipient3), 0); // Not distributed yet

        // Phase 3: Distribute remaining allocation to third recipient
        Flywheel.Payout[] memory remainingDistribution = new Flywheel.Payout[](1);
        remainingDistribution[0] = Flywheel.Payout({recipient: recipient3, amount: 300e18, extraData: ""});

        vm.prank(manager);
        flywheel.distribute(complexCampaign, address(token), abi.encode(remainingDistribution));

        // Verify complete distribution
        assertEq(token.balanceOf(recipient1), 100e18);
        assertEq(token.balanceOf(recipient2), 200e18);
        assertEq(token.balanceOf(recipient3), 300e18);

        // Verify campaign balance
        assertEq(token.balanceOf(complexCampaign), 400e18); // 1000 - 600 distributed
    }

    function test_distribute_errorConditions() public {
        // Test error conditions specific to distribute function in core Flywheel
        SimpleRewards simpleHook = new SimpleRewards(address(flywheel));
        address manager = address(0x9003);

        bytes memory hookData = abi.encode(manager, manager, "");
        address errorCampaign = flywheel.createCampaign(address(simpleHook), 103, hookData);

        // Transfer tokens to manager for funding campaign
        vm.prank(advertiser);
        token.transfer(manager, 500e18);

        // Fund campaign
        vm.prank(manager);
        token.transfer(errorCampaign, 500e18);

        // Test 1: Cannot distribute on INACTIVE campaign

        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: address(0x8007), amount: 100e18, extraData: ""});

        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(manager);
        flywheel.distribute(errorCampaign, address(token), abi.encode(payouts));

        // Activate campaign for further tests
        vm.prank(manager);
        flywheel.updateStatus(errorCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Test 2: Successful allocate and distribute in ACTIVE state
        // First allocate
        vm.prank(manager);
        flywheel.allocate(errorCampaign, address(token), abi.encode(payouts));

        // Then distribute
        vm.prank(manager);
        flywheel.distribute(errorCampaign, address(token), abi.encode(payouts));
        assertEq(token.balanceOf(address(0x8007)), 100e18);

        // Test 3: Distribute in FINALIZING state (should work)
        vm.prank(manager);
        flywheel.updateStatus(errorCampaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Allocate first for FINALIZING state test
        payouts[0].recipient = address(0x8008);
        vm.prank(manager);
        flywheel.allocate(errorCampaign, address(token), abi.encode(payouts));

        // Then distribute
        payouts[0].recipient = address(0x8008);
        vm.prank(manager);
        flywheel.distribute(errorCampaign, address(token), abi.encode(payouts));
        assertEq(token.balanceOf(address(0x8008)), 100e18);

        // Test 4: Cannot distribute on FINALIZED campaign
        vm.prank(manager);
        flywheel.updateStatus(errorCampaign, Flywheel.CampaignStatus.FINALIZED, "");

        payouts[0].recipient = address(0x8009);
        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(manager);
        flywheel.distribute(errorCampaign, address(token), abi.encode(payouts));
    }

    // =============================================================
    //                    EVENT LOGGING TESTS
    // =============================================================

    function test_createCampaign_emitsCampaignCreatedEvent() public {
        string[] memory allowedRefs = new string[](0);
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](0);

        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, "https://example.com/test-campaign", allowedRefs, configs, 7 days
        );

        address expectedCampaign = flywheel.predictCampaignAddress(address(hook), 999, hookData);

        // Expect the Flywheel CampaignCreated event
        vm.expectEmit(true, false, false, true);
        emit Flywheel.CampaignCreated(expectedCampaign, address(hook));

        // Create campaign
        address newCampaign = flywheel.createCampaign(address(hook), 999, hookData);
        assertEq(newCampaign, expectedCampaign);
    }

    function test_updateStatus_emitsCampaignStatusUpdatedEvent() public {
        // Expect the status update event
        vm.expectEmit(true, false, false, true);
        emit Flywheel.CampaignStatusUpdated(
            campaign, attributionProvider, Flywheel.CampaignStatus.INACTIVE, Flywheel.CampaignStatus.ACTIVE
        );

        // Update status to ACTIVE
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
    }

    function test_send_emitsPayoutSentEvent() public {
        // Set attribution provider fee and create new campaign for this test
        vm.prank(attributionProvider);
        // Attribution fee is now set during campaign creation

        // Create new campaign with fee cached
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://example.com/offchain"});
        configs[1] =
            AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: "https://example.com/onchain"});
        string[] memory allowedRefCodes = new string[](0);
        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://example.com/campaign",
            allowedRefCodes,
            configs,
            7 days,
            ATTRIBUTION_FEE_BPS
        );
        address testCampaign = flywheel.createCampaign(address(hook), 105, hookData);

        // Activate campaign first
        vm.prank(attributionProvider);
        flywheel.updateStatus(testCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Fund campaign by transferring tokens directly to the Campaign
        vm.prank(advertiser);
        token.transfer(testCampaign, INITIAL_BALANCE);

        // Create attribution
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 0,
                publisherRefCode: "code1",
                timestamp: uint32(block.timestamp),
                payoutRecipient: address(0),
                payoutAmount: 100e18
            }),
            logBytes: ""
        });

        bytes memory attributionData = abi.encode(attributions);

        // Expect the payout rewarded event
        vm.expectEmit(true, false, false, true);
        emit Flywheel.PayoutSent(testCampaign, address(token), publisher1Payout, 95e18, ""); // Amount minus 5% fee

        // Process attribution with reward
        vm.prank(attributionProvider);
        flywheel.send(testCampaign, address(token), attributionData);
    }
}
