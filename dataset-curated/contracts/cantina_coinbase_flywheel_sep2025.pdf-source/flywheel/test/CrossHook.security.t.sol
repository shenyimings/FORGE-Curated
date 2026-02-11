// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

import {Flywheel} from "../src/Flywheel.sol";
import {CashbackRewards} from "../src/hooks/CashbackRewards.sol";
import {SimpleRewards} from "../src/hooks/SimpleRewards.sol";
import {AdConversion} from "../src/hooks/AdConversion.sol";
import {BuilderCodes} from "../src/BuilderCodes.sol";
import {DummyERC20} from "./mocks/DummyERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Cross-Hook Security & Integration Test Suite
/// @notice Comprehensive testing for cross-hook interactions: baseline functionality and security attacks
/// @dev Tests hook interoperability, cross-campaign workflows, and multi-hook security vulnerabilities
contract CrossHookSecurityTest is Test {
    // Core contracts
    Flywheel public flywheel;
    BuilderCodes public publisherRegistry;
    AuthCaptureEscrow public escrow;

    // Hook contracts
    AdConversion public adHook;
    CashbackRewards public buyerHook;
    SimpleRewards public simpleHook;

    // Tokens
    DummyERC20 public paymentToken; // USDC-like
    DummyERC20 public rewardToken; // Platform token
    DummyERC20 public bonusToken; // Bonus rewards

    // Test accounts
    address public owner = makeAddr("owner");
    address public signer = makeAddr("signer");

    // AdConversion actors
    address public advertiser = makeAddr("advertiser");
    address public attributionProvider = makeAddr("attributionProvider");
    address public publisher1 = makeAddr("publisher1");
    address public publisher2 = makeAddr("publisher2");

    // CashbackRewards actors
    address public ecommerceOwner = makeAddr("ecommerceOwner");
    address public paymentManager = makeAddr("paymentManager");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");

    // SimpleRewards actors
    address public daoManager = makeAddr("daoManager");
    address public contributor1 = makeAddr("contributor1");
    address public contributor2 = makeAddr("contributor2");

    // Security test actors
    address public attacker = makeAddr("attacker");
    address public victim = makeAddr("victim");
    address public merchant = makeAddr("merchant");

    // Legacy variable mappings for security tests
    address public simpleRewardsManager = daoManager;
    address public cashbackRewardsManager = paymentManager;
    address public manager = owner;
    DummyERC20 public token; // Alias for security tests

    // Campaign addresses
    address public adCampaign;
    address public buyerCampaign;
    address public simpleCampaign;

    // Constants
    uint256 public constant CAMPAIGN_FUNDING = 100000e18;
    uint256 public constant AD_PAYOUT = 1000e18;
    uint256 public constant CASHBACK_AMOUNT = 500e18;
    uint256 public constant DAO_REWARD = 2000e18;
    uint16 public constant ATTRIBUTION_FEE_BPS = 500; // 5%

    // Security test constants
    uint256 public constant INITIAL_TOKEN_BALANCE = 1000e18;
    uint256 public constant ATTACK_AMOUNT = 100e18;

    function setUp() public {
        // Deploy tokens with proper initial distributions
        _deployTokens();

        // Deploy core infrastructure
        _deployCoreContracts();

        // Deploy hooks
        _deployHooks();

        // Setup campaigns
        _setupCampaigns();

        console.log("Cross-hook security & integration test setup complete");
        console.log("AdConversion campaign:", adCampaign);
        console.log("CashbackRewards campaign:", buyerCampaign);
        console.log("SimpleRewards campaign:", simpleCampaign);
    }

    function _deployTokens() internal {
        // Deploy payment token (USDC-like) for buyers and merchants
        address[] memory paymentHolders = new address[](3);
        paymentHolders[0] = buyer1;
        paymentHolders[1] = buyer2;
        paymentHolders[2] = paymentManager;

        // Deploy reward tokens for campaign owners/funders + security test accounts
        address[] memory rewardHolders = new address[](6);
        rewardHolders[0] = advertiser;
        rewardHolders[1] = ecommerceOwner;
        rewardHolders[2] = daoManager;
        rewardHolders[3] = owner;
        rewardHolders[4] = attacker; // For security tests
        rewardHolders[5] = victim; // For security tests

        paymentToken = new DummyERC20(paymentHolders);
        rewardToken = new DummyERC20(rewardHolders);
        bonusToken = new DummyERC20(rewardHolders);
    }

    function _deployCoreContracts() internal {
        // Deploy Flywheel
        flywheel = new Flywheel();

        // Deploy publisher registry
        BuilderCodes impl = new BuilderCodes();
        bytes memory initData = abi.encodeWithSelector(BuilderCodes.initialize.selector, owner, signer, "");
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        publisherRegistry = BuilderCodes(address(proxy));

        // Deploy AuthCaptureEscrow
        escrow = new AuthCaptureEscrow();
    }

    function _deployHooks() internal {
        // Deploy AdConversion hook
        adHook = new AdConversion(address(flywheel), owner, address(publisherRegistry));

        // Deploy CashbackRewards hook
        buyerHook = new CashbackRewards(address(flywheel), address(escrow));

        // Deploy SimpleRewards hook
        simpleHook = new SimpleRewards(address(flywheel));
    }

    function _setupCampaigns() internal {
        // Register publishers for ad campaign
        vm.startPrank(owner);
        publisherRegistry.register("code1", publisher1, publisher1);
        publisherRegistry.register("code2", publisher2, publisher2);
        publisherRegistry.register("victim", victim, victim); // For security tests
        vm.stopPrank();

        // Attribution fee is now set during campaign creation

        // Create AdConversion campaign
        string[] memory allowedRefCodes = new string[](0);
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] =
            AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: "https://ad-campaign.com/metadata"});

        bytes memory adHookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://ad-campaign.com",
            allowedRefCodes,
            configs,
            7 days,
            ATTRIBUTION_FEE_BPS
        );
        adCampaign = flywheel.createCampaign(address(adHook), 1, adHookData);

        // Create CashbackRewards campaign
        bytes memory buyerHookData = abi.encode(ecommerceOwner, paymentManager, "https://ecommerce.com/cashback", 0);
        buyerCampaign = flywheel.createCampaign(address(buyerHook), 2, buyerHookData);

        // Create SimpleRewards campaign
        bytes memory simpleHookData = abi.encode(daoManager, daoManager, "");
        simpleCampaign = flywheel.createCampaign(address(simpleHook), 3, simpleHookData);

        // Fund all campaigns
        vm.startPrank(advertiser);
        rewardToken.transfer(adCampaign, CAMPAIGN_FUNDING);
        vm.stopPrank();

        vm.startPrank(ecommerceOwner);
        rewardToken.transfer(buyerCampaign, CAMPAIGN_FUNDING);
        vm.stopPrank();

        vm.startPrank(daoManager);
        rewardToken.transfer(simpleCampaign, CAMPAIGN_FUNDING);
        bonusToken.transfer(simpleCampaign, CAMPAIGN_FUNDING / 2);
        vm.stopPrank();

        // Activate all campaigns for security tests
        vm.prank(paymentManager);
        flywheel.updateStatus(buyerCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        vm.prank(daoManager);
        flywheel.updateStatus(simpleCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        vm.prank(attributionProvider);
        flywheel.updateStatus(adCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Initialize legacy alias for security tests
        token = rewardToken;
    }

    // Helper functions for CashbackRewards payment simulation
    function _createPaymentInfo(address payer, address payee, uint256 amount, bytes32 salt)
        internal
        view
        returns (AuthCaptureEscrow.PaymentInfo memory)
    {
        return AuthCaptureEscrow.PaymentInfo({
            operator: paymentManager,
            payer: payer,
            receiver: payee,
            token: address(paymentToken),
            maxAmount: uint120(amount),
            preApprovalExpiry: uint48(block.timestamp + 1 hours),
            authorizationExpiry: uint48(block.timestamp + 24 hours),
            refundExpiry: uint48(block.timestamp + 48 hours),
            minFeeBps: 0,
            maxFeeBps: 1000, // 10% max fee
            feeReceiver: address(0),
            salt: uint256(salt)
        });
    }

    function _simulatePayment(AuthCaptureEscrow.PaymentInfo memory paymentInfo, bytes32 paymentHash) internal {
        // Mock escrow.getHash to return our expected hash
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(AuthCaptureEscrow.getHash.selector, paymentInfo),
            abi.encode(paymentHash)
        );

        // Mock the paymentState mapping getter to return hasCollectedPayment = true
        vm.mockCall(
            address(escrow),
            abi.encodeWithSignature("paymentState(bytes32)", paymentHash),
            abi.encode(true, uint120(0), uint120(paymentInfo.maxAmount)) // hasCollectedPayment=true, capturableAmount=0, refundableAmount=amount
        );
    }

    // =============================================================
    //                    BASELINE INTEGRATION TESTS
    // =============================================================

    function test_hookInteroperabilityValidation() public {
        // Test that hooks don't interfere with each other

        // Campaigns are already ACTIVE from setUp(), so skip activation

        // Test that AdConversion controls don't affect other campaigns
        vm.expectRevert(); // Should fail - attribution provider has no control over buyer campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(buyerCampaign, Flywheel.CampaignStatus.INACTIVE, "");

        vm.expectRevert(); // Should fail - attribution provider has no control over simple campaign
        vm.prank(attributionProvider);
        flywheel.updateStatus(simpleCampaign, Flywheel.CampaignStatus.INACTIVE, "");

        // Test that CashbackRewards controls don't affect other campaigns
        vm.expectRevert(); // Should fail - payment manager has no control over ad campaign
        vm.prank(paymentManager);
        flywheel.updateStatus(adCampaign, Flywheel.CampaignStatus.INACTIVE, "");

        vm.expectRevert(); // Should fail - payment manager has no control over simple campaign
        vm.prank(paymentManager);
        flywheel.updateStatus(simpleCampaign, Flywheel.CampaignStatus.INACTIVE, "");

        // Test that SimpleRewards controls don't affect other campaigns
        vm.expectRevert(); // Should fail - DAO manager has no control over ad campaign
        vm.prank(daoManager);
        flywheel.updateStatus(adCampaign, Flywheel.CampaignStatus.INACTIVE, "");

        vm.expectRevert(); // Should fail - DAO manager has no control over buyer campaign
        vm.prank(daoManager);
        flywheel.updateStatus(buyerCampaign, Flywheel.CampaignStatus.INACTIVE, "");

        // Verify all campaigns are still active (no unauthorized changes)
        assertEq(uint8(flywheel.campaignStatus(adCampaign)), uint8(Flywheel.CampaignStatus.ACTIVE));
        assertEq(uint8(flywheel.campaignStatus(buyerCampaign)), uint8(Flywheel.CampaignStatus.ACTIVE));
        assertEq(uint8(flywheel.campaignStatus(simpleCampaign)), uint8(Flywheel.CampaignStatus.ACTIVE));

        console.log("Hook interoperability validation completed - all hooks properly isolated");
    }

    // =============================================================
    //                    SECURITY ATTACK SCENARIOS
    // =============================================================

    /// @notice Test cross-hook manager privilege escalation
    function test_security_crossHookManagerPrivilegeEscalation() public {
        // Manager of SimpleRewards tries to control CashbackRewards campaign
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = AuthCaptureEscrow.PaymentInfo({
            operator: merchant,
            payer: attacker,
            receiver: merchant,
            token: address(rewardToken),
            maxAmount: 1000e6,
            preApprovalExpiry: uint48(block.timestamp + 1 hours),
            authorizationExpiry: uint48(block.timestamp + 1 days),
            refundExpiry: uint48(block.timestamp + 7 days),
            minFeeBps: 0,
            maxFeeBps: 1000,
            feeReceiver: address(0),
            salt: 12345
        });

        bytes32 paymentHash = escrow.getHash(paymentInfo);
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(escrow.paymentState.selector, paymentHash),
            abi.encode(true, false, false)
        );

        CashbackRewards.PaymentReward[] memory paymentRewards = new CashbackRewards.PaymentReward[](1);
        paymentRewards[0] =
            CashbackRewards.PaymentReward({paymentInfo: paymentInfo, payoutAmount: uint120(ATTACK_AMOUNT)});
        bytes memory hookData = abi.encode(paymentRewards);

        // SimpleRewards manager should NOT be able to control CashbackRewards campaign
        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(simpleRewardsManager);
        flywheel.send(buyerCampaign, address(rewardToken), hookData);
    }

    /// @notice Test attribution provider cross-hook privilege abuse
    function test_security_attributionProviderCrossHookAbuse() public {
        // Attribution provider tries to control non-ad campaigns
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: attacker, amount: ATTACK_AMOUNT, extraData: ""});
        bytes memory hookData = abi.encode(payouts);

        // Attribution provider should NOT control SimpleRewards
        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(attributionProvider);
        flywheel.send(simpleCampaign, address(rewardToken), hookData);

        // Attribution provider should NOT control CashbackRewards
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = AuthCaptureEscrow.PaymentInfo({
            operator: merchant,
            payer: attacker,
            receiver: merchant,
            token: address(rewardToken),
            maxAmount: 1000e6,
            preApprovalExpiry: uint48(block.timestamp + 1 hours),
            authorizationExpiry: uint48(block.timestamp + 1 days),
            refundExpiry: uint48(block.timestamp + 7 days),
            minFeeBps: 0,
            maxFeeBps: 1000,
            feeReceiver: address(0),
            salt: 12346
        });

        CashbackRewards.PaymentReward[] memory cashbackRewards = new CashbackRewards.PaymentReward[](1);
        cashbackRewards[0] =
            CashbackRewards.PaymentReward({paymentInfo: paymentInfo, payoutAmount: uint120(ATTACK_AMOUNT)});
        bytes memory buyerHookData = abi.encode(cashbackRewards);

        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(attributionProvider);
        flywheel.send(buyerCampaign, address(rewardToken), buyerHookData);
    }

    // =============================================================
    //                    CROSS-CAMPAIGN ATTACK VECTORS
    // =============================================================

    /// @notice Test cross-campaign fund drainage
    function test_security_crossCampaignFundDrainage() public {
        // Compromised manager drains multiple campaigns
        uint256 attackerBalanceBefore = token.balanceOf(attacker);

        // Drain SimpleRewards campaign
        Flywheel.Payout[] memory payouts1 = new Flywheel.Payout[](1);
        payouts1[0] = Flywheel.Payout({recipient: attacker, amount: INITIAL_TOKEN_BALANCE, extraData: ""});

        vm.prank(simpleRewardsManager);
        flywheel.send(simpleCampaign, address(rewardToken), abi.encode(payouts1));

        // Drain CashbackRewards campaign (manager can't do this - only owner can withdraw after finalization)
        // But manager can allocate large amounts to attacker
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = AuthCaptureEscrow.PaymentInfo({
            operator: merchant,
            payer: attacker,
            receiver: merchant,
            token: address(rewardToken),
            maxAmount: 1000e6,
            preApprovalExpiry: uint48(block.timestamp + 1 hours),
            authorizationExpiry: uint48(block.timestamp + 1 days),
            refundExpiry: uint48(block.timestamp + 7 days),
            minFeeBps: 0,
            maxFeeBps: 1000,
            feeReceiver: address(0),
            salt: 12347
        });

        bytes32 paymentHash = escrow.getHash(paymentInfo);
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(escrow.paymentState.selector, paymentHash),
            abi.encode(true, false, false)
        );

        CashbackRewards.PaymentReward[] memory buyerDrainRewards = new CashbackRewards.PaymentReward[](1);
        buyerDrainRewards[0] =
            CashbackRewards.PaymentReward({paymentInfo: paymentInfo, payoutAmount: uint120(INITIAL_TOKEN_BALANCE)});

        vm.prank(cashbackRewardsManager);
        flywheel.send(buyerCampaign, address(rewardToken), abi.encode(buyerDrainRewards));

        // Verify drainage
        uint256 attackerBalanceAfter = token.balanceOf(attacker);
        assertEq(attackerBalanceAfter, attackerBalanceBefore + (2 * INITIAL_TOKEN_BALANCE));
    }

    /// @notice Test campaign state manipulation across hooks
    function test_security_crossHookStateManipulation() public {
        // Manager tries to pause campaigns they don't control
        vm.expectRevert(); // Should fail - manager doesn't control ad campaign
        vm.prank(manager);
        flywheel.updateStatus(adCampaign, Flywheel.CampaignStatus.INACTIVE, "");

        // Attribution provider tries to control other campaigns
        vm.expectRevert(); // Should fail - attribution provider doesn't control simple rewards
        vm.prank(attributionProvider);
        flywheel.updateStatus(simpleCampaign, Flywheel.CampaignStatus.INACTIVE, "");
    }

    // =============================================================
    //                    HOOK INTEROPERABILITY ATTACKS
    // =============================================================

    /// @notice Test hook data confusion attack
    function test_security_hookDataConfusionAttack() public {
        // Create SimpleRewards payout data
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: attacker, amount: ATTACK_AMOUNT, extraData: ""});
        bytes memory simpleRewardsData = abi.encode(payouts);

        // Try to use SimpleRewards data on CashbackRewards campaign
        vm.expectRevert(); // Should fail due to data format mismatch
        vm.prank(cashbackRewardsManager);
        flywheel.send(buyerCampaign, address(rewardToken), simpleRewardsData);

        // Create CashbackRewards payment data
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = AuthCaptureEscrow.PaymentInfo({
            operator: merchant,
            payer: attacker,
            receiver: merchant,
            token: address(rewardToken),
            maxAmount: 1000e6,
            preApprovalExpiry: uint48(block.timestamp + 1 hours),
            authorizationExpiry: uint48(block.timestamp + 1 days),
            refundExpiry: uint48(block.timestamp + 7 days),
            minFeeBps: 0,
            maxFeeBps: 1000,
            feeReceiver: address(0),
            salt: 12348
        });
        CashbackRewards.PaymentReward[] memory cashbackRewards = new CashbackRewards.PaymentReward[](1);
        cashbackRewards[0] =
            CashbackRewards.PaymentReward({paymentInfo: paymentInfo, payoutAmount: uint120(ATTACK_AMOUNT)});
        bytes memory cashbackRewardsData = abi.encode(cashbackRewards);

        // Try to use CashbackRewards data on SimpleRewards campaign
        vm.expectRevert(); // Should fail due to data format mismatch
        vm.prank(simpleRewardsManager);
        flywheel.send(simpleCampaign, address(rewardToken), cashbackRewardsData);
    }

    /// @notice Test allocation/distribution cross-contamination
    function test_security_allocationDistributionCrossContamination() public {
        // Allocate in SimpleRewards campaign
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: victim, amount: ATTACK_AMOUNT, extraData: ""});

        vm.prank(simpleRewardsManager);
        flywheel.allocate(simpleCampaign, address(rewardToken), abi.encode(payouts));

        // Verify allocation in flywheel core
        assertEq(
            flywheel.allocatedPayout(simpleCampaign, address(rewardToken), bytes32(bytes20(victim))), ATTACK_AMOUNT
        );

        // Attacker tries to distribute from different campaign's allocation
        // This should fail because allocations are campaign-specific
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = AuthCaptureEscrow.PaymentInfo({
            operator: merchant,
            payer: victim,
            receiver: merchant,
            token: address(rewardToken),
            maxAmount: 1000e6,
            preApprovalExpiry: uint48(block.timestamp + 1 hours),
            authorizationExpiry: uint48(block.timestamp + 1 days),
            refundExpiry: uint48(block.timestamp + 7 days),
            minFeeBps: 0,
            maxFeeBps: 1000,
            feeReceiver: address(0),
            salt: 12349
        });

        bytes32 paymentHash = escrow.getHash(paymentInfo);
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(escrow.paymentState.selector, paymentHash),
            abi.encode(true, false, false)
        );

        // CashbackRewards campaign has no allocation for victim
        assertEq(flywheel.allocatedPayout(buyerCampaign, address(rewardToken), bytes32(bytes20(victim))), 0);

        CashbackRewards.PaymentReward[] memory buyerDistributeRewards = new CashbackRewards.PaymentReward[](1);
        buyerDistributeRewards[0] =
            CashbackRewards.PaymentReward({paymentInfo: paymentInfo, payoutAmount: uint120(ATTACK_AMOUNT)});
        bytes memory buyerData = abi.encode(buyerDistributeRewards);

        // Should fail - no allocation in CashbackRewards campaign
        vm.expectRevert(); // InsufficientAllocation or similar
        vm.prank(cashbackRewardsManager);
        flywheel.distribute(buyerCampaign, address(rewardToken), buyerData);
    }

    // =============================================================
    //                    ECONOMIC ATTACK SCENARIOS
    // =============================================================

    /// @notice Test multi-campaign economic manipulation
    function test_security_multiCampaignEconomicManipulation() public {
        // Attacker with manager role in multiple campaigns could manipulate token prices
        // by coordinating large payouts across campaigns

        uint256 totalDrainAmount = 0;
        uint256 attackerBalanceBefore = token.balanceOf(attacker);

        // Drain SimpleRewards (manager has control)
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: attacker, amount: INITIAL_TOKEN_BALANCE / 2, extraData: ""});

        vm.prank(simpleRewardsManager);
        flywheel.send(simpleCampaign, address(rewardToken), abi.encode(payouts));
        totalDrainAmount += INITIAL_TOKEN_BALANCE / 2;

        // Drain CashbackRewards (manager has control over payouts)
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = AuthCaptureEscrow.PaymentInfo({
            operator: merchant,
            payer: attacker,
            receiver: merchant,
            token: address(rewardToken),
            maxAmount: 1000e6,
            preApprovalExpiry: uint48(block.timestamp + 1 hours),
            authorizationExpiry: uint48(block.timestamp + 1 days),
            refundExpiry: uint48(block.timestamp + 7 days),
            minFeeBps: 0,
            maxFeeBps: 1000,
            feeReceiver: address(0),
            salt: 12350
        });

        bytes32 paymentHash = escrow.getHash(paymentInfo);
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(escrow.paymentState.selector, paymentHash),
            abi.encode(true, false, false)
        );

        CashbackRewards.PaymentReward[] memory economicRewards = new CashbackRewards.PaymentReward[](1);
        economicRewards[0] =
            CashbackRewards.PaymentReward({paymentInfo: paymentInfo, payoutAmount: uint120(INITIAL_TOKEN_BALANCE / 2)});

        vm.prank(cashbackRewardsManager);
        flywheel.send(buyerCampaign, address(rewardToken), abi.encode(economicRewards));
        totalDrainAmount += INITIAL_TOKEN_BALANCE / 2;

        // Verify coordinated drainage
        uint256 attackerBalanceAfter = token.balanceOf(attacker);
        assertEq(attackerBalanceAfter, attackerBalanceBefore + totalDrainAmount);
    }

    /// @notice Test cross-hook fee manipulation
    function test_security_crossHookFeeManipulation() public {
        // Set high attribution provider fee and create new campaign for this test
        vm.prank(attributionProvider);
        // Attribution fee (50%) is now set during campaign creation

        // Create new campaign with 50% fee cached
        string[] memory allowedRefCodes = new string[](0);
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](1);
        configs[0] = AdConversion.ConversionConfigInput({
            isEventOnchain: false,
            metadataURI: "https://high-fee-campaign.com/metadata"
        });

        bytes memory highFeeHookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://high-fee-campaign.com",
            allowedRefCodes,
            configs,
            7 days,
            uint16(5000)
        );
        address highFeeCampaign = flywheel.createCampaign(address(adHook), 999, highFeeHookData);

        // Fund the new campaign
        vm.prank(advertiser);
        rewardToken.transfer(highFeeCampaign, CAMPAIGN_FUNDING);

        // Create attribution using registered publisher
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click123",
                configId: 1,
                publisherRefCode: "code1", // Use registered publisher from setUp
                timestamp: uint32(block.timestamp),
                payoutRecipient: publisher1, // Set actual recipient
                payoutAmount: 200e18
            }),
            logBytes: ""
        });

        bytes memory adHookData = abi.encode(attributions);

        // Attribution provider gets large fee from ad campaign
        uint256 providerBalanceBefore = token.balanceOf(attributionProvider);

        // vm.prank(address(flywheel));
        // (
        //     Flywheel.Payout[] memory payouts,
        //     Flywheel.Payout[] memory immediateFees,
        //     Flywheel.Allocation[] memory delayedFees
        // ) = adHook.onSend(attributionProvider, highFeeCampaign, address(rewardToken), adHookData);

        // // Fee should be 50% of 200e18 = 100e18
        // assertEq(immediateFees.length, 0);
        // assertEq(delayedFees.length, 1);
        // assertEq(delayedFees[0].key, bytes32(bytes20(attributionProvider)));
        // assertEq(delayedFees[0].amount, 100e18);
        // assertEq(keccak256(delayedFees[0].extraData), keccak256(""));

        // Other hooks (CashbackRewards, SimpleRewards) don't have fees
        // This creates economic imbalance that could be exploited
    }

    // =============================================================
    //                    REENTRANCY ACROSS HOOKS
    // =============================================================

    /// @notice Test cross-hook reentrancy attack
    function test_security_crossHookReentrancyAttack() public {
        // Deploy malicious contract that attempts cross-hook reentrancy
        CrossHookReentrancyAttacker attackerContract = new CrossHookReentrancyAttacker(
            address(flywheel), address(buyerHook), address(simpleHook), buyerCampaign, simpleCampaign
        );

        // This attack should fail due to access control
        vm.expectRevert();
        attackerContract.attemptCrossHookReentrancy();
    }
}

