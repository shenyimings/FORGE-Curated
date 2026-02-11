// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/Stake.sol";
import "../contracts/StakeSweeper.sol";
import {Token as VultToken} from "../contracts/Token.sol";
import "../contracts/mocks/MockUniswapRouter.sol";

contract StakeReinvestTest is Test {
    // Contracts
    Stake public stake;
    VultToken public stakingToken;
    VultToken public rewardToken;
    MockUniswapRouter public router;
    StakeSweeper public sweeper;

    // Actors
    address public owner = address(1);
    address public user = address(2);

    // Constants for testing
    uint256 public constant STAKE_AMOUNT = 1000 * 1e18;
    uint256 public constant REWARD_AMOUNT = 100 * 1e18;

    // Setup function called before each test
    function setUp() public {
        vm.startPrank(owner);

        // Deploy tokens
        stakingToken = new VultToken("Staking Token", "STK");
        rewardToken = new VultToken("Reward Token", "RWD");

        // Mint tokens - in our Token contract, mint() creates tokens for the caller only
        stakingToken.mint(10000 * 1e18);
        rewardToken.mint(10000 * 1e18);

        // Deploy a mock uniswap router for testing
        router = new MockUniswapRouter();
        sweeper = new StakeSweeper(address(rewardToken), address(router));

        // Deploy stake contract
        stake = new Stake(address(stakingToken), address(rewardToken));

        // Set router for the stake contract
        stake.setSweeper(address(sweeper));

        // Set reward parameters for immediate testing
        stake.setMinRewardUpdateDelay(0);
        stake.setRewardDecayFactor(1);

        // Transfer tokens to user
        stakingToken.transfer(user, STAKE_AMOUNT * 2);

        // Set up the mock router to simulate token swaps
        // Set a favorable exchange rate for tests to pass with slippage protection
        router.setExchangeRate(address(rewardToken), address(stakingToken), 9, 10); // 0.9 ratio

        // Pre-fund the router with staking tokens so it has tokens to swap
        stakingToken.transfer(address(router), 1000 * 1e18);

        vm.stopPrank();
    }

    // Test basic reinvestment flow
    function test_BasicReinvest() public {
        // User stakes tokens
        vm.startPrank(user);
        stakingToken.approve(address(stake), STAKE_AMOUNT);
        stake.deposit(STAKE_AMOUNT);
        vm.stopPrank();

        console.log("Initial staked amount:", stake.userAmount(user));

        // Owner sends rewards to stake contract
        vm.prank(owner);
        rewardToken.transfer(address(stake), REWARD_AMOUNT);

        // Update rewards to calculate distribution
        stake.updateRewards();

        // Check that pending rewards are available
        uint256 pendingRewards = stake.pendingRewards(user);
        console.log("Pending rewards:", pendingRewards);
        assertGt(pendingRewards, 0, "User should have pending rewards");

        // Log balances before reinvesting
        console.log("Stake contract reward balance:", rewardToken.balanceOf(address(stake)));

        // Get user stake amount before reinvesting
        uint256 userStakeBefore = stake.userAmount(user);

        vm.prank(user);
        uint256 reinvestedAmount = stake.reinvest();
        console.log("Reinvested amount:", reinvestedAmount);

        // Log final balances
        console.log("Final staked amount:", stake.userAmount(user));

        // After reinvestment
        uint256 userStakeAfter = stake.userAmount(user);

        // Verify results
        assertGt(reinvestedAmount, 0, "Should have reinvested some tokens");
        assertEq(userStakeAfter, userStakeBefore + reinvestedAmount, "Stake should have increased by reinvested amount");

        // Check rewards were claimed
        uint256 newPendingRewards = stake.pendingRewards(user);
        assertEq(newPendingRewards, 0, "All rewards should have been claimed");
    }
    // Test with router not set

    function test_RevertNoRouter() public {
        // Deploy new stake contract with no router set
        vm.startPrank(owner);
        Stake noRouterStake = new Stake(address(stakingToken), address(rewardToken));

        // Transfer some tokens to the new stake contract for testing
        rewardToken.transfer(address(noRouterStake), REWARD_AMOUNT);
        stakingToken.transfer(user, STAKE_AMOUNT);
        vm.stopPrank();

        // Set up user stake
        vm.startPrank(user);
        stakingToken.approve(address(noRouterStake), STAKE_AMOUNT);
        noRouterStake.deposit(STAKE_AMOUNT);

        // Update rewards
        noRouterStake.updateRewards();

        // Try to reinvest with no router set
        vm.expectRevert("Stake: sweeper not set");
        noRouterStake.reinvest();

        vm.stopPrank();
    }

    // Test with no rewards
    function test_RevertNoRewards() public {
        // User stakes tokens but has no rewards
        vm.startPrank(user);
        stakingToken.approve(address(stake), STAKE_AMOUNT);
        stake.deposit(STAKE_AMOUNT);

        // Try to reinvest with no rewards
        vm.expectRevert("Stake: no rewards to reinvest");
        stake.reinvest();

        vm.stopPrank();
    }

    // Test with rewards already claimed (no pending rewards)
    function test_RevertRewardsAlreadyClaimed() public {
        // User stakes tokens
        vm.startPrank(user);
        stakingToken.approve(address(stake), STAKE_AMOUNT);
        stake.deposit(STAKE_AMOUNT);
        vm.stopPrank();

        // Owner sends rewards to stake contract
        vm.prank(owner);
        rewardToken.transfer(address(stake), REWARD_AMOUNT);

        // Update rewards to make them claimable
        stake.updateRewards();

        // User claims rewards to themselves first
        vm.prank(user);
        stake.claim();

        // Try reinvest after already claiming rewards
        vm.startPrank(user);
        vm.expectRevert("Stake: no rewards to reinvest");
        stake.reinvest();
        vm.stopPrank();
    }

    // Test reinvest after partial reward claim
    function test_ReinvestAfterPartialClaim() public {
        // User stakes tokens
        vm.startPrank(user);
        stakingToken.approve(address(stake), STAKE_AMOUNT);
        stake.deposit(STAKE_AMOUNT);
        vm.stopPrank();

        // Owner sends rewards to stake contract
        vm.prank(owner);
        rewardToken.transfer(address(stake), REWARD_AMOUNT * 2);

        // Set immediate reward release for testing
        vm.startPrank(owner);
        stake.setRewardDecayFactor(1); // Release all rewards immediately
        stake.setMinRewardUpdateDelay(0); // No delay
        vm.stopPrank();

        stake.updateRewards();

        // User claims half the rewards
        vm.prank(user);
        stake.claim();

        // Send more rewards to the contract
        vm.prank(owner);
        rewardToken.transfer(address(stake), REWARD_AMOUNT);

        // Update rewards again to make new rewards available
        stake.updateRewards();

        // There should be new rewards available
        uint256 pendingAfter = stake.pendingRewards(user);
        assertGt(pendingAfter, 0, "User should have pending rewards after new deposit");

        // Get user stake amount before reinvesting
        uint256 userStakeBefore = stake.userAmount(user);

        // Now reinvest the remaining rewards
        vm.prank(user);
        uint256 reinvestedAmount = stake.reinvest();

        // Verify results
        assertGt(reinvestedAmount, 0, "Should have reinvested some tokens");
        assertEq(stake.userAmount(user), userStakeBefore + reinvestedAmount, "Stake should have increased");

        // After reinvest, there should be no rewards left
        uint256 remainingRewards = stake.pendingRewards(user);
        assertEq(remainingRewards, 0, "No rewards should remain after reinvesting");
    }

    // Test that reinvest emits correct events
    function test_ReinvestEvents() public {
        // User stakes tokens
        vm.startPrank(user);
        stakingToken.approve(address(stake), STAKE_AMOUNT);
        stake.deposit(STAKE_AMOUNT);
        vm.stopPrank();

        // Owner sends rewards to stake contract
        vm.prank(owner);
        rewardToken.transfer(address(stake), REWARD_AMOUNT);

        // Update rewards to calculate distribution
        stake.updateRewards();

        // Check that pending rewards are available
        uint256 pendingRewards = stake.pendingRewards(user);

        // Make sure we have rewards to reinvest
        assertGt(pendingRewards, 0, "User should have pending rewards");

        // Prepare for log recording

        vm.recordLogs();

        // Execute reinvestment as the user
        vm.prank(user);
        uint256 reinvestedAmount = stake.reinvest();

        // Verify logs manually instead of using expectEmit
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundRewardClaimed = false;
        bool foundDeposited = false;
        bool foundReinvested = false;

        for (uint256 i = 0; i < entries.length; i++) {
            // Check for RewardClaimed event
            if (entries[i].topics[0] == keccak256("RewardClaimed(address,uint256)")) {
                address eventUser = address(uint160(uint256(entries[i].topics[1])));
                assertEq(eventUser, user, "RewardClaimed event has wrong user");
                foundRewardClaimed = true;
            }
            // Check for Deposited event
            if (entries[i].topics[0] == keccak256("Deposited(address,uint256)")) {
                address eventUser = address(uint160(uint256(entries[i].topics[1])));
                assertEq(eventUser, user, "Deposited event has wrong user");
                foundDeposited = true;
            }
            // Check for Reinvested event
            if (entries[i].topics[0] == keccak256("Reinvested(address,uint256,uint256)")) {
                address eventUser = address(uint160(uint256(entries[i].topics[1])));
                assertEq(eventUser, user, "Reinvested event has wrong user");
                foundReinvested = true;
            }
        }

        assertTrue(foundRewardClaimed, "RewardClaimed event not emitted");
        assertTrue(foundDeposited, "Deposited event not emitted");
        assertTrue(foundReinvested, "Reinvested event not emitted");

        // Also verify the reinvested amount is within expected range
        assertGt(reinvestedAmount, 0, "Reinvested amount should be greater than 0");
    }
}
