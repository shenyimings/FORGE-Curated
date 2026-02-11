// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Flywheel} from "../../src/Flywheel.sol";
import {AdConversion} from "../../src/hooks/AdConversion.sol";
import {BuilderCodes} from "../../src/BuilderCodes.sol";
import {DummyERC20} from "../mocks/DummyERC20.sol";

import {PublisherTestSetup, PublisherSetupHelper} from "../helpers/PublisherSetupHelper.sol";

contract AdFlowTest is PublisherTestSetup {
    // Contracts
    Flywheel public flywheel;
    BuilderCodes public publisherRegistry;
    AdConversion public adHook;
    DummyERC20 public usdc;

    // Test accounts
    address public advertiser = makeAddr("advertiser");
    address public provider = makeAddr("provider");
    address public publisher1 = makeAddr("publisher1");
    address public publisher2 = makeAddr("publisher2");
    address public owner = makeAddr("owner");
    address public signer = makeAddr("signer");

    // Campaign details
    address public campaign;
    uint256 public constant CAMPAIGN_NONCE = 1;
    uint256 public constant INITIAL_FUNDING = 10000 * 1e6; // 10,000 USDC
    uint256 public constant ATTRIBUTION_AMOUNT = 100 * 1e6; // 100 USDC per attribution
    uint16 public constant ATTRIBUTION_FEE_BPS = 500; // 5%

    // Publisher ref codes
    string public constant pub1RefCode = "ref1";
    string public constant pub2RefCode = "ref2";

    function setUp() public {
        // Deploy token with initial balances
        address[] memory initialHolders = new address[](2);
        initialHolders[0] = advertiser;
        initialHolders[1] = provider;
        usdc = new DummyERC20(initialHolders);

        // Deploy Flywheel
        flywheel = new Flywheel();

        // Deploy publisher registry
        BuilderCodes impl = new BuilderCodes();
        bytes memory initData = abi.encodeWithSelector(
            BuilderCodes.initialize.selector,
            owner,
            signer, // signer address
            "" // empty baseURI
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        publisherRegistry = BuilderCodes(address(proxy));

        // Deploy ad conversion hook
        adHook = new AdConversion(address(flywheel), owner, address(publisherRegistry));

        // Register publishers
        _registerPublishers();

        // Attribution fee is now set during campaign creation

        // Create campaign
        _createCampaign();

        // Fund campaign
        _fundCampaign();
    }

    function _registerPublishers() internal {
        vm.prank(owner);
        publisherRegistry.register(pub1RefCode, publisher1, publisher1);

        // Register publisher 2 with different chain overrides
        vm.prank(owner);
        publisherRegistry.register(pub2RefCode, publisher2, publisher2);

        console2.log("Publisher 1 ref code:", string(abi.encodePacked(pub1RefCode)));
        console2.log("Publisher 2 ref code:", string(abi.encodePacked(pub2RefCode)));
    }

    function _createCampaign() internal {
        // Prepare hook data for campaign creation (empty allowlist means all publishers allowed)
        string[] memory allowedRefCodes = new string[](0);

        // Create conversion configs
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] = AdConversion.ConversionConfigInput({
            isEventOnchain: false,
            metadataURI: "https://campaign.com/offchain-metadata"
        });
        configs[1] = AdConversion.ConversionConfigInput({
            isEventOnchain: true,
            metadataURI: "https://campaign.com/onchain-metadata"
        });

        bytes memory hookData = abi.encode(
            provider, advertiser, "https://campaign.com/metadata", allowedRefCodes, configs, 7 days, ATTRIBUTION_FEE_BPS
        );

        // Create campaign
        campaign = flywheel.createCampaign(address(adHook), CAMPAIGN_NONCE, hookData);

        console2.log("Campaign created at:", campaign);
    }

    function _fundCampaign() internal {
        // Fund campaign with USDC
        vm.startPrank(advertiser);
        usdc.transfer(campaign, INITIAL_FUNDING);
        vm.stopPrank();

        console2.log("Campaign funded with:", INITIAL_FUNDING);
    }

    function test_endToEndAdFlow() public {
        // 1. Verify initial setup
        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(Flywheel.CampaignStatus.INACTIVE));
        assertEq(usdc.balanceOf(campaign), INITIAL_FUNDING);
        assertEq(usdc.balanceOf(publisher1), 0);
        assertEq(usdc.balanceOf(publisher2), 0);

        // 2. Open campaign
        vm.startPrank(provider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        vm.stopPrank();

        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(Flywheel.CampaignStatus.ACTIVE));

        // 3. Create attributions
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](2);

        // Attribution for publisher 1
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click_123",
                configId: 1,
                publisherRefCode: pub1RefCode,
                timestamp: uint32(block.timestamp),
                payoutRecipient: publisher1,
                payoutAmount: ATTRIBUTION_AMOUNT
            }),
            logBytes: "" // Offchain conversion
        });

        // Attribution for publisher 2
        attributions[1] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(2)),
                clickId: "click_456",
                configId: 1,
                publisherRefCode: pub2RefCode,
                timestamp: uint32(block.timestamp),
                payoutRecipient: publisher2,
                payoutAmount: ATTRIBUTION_AMOUNT
            }),
            logBytes: "" // Offchain conversion
        });

        // 4. Process attributions
        vm.startPrank(provider);
        bytes memory attributionData = abi.encode(attributions);
        flywheel.send(campaign, address(usdc), attributionData);
        vm.stopPrank();

        // 5. Verify attributions were processed
        uint256 expectedPayoutAmount = ATTRIBUTION_AMOUNT - (ATTRIBUTION_AMOUNT * ATTRIBUTION_FEE_BPS / 10000);
        uint256 expectedFeeAmount = ATTRIBUTION_AMOUNT * ATTRIBUTION_FEE_BPS / 10000;

        // With reward(), payments are sent immediately, so check balances
        assertEq(usdc.balanceOf(publisher1), expectedPayoutAmount);
        assertEq(usdc.balanceOf(publisher2), expectedPayoutAmount);
        assertEq(flywheel.allocatedFee(campaign, address(usdc), bytes32(bytes20(provider))), expectedFeeAmount * 2);

        // 6. Provider collects fees
        vm.startPrank(provider);
        flywheel.distributeFees(campaign, address(usdc), abi.encode(provider));
        vm.stopPrank();

        assertEq(usdc.balanceOf(provider), 1000000 * 1e18 + expectedFeeAmount * 2); // Initial balance + fees

        // 7. Close campaign
        vm.startPrank(provider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        vm.stopPrank();

        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(Flywheel.CampaignStatus.FINALIZING));

        // 8. Finalize campaign
        vm.startPrank(provider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");
        vm.stopPrank();

        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(Flywheel.CampaignStatus.FINALIZED));

        // 9. Withdraw remaining funds
        uint256 remainingFunds = usdc.balanceOf(campaign);
        vm.startPrank(advertiser);
        flywheel.withdrawFunds(campaign, address(usdc), abi.encode(advertiser, remainingFunds));
        vm.stopPrank();

        assertEq(usdc.balanceOf(campaign), 0);
        console2.log("Test completed successfully!");
    }

    function test_onchainConversion() public {
        // Open campaign
        vm.startPrank(provider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        vm.stopPrank();

        // Create onchain attribution with log data
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);

        AdConversion.Log memory logData =
            AdConversion.Log({chainId: block.chainid, transactionHash: keccak256("test_tx"), index: 0});

        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "onchain_click_123",
                configId: 2,
                publisherRefCode: pub1RefCode,
                timestamp: uint32(block.timestamp),
                payoutRecipient: publisher1,
                payoutAmount: ATTRIBUTION_AMOUNT
            }),
            logBytes: abi.encode(logData)
        });

        // Process onchain attribution
        vm.startPrank(provider);
        bytes memory attributionData = abi.encode(attributions);

        // Expect OnchainConversion event
        vm.expectEmit(true, false, false, true);
        emit AdConversion.OnchainConversionProcessed(campaign, false, attributions[0].conversion, logData);

        flywheel.send(campaign, address(usdc), attributionData);
        vm.stopPrank();

        // Verify attribution processed correctly
        uint256 expectedPayoutAmount = ATTRIBUTION_AMOUNT - (ATTRIBUTION_AMOUNT * ATTRIBUTION_FEE_BPS / 10000);
        assertEq(usdc.balanceOf(publisher1), expectedPayoutAmount);
    }

    function test_unauthorizedAccessReverts() public {
        // Try to update status as unauthorized user
        vm.startPrank(makeAddr("unauthorized"));
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        vm.stopPrank();

        // Open the campaign properly first
        vm.startPrank(provider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        vm.stopPrank();

        // Try to allocate as unauthorized provider
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click_123",
                configId: 1,
                publisherRefCode: pub1RefCode,
                timestamp: uint32(block.timestamp),
                payoutRecipient: publisher1,
                payoutAmount: ATTRIBUTION_AMOUNT
            }),
            logBytes: ""
        });

        vm.startPrank(makeAddr("unauthorized_provider"));
        bytes memory attributionData = abi.encode(attributions);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.send(campaign, address(usdc), attributionData);
        vm.stopPrank();

        // Try to withdraw funds as unauthorized user
        address unauthorized = makeAddr("unauthorized");
        vm.startPrank(unauthorized);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        flywheel.withdrawFunds(campaign, address(usdc), abi.encode(unauthorized, 100));
        vm.stopPrank();
    }

    function test_advertiserCanWithdrawToDifferentAddress() public {
        // Use the existing campaign from setUp
        // Fund the campaign first
        vm.prank(advertiser);
        usdc.transfer(campaign, INITIAL_FUNDING);

        // Finalize campaign (advertiser can do INACTIVE → FINALIZED directly for fund recovery)
        vm.startPrank(advertiser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");
        vm.stopPrank();

        // Advertiser can withdraw to a different address (unlike SimpleRewards)
        address differentAddress = makeAddr("beneficiary");
        uint256 remainingFunds = usdc.balanceOf(campaign);
        uint256 beneficiaryBalanceBefore = usdc.balanceOf(differentAddress);

        vm.startPrank(advertiser);
        flywheel.withdrawFunds(campaign, address(usdc), abi.encode(differentAddress, remainingFunds));
        vm.stopPrank();

        // Verify funds went to the different address
        assertEq(usdc.balanceOf(differentAddress), beneficiaryBalanceBefore + remainingFunds);
        assertEq(usdc.balanceOf(campaign), 0);
    }

    function test_conversionConfigManagement() public {
        // Test adding a new conversion config
        // Only advertiser can add conversion configs
        vm.startPrank(advertiser);
        vm.expectEmit(true, true, false, true);
        // The emitted config will have isActive: true
        emit AdConversion.ConversionConfigAdded(
            campaign,
            3,
            AdConversion.ConversionConfig({
                isActive: true,
                isEventOnchain: false,
                metadataURI: "https://campaign.com/new-config-metadata"
            })
        );
        adHook.addConversionConfig(
            campaign,
            AdConversion.ConversionConfigInput({
                isEventOnchain: false,
                metadataURI: "https://campaign.com/new-config-metadata"
            })
        );
        vm.stopPrank();

        // Verify the new config was added
        AdConversion.ConversionConfig memory retrievedConfig = adHook.getConversionConfig(campaign, 3);
        assertEq(retrievedConfig.isActive, true);
        assertEq(retrievedConfig.isEventOnchain, false);
        assertEq(retrievedConfig.metadataURI, "https://campaign.com/new-config-metadata");

        // Test disabling a conversion config
        vm.startPrank(advertiser);
        vm.expectEmit(true, true, false, true);
        emit AdConversion.ConversionConfigStatusChanged(campaign, 1, false);
        adHook.disableConversionConfig(campaign, 1);
        vm.stopPrank();

        // Verify the config was disabled
        AdConversion.ConversionConfig memory disabledConfig = adHook.getConversionConfig(campaign, 1);
        assertEq(disabledConfig.isActive, false);

        // Test that unauthorized users cannot manage configs
        vm.startPrank(makeAddr("unauthorized"));
        vm.expectRevert(AdConversion.Unauthorized.selector);
        adHook.addConversionConfig(
            campaign,
            AdConversion.ConversionConfigInput({
                isEventOnchain: false,
                metadataURI: "https://campaign.com/unauthorized-config"
            })
        );

        vm.expectRevert(AdConversion.Unauthorized.selector);
        adHook.disableConversionConfig(campaign, 2);
        vm.stopPrank();

        // Test that disabled config still works in attribution (by design)
        vm.startPrank(provider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        vm.stopPrank();

        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click_disabled_config",
                configId: 1, // This config was disabled but should still work
                publisherRefCode: pub1RefCode,
                timestamp: uint32(block.timestamp),
                payoutRecipient: publisher1,
                payoutAmount: ATTRIBUTION_AMOUNT
            }),
            logBytes: ""
        });

        vm.startPrank(provider);
        bytes memory attributionData = abi.encode(attributions);
        // Should succeed even with disabled config
        flywheel.send(campaign, address(usdc), attributionData);
        vm.stopPrank();

        console2.log("Conversion config management tests completed successfully!");
    }
}
