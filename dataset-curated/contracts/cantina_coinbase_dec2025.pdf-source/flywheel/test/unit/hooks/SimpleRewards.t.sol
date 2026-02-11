// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../../lib/mocks/MockERC20.sol";

import {Constants} from "../../../src/Constants.sol";
import {Flywheel} from "../../../src/Flywheel.sol";
import {SimpleRewards} from "../../../src/hooks/SimpleRewards.sol";

contract SimpleRewardsTest is Test {
    Flywheel public flywheel;
    SimpleRewards public hook;
    MockERC20 public token;

    address public manager = address(0x1000);
    address public randomUser = address(0x2000);
    address public recipient1 = address(0x3000);
    address public recipient2 = address(0x4000);

    address public campaign;
    uint256 public constant INITIAL_TOKEN_BALANCE = 1000e18;
    uint256 public constant PAYOUT_AMOUNT = 100e18;

    function setUp() public {
        // Deploy contracts
        flywheel = new Flywheel();
        hook = new SimpleRewards(address(flywheel));

        // Deploy token with initial holders
        address[] memory initialHolders = new address[](2);
        initialHolders[0] = manager;
        initialHolders[1] = address(this);
        token = new MockERC20(initialHolders);

        // Create campaign
        bytes memory hookData = abi.encode(manager, manager, "");
        campaign = flywheel.createCampaign(address(hook), 1, hookData);
    }

    // NOTE: Core campaign creation is tested in Flywheel.t.sol
    // This focuses on SimpleRewards-specific campaign setup

    // =============================================================
    //                    NATIVE TOKEN TESTS
    // =============================================================

    function test_allocate_nativeToken_succeeds() public {
        // Fund campaign with native token and activate
        vm.deal(campaign, 1 ether);
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Prepare allocation in native token
        Flywheel.Payout[] memory allocations = new Flywheel.Payout[](1);
        allocations[0] = Flywheel.Payout({recipient: recipient1, amount: 0.5 ether, extraData: ""});

        vm.prank(manager);
        flywheel.allocate(campaign, Constants.NATIVE_TOKEN, abi.encode(allocations));
        bytes32 key = bytes32(bytes20(recipient1));
        assertEq(flywheel.allocatedPayout(campaign, Constants.NATIVE_TOKEN, key), 0.5 ether);
    }

    function test_withdraw_nativeToken_succeeds() public {
        // Fund campaign with native token
        vm.deal(campaign, 1 ether);

        // Prepare withdrawal hook data
        Flywheel.Payout memory payout = Flywheel.Payout({recipient: manager, amount: 1 ether, extraData: ""});

        // Succeeds now; assert balances updated
        uint256 beforeManager = manager.balance;
        vm.prank(manager);
        flywheel.withdrawFunds(campaign, Constants.NATIVE_TOKEN, abi.encode(payout));
        assertEq(manager.balance, beforeManager + 1 ether);
        assertEq(campaign.balance, 0);
    }

    // =============================================================
    //                    TOKEN TESTS
    // =============================================================
    function test_send_success() public {
        // Fund campaign
        vm.prank(manager);
        token.transfer(campaign, INITIAL_TOKEN_BALANCE);

        // Activate campaign
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Create payout data
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](2);
        payouts[0] = Flywheel.Payout({recipient: recipient1, amount: PAYOUT_AMOUNT, extraData: ""});
        payouts[1] = Flywheel.Payout({recipient: recipient2, amount: PAYOUT_AMOUNT / 2, extraData: ""});

        bytes memory hookData = abi.encode(payouts);

        // Process reward
        vm.prank(manager);
        flywheel.send(campaign, address(token), hookData);

        // Verify recipients received tokens
        assertEq(token.balanceOf(recipient1), PAYOUT_AMOUNT);
        assertEq(token.balanceOf(recipient2), PAYOUT_AMOUNT / 2);
    }

    // NOTE: Core allocate/distribute/deallocate functionality is tested in Flywheel.t.sol
    // This hook focuses on SimpleRewards-specific behavior

    function test_onlyManager_canCallPayoutFunctions() public {
        // Fund and activate campaign
        vm.prank(manager);
        token.transfer(campaign, INITIAL_TOKEN_BALANCE);

        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Create payout data
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: recipient1, amount: PAYOUT_AMOUNT, extraData: ""});

        Flywheel.Payout[] memory allocations = new Flywheel.Payout[](1);
        allocations[0] = Flywheel.Payout({recipient: recipient1, amount: PAYOUT_AMOUNT, extraData: ""});

        Flywheel.Payout[] memory distributions = new Flywheel.Payout[](1);
        distributions[0] = Flywheel.Payout({recipient: recipient1, amount: PAYOUT_AMOUNT, extraData: ""});

        // Random user cannot call payout functions
        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(randomUser);
        flywheel.send(campaign, address(token), abi.encode(payouts));

        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(randomUser);
        flywheel.allocate(campaign, address(token), abi.encode(allocations));

        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(randomUser);
        flywheel.distribute(campaign, address(token), abi.encode(distributions));

        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(randomUser);
        flywheel.deallocate(campaign, address(token), abi.encode(allocations));
    }

    function test_onlyManager_canUpdateStatus() public {
        // Manager can update status
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));

        // Random user cannot update status
        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(randomUser);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.INACTIVE, "");
    }

    function test_onlyManager_canWithdrawFunds() public {
        // Fund campaign
        vm.prank(manager);
        token.transfer(campaign, INITIAL_TOKEN_BALANCE);

        // Finalize campaign
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");

        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");

        // Manager can withdraw
        vm.prank(manager);
        flywheel.withdrawFunds(
            campaign,
            address(token),
            abi.encode(Flywheel.Payout({recipient: manager, amount: INITIAL_TOKEN_BALANCE, extraData: ""}))
        );

        // Random user cannot withdraw
        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(randomUser);
        flywheel.withdrawFunds(
            campaign, address(token), abi.encode(Flywheel.Payout({recipient: randomUser, amount: 0, extraData: ""}))
        );
    }

    function test_batchPayouts() public {
        // Fund and activate campaign
        vm.prank(manager);
        token.transfer(campaign, INITIAL_TOKEN_BALANCE);

        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Create multiple payouts
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](3);
        payouts[0] = Flywheel.Payout({recipient: recipient1, amount: 100e18, extraData: ""});
        payouts[1] = Flywheel.Payout({recipient: recipient2, amount: 200e18, extraData: ""});
        payouts[2] = Flywheel.Payout({recipient: address(0x5000), amount: 150e18, extraData: ""});

        bytes memory hookData = abi.encode(payouts);

        // Process batch reward
        vm.prank(manager);
        flywheel.send(campaign, address(token), hookData);

        // Verify all recipients received correct amounts
        assertEq(token.balanceOf(recipient1), 100e18);
        assertEq(token.balanceOf(recipient2), 200e18);
        assertEq(token.balanceOf(address(0x5000)), 150e18);
    }

    function test_emptyPayouts() public {
        // Fund and activate campaign
        vm.prank(manager);
        token.transfer(campaign, INITIAL_TOKEN_BALANCE);

        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Create empty payouts array
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](0);
        bytes memory hookData = abi.encode(payouts);

        // Should not revert with empty payouts
        vm.prank(manager);
        flywheel.send(campaign, address(token), hookData);

        // No tokens should be transferred
        assertEq(token.balanceOf(recipient1), 0);
        assertEq(token.balanceOf(recipient2), 0);
    }

    function test_multipleTokenTypes() public {
        // Deploy second token
        address[] memory initialHolders = new address[](1);
        initialHolders[0] = manager;
        MockERC20 token2 = new MockERC20(initialHolders);

        // Fund campaign with both tokens
        vm.startPrank(manager);
        token.transfer(campaign, INITIAL_TOKEN_BALANCE);
        token2.transfer(campaign, INITIAL_TOKEN_BALANCE);

        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        vm.stopPrank();

        // Create payouts for first token
        Flywheel.Payout[] memory payouts1 = new Flywheel.Payout[](1);
        payouts1[0] = Flywheel.Payout({recipient: recipient1, amount: 100e18, extraData: ""});

        // Create payouts for second token
        Flywheel.Payout[] memory payouts2 = new Flywheel.Payout[](1);
        payouts2[0] = Flywheel.Payout({recipient: recipient2, amount: 200e18, extraData: ""});

        // Process rewards for both tokens
        vm.prank(manager);
        flywheel.send(campaign, address(token), abi.encode(payouts1));

        vm.prank(manager);
        flywheel.send(campaign, address(token2), abi.encode(payouts2));

        // Verify correct token distributions
        assertEq(token.balanceOf(recipient1), 100e18);
        assertEq(token.balanceOf(recipient2), 0);
        assertEq(token2.balanceOf(recipient1), 0);
        assertEq(token2.balanceOf(recipient2), 200e18);
    }

    function test_allPayoutFunctions_supportedInAllStates() public {
        // Fund campaign
        vm.prank(manager);
        token.transfer(campaign, INITIAL_TOKEN_BALANCE);

        // Create payout data
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: recipient1, amount: 50e18, extraData: ""});

        // Test in ACTIVE state
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        vm.prank(manager);
        flywheel.send(campaign, address(token), abi.encode(payouts));

        vm.prank(manager);
        flywheel.allocate(campaign, address(token), abi.encode(payouts));

        vm.prank(manager);
        flywheel.deallocate(campaign, address(token), abi.encode(payouts));

        vm.prank(manager);
        flywheel.allocate(campaign, address(token), abi.encode(payouts));

        vm.prank(manager);
        flywheel.distribute(campaign, address(token), abi.encode(payouts));

        // Test in FINALIZING state
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");

        vm.prank(manager);
        flywheel.send(campaign, address(token), abi.encode(payouts));

        vm.prank(manager);
        flywheel.allocate(campaign, address(token), abi.encode(payouts));

        vm.prank(manager);
        flywheel.deallocate(campaign, address(token), abi.encode(payouts));

        vm.prank(manager);
        flywheel.allocate(campaign, address(token), abi.encode(payouts));

        vm.prank(manager);
        flywheel.distribute(campaign, address(token), abi.encode(payouts));

        // Verify recipient received tokens from multiple operations
        assertEq(token.balanceOf(recipient1), 200e18); // 4 reward + distribute operations × 50e18
    }

    function test_zeroAmountPayouts() public {
        // Fund and activate campaign
        vm.prank(manager);
        token.transfer(campaign, INITIAL_TOKEN_BALANCE);

        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Create zero amount payouts
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](2);
        payouts[0] = Flywheel.Payout({recipient: recipient1, amount: 0, extraData: ""});
        payouts[1] = Flywheel.Payout({recipient: recipient2, amount: PAYOUT_AMOUNT, extraData: ""});

        bytes memory hookData = abi.encode(payouts);

        // Should not revert with zero amounts
        vm.prank(manager);
        flywheel.send(campaign, address(token), hookData);

        // Only non-zero amount should be transferred
        assertEq(token.balanceOf(recipient1), 0);
        assertEq(token.balanceOf(recipient2), PAYOUT_AMOUNT);
    }

    function test_createNewCampaign() public {
        // Create second campaign with different manager
        address newManager = address(0x9000);
        bytes memory hookData = abi.encode(newManager, newManager, "");

        address newCampaign = flywheel.createCampaign(address(hook), 2, hookData);

        // Verify new campaign has correct manager
        assertEq(hook.managers(newCampaign), newManager);
        assertEq(hook.managers(campaign), manager); // Original campaign unchanged

        // Verify isolation - original manager cannot control new campaign
        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(manager);
        flywheel.updateStatus(newCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // But new manager can control new campaign
        vm.prank(newManager);
        flywheel.updateStatus(newCampaign, Flywheel.CampaignStatus.ACTIVE, "");
        assertEq(uint256(flywheel.campaignStatus(newCampaign)), uint256(Flywheel.CampaignStatus.ACTIVE));
    }

    function test_noFeesCharged() public {
        // Fund and activate campaign
        vm.prank(manager);
        token.transfer(campaign, INITIAL_TOKEN_BALANCE);

        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Create payout data
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: recipient1, amount: PAYOUT_AMOUNT, extraData: ""});

        bytes memory hookData = abi.encode(payouts);

        // Check initial balances
        uint256 campaignBalance = token.balanceOf(campaign);
        uint256 recipientBalance = token.balanceOf(recipient1);

        // Process reward
        vm.prank(manager);
        flywheel.send(campaign, address(token), hookData);

        // Verify no fees were charged (full amount transferred)
        assertEq(token.balanceOf(recipient1), recipientBalance + PAYOUT_AMOUNT);
        assertEq(token.balanceOf(campaign), campaignBalance - PAYOUT_AMOUNT);
    }

    // =============================================================
    //                    INTEGRATION TESTS
    // =============================================================

    function test_endToEndSimpleRewardsFlow() public {
        // Integration test for complete SimpleRewards workflow

        // Deploy additional tokens for proper separation
        address[] memory tokenHolders = new address[](1);
        tokenHolders[0] = manager;

        MockERC20 rewardToken = new MockERC20(tokenHolders);
        MockERC20 bonusToken = new MockERC20(tokenHolders);

        uint256 INITIAL_FUNDING = 100000e18; // 100,000 reward tokens
        uint256 BASE_REWARD = 1000e18; // 1,000 tokens per contribution

        // Fund campaign
        vm.startPrank(manager);
        rewardToken.transfer(campaign, INITIAL_FUNDING);
        bonusToken.transfer(campaign, INITIAL_FUNDING / 2); // 50,000 bonus tokens
        vm.stopPrank();

        // 1. Verify initial setup
        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(Flywheel.CampaignStatus.INACTIVE));
        assertEq(rewardToken.balanceOf(campaign), INITIAL_FUNDING);
        assertEq(rewardToken.balanceOf(recipient1), 0);
        assertEq(rewardToken.balanceOf(recipient2), 0);
        address recipient3 = address(0x5000);
        assertEq(rewardToken.balanceOf(recipient3), 0);

        // 2. Activate campaign
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(Flywheel.CampaignStatus.ACTIVE));

        // 3. Immediate rewards for quick contributions
        Flywheel.Payout[] memory immediatePayouts = new Flywheel.Payout[](2);
        immediatePayouts[0] = Flywheel.Payout({recipient: recipient1, amount: BASE_REWARD, extraData: "github-pr-123"});
        immediatePayouts[1] = Flywheel.Payout({
            recipient: recipient2,
            amount: BASE_REWARD * 2, // Larger contribution
            extraData: "github-pr-456"
        });

        vm.prank(manager);
        flywheel.send(campaign, address(rewardToken), abi.encode(immediatePayouts));

        // Verify immediate rewards
        assertEq(rewardToken.balanceOf(recipient1), BASE_REWARD);
        assertEq(rewardToken.balanceOf(recipient2), BASE_REWARD * 2);

        // 4. Allocated rewards for pending review
        Flywheel.Payout[] memory allocations = new Flywheel.Payout[](2);
        allocations[0] = Flywheel.Payout({
            recipient: recipient2,
            amount: BASE_REWARD / 2, // Additional contribution
            extraData: "github-pr-789"
        });
        allocations[1] = Flywheel.Payout({
            recipient: recipient3,
            amount: BASE_REWARD * 3, // Large contribution under review
            extraData: "github-pr-101112"
        });

        vm.prank(manager);
        flywheel.allocate(campaign, address(rewardToken), abi.encode(allocations));

        // Verify allocation (no tokens transferred yet)
        assertEq(rewardToken.balanceOf(recipient2), BASE_REWARD * 2); // Still only initial reward
        assertEq(rewardToken.balanceOf(recipient3), 0); // No tokens yet

        Flywheel.Payout[] memory distributions = new Flywheel.Payout[](2);
        distributions[0] = Flywheel.Payout({
            recipient: recipient2,
            amount: BASE_REWARD / 2, // Additional contribution
            extraData: "github-pr-789"
        });
        distributions[1] = Flywheel.Payout({
            recipient: recipient3,
            amount: BASE_REWARD * 3, // Large contribution under review
            extraData: "github-pr-101112"
        });

        // 5. Approve and distribute pending rewards
        vm.prank(manager);
        flywheel.distribute(campaign, address(rewardToken), abi.encode(distributions));

        // Verify distribution
        assertEq(rewardToken.balanceOf(recipient2), BASE_REWARD * 2 + BASE_REWARD / 2);
        assertEq(rewardToken.balanceOf(recipient3), BASE_REWARD * 3);

        // 6. Rejected contribution (allocate then deallocate)
        Flywheel.Payout[] memory rejectedAllocation = new Flywheel.Payout[](1);
        rejectedAllocation[0] = Flywheel.Payout({
            recipient: recipient1,
            amount: BASE_REWARD * 5, // Large reward for major feature
            extraData: "github-pr-131415"
        });

        // Allocate the reward
        vm.prank(manager);
        flywheel.allocate(campaign, address(rewardToken), abi.encode(rejectedAllocation));

        uint256 recipient1BalanceBeforeRejection = rewardToken.balanceOf(recipient1);

        // Reject the contribution (deallocate)
        vm.prank(manager);
        flywheel.deallocate(campaign, address(rewardToken), abi.encode(rejectedAllocation));

        // Verify deallocation (no change in recipient1's balance)
        assertEq(rewardToken.balanceOf(recipient1), recipient1BalanceBeforeRejection);

        // 7. Multi-token rewards (bonus token)
        Flywheel.Payout[] memory bonusPayouts = new Flywheel.Payout[](3);
        bonusPayouts[0] = Flywheel.Payout({
            recipient: recipient1,
            amount: 500e18, // Bonus for recipient1
            extraData: "milestone-bonus"
        });
        bonusPayouts[1] = Flywheel.Payout({
            recipient: recipient2,
            amount: 750e18, // Bonus for recipient2
            extraData: "milestone-bonus"
        });
        bonusPayouts[2] = Flywheel.Payout({
            recipient: recipient3,
            amount: 1000e18, // Bonus for recipient3
            extraData: "milestone-bonus"
        });

        vm.prank(manager);
        flywheel.send(campaign, address(bonusToken), abi.encode(bonusPayouts));

        // Verify bonus token distribution
        assertEq(bonusToken.balanceOf(recipient1), 500e18);
        assertEq(bonusToken.balanceOf(recipient2), 750e18);
        assertEq(bonusToken.balanceOf(recipient3), 1000e18);

        // 8. Finalize campaign
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");

        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");

        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(Flywheel.CampaignStatus.FINALIZED));

        // 9. Manager withdraws remaining funds
        uint256 remainingRewardTokens = rewardToken.balanceOf(campaign);
        uint256 remainingBonusTokens = bonusToken.balanceOf(campaign);
        uint256 managerRewardBalanceBefore = rewardToken.balanceOf(manager);
        uint256 managerBonusBalanceBefore = bonusToken.balanceOf(manager);

        vm.startPrank(manager);
        flywheel.withdrawFunds(
            campaign,
            address(rewardToken),
            abi.encode(Flywheel.Payout({recipient: manager, amount: remainingRewardTokens, extraData: ""}))
        );
        flywheel.withdrawFunds(
            campaign,
            address(bonusToken),
            abi.encode(Flywheel.Payout({recipient: manager, amount: remainingBonusTokens, extraData: ""}))
        );
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(campaign), 0);
        assertEq(bonusToken.balanceOf(campaign), 0);
        assertEq(rewardToken.balanceOf(manager), managerRewardBalanceBefore + remainingRewardTokens);
        assertEq(bonusToken.balanceOf(manager), managerBonusBalanceBefore + remainingBonusTokens);
    }

    function test_batchContributorRewards() public {
        // Test batch processing of multiple contributor rewards

        uint256 BASE_REWARD = 1000e18;

        // Fund with enough for batch rewards: 1000 + 2000 + ... + 10000 = 55000e18
        vm.prank(manager);
        token.transfer(campaign, 100000e18);

        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Create a large batch of contributors
        address[] memory contributors = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            contributors[i] = makeAddr(string(abi.encodePacked("contributor_", i)));
        }

        // Create batch payouts with varying amounts
        Flywheel.Payout[] memory batchPayouts = new Flywheel.Payout[](10);
        uint256 totalRewards = 0;
        for (uint256 i = 0; i < 10; i++) {
            uint256 amount = BASE_REWARD * (i + 1); // Escalating rewards
            batchPayouts[i] = Flywheel.Payout({
                recipient: contributors[i], amount: amount, extraData: abi.encodePacked("batch-contribution-", i)
            });
            totalRewards += amount;
        }

        // Process batch rewards
        vm.prank(manager);
        flywheel.send(campaign, address(token), abi.encode(batchPayouts));

        // Verify all contributors received their rewards
        for (uint256 i = 0; i < 10; i++) {
            uint256 expectedAmount = BASE_REWARD * (i + 1);
            assertEq(token.balanceOf(contributors[i]), expectedAmount);
        }
    }

    function test_flexibleRewardWorkflows() public {
        // Test the flexibility of SimpleRewards for different use cases

        uint256 BASE_REWARD = 1000e18;

        // Fund with enough for all use cases: 10000 + 100 + 200 + 2000 = ~12300e18
        vm.prank(manager);
        token.transfer(campaign, 20000e18);

        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Use case 1: Bug bounty program
        Flywheel.Payout[] memory bugBounties = new Flywheel.Payout[](1);
        bugBounties[0] = Flywheel.Payout({
            recipient: recipient1,
            amount: BASE_REWARD * 10, // High reward for critical bug
            extraData: "bug-bounty-critical-severity"
        });

        vm.prank(manager);
        flywheel.send(campaign, address(token), abi.encode(bugBounties));

        // Use case 2: Community governance participation
        Flywheel.Payout[] memory govRewards = new Flywheel.Payout[](2);
        govRewards[0] = Flywheel.Payout({
            recipient: recipient2,
            amount: BASE_REWARD / 10, // Small reward for vote participation
            extraData: "governance-vote-participation"
        });
        govRewards[1] = Flywheel.Payout({
            recipient: address(0x6000),
            amount: BASE_REWARD / 5, // Larger reward for proposal creation
            extraData: "governance-proposal-creation"
        });

        vm.prank(manager);
        flywheel.send(campaign, address(token), abi.encode(govRewards));

        // Use case 3: Educational content creation (allocate/distribute workflow)
        Flywheel.Payout[] memory allocations = new Flywheel.Payout[](1);
        allocations[0] = Flywheel.Payout({
            recipient: recipient1, amount: BASE_REWARD * 2, extraData: "educational-tutorial-creation"
        });

        // Allocate for review
        vm.prank(manager);
        flywheel.allocate(campaign, address(token), abi.encode(allocations));

        Flywheel.Payout[] memory distributions = new Flywheel.Payout[](1);
        distributions[0] = Flywheel.Payout({
            recipient: recipient1, amount: BASE_REWARD * 2, extraData: "educational-tutorial-creation"
        });

        uint256 balanceBeforeDistribution = token.balanceOf(recipient1);

        // Approve and distribute after review
        vm.prank(manager);
        flywheel.distribute(campaign, address(token), abi.encode(distributions));

        // Verify all rewards
        assertEq(token.balanceOf(recipient1), balanceBeforeDistribution + BASE_REWARD * 2);
        assertEq(token.balanceOf(recipient2), BASE_REWARD / 10);
        assertEq(token.balanceOf(address(0x6000)), BASE_REWARD / 5);
    }
}