// =============================================================
//                    MALICIOUS CONTRACTS
// =============================================================

/// @notice Contract that attempts reentrancy across different hook types
contract CrossHookReentrancyAttacker {
    Flywheel public flywheel;
    CashbackRewards public buyerHook;
    SimpleRewards public simpleHook;
    address public buyerCampaign;
    address public simpleCampaign;
    bool public attacking;

    constructor(
        address _flywheel,
        address _buyerHook,
        address _simpleHook,
        address _buyerCampaign,
        address _simpleCampaign
    ) {
        flywheel = Flywheel(_flywheel);
        buyerHook = CashbackRewards(_buyerHook);
        simpleHook = SimpleRewards(_simpleHook);
        buyerCampaign = _buyerCampaign;
        simpleCampaign = _simpleCampaign;
    }

    function attemptCrossHookReentrancy() external {
        // This will fail because this contract is not authorized to call either hook
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: address(this), amount: 100e18, extraData: ""});
        bytes memory hookData = abi.encode(payouts);

        flywheel.send(simpleCampaign, address(0x1), hookData);
    }

    receive() external payable {
        if (!attacking) {
            attacking = true;
            // Attempt to call different hook during reentrancy
            try buyerHook.managers(buyerCampaign) {} catch {}
            try simpleHook.managers(simpleCampaign) {} catch {}
            attacking = false;
        }
    }
}
