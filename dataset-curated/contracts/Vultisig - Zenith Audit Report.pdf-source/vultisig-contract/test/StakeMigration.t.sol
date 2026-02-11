// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Stake} from "../contracts/Stake.sol";
import {MockERC1363} from "./mocks/MockERC1363.sol";

contract StakeMigrationTest is Test {
    Stake public oldStake;
    Stake public newStake;
    MockERC1363 public stakingToken;
    MockERC1363 public rewardToken;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 public constant USER_BALANCE = 1_000 ether;
    uint256 public constant DEPOSIT_AMOUNT = 100 ether;
    uint256 public constant REWARD_AMOUNT = 50 ether;

    function setUp() public {
        // Deploy tokens and stake contracts as owner
        vm.startPrank(owner);

        // Create separate tokens for staking and rewards
        stakingToken = new MockERC1363(INITIAL_SUPPLY);
        rewardToken = new MockERC1363(INITIAL_SUPPLY);

        // Deploy old and new stake contracts with the same tokens
        oldStake = new Stake(address(stakingToken), address(rewardToken));
        newStake = new Stake(address(stakingToken), address(rewardToken));

        // Transfer reward tokens to both stake contracts
        rewardToken.transfer(address(oldStake), REWARD_AMOUNT * 2); // Double for old contract
        rewardToken.transfer(address(newStake), REWARD_AMOUNT);

        // Transfer staking tokens to the user for testing
        stakingToken.transfer(user, USER_BALANCE);
        vm.stopPrank();

        // Set approvals for both stake contracts
        vm.prank(address(oldStake));
        rewardToken.approve(address(oldStake), type(uint256).max);
        vm.prank(address(newStake));
        rewardToken.approve(address(newStake), type(uint256).max);

        // User deposits tokens into old stake contract
        vm.startPrank(user);
        stakingToken.approve(address(oldStake), DEPOSIT_AMOUNT);
        oldStake.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Simulate passage of time with rewards accrual
        // First update rewards to establish baseline
        oldStake.updateRewards();
    }

    function test_MigrateBasic() public {
        // Verify initial state
        (uint256 initialStakedAmount,) = oldStake.userInfo(user);
        assertEq(initialStakedAmount, DEPOSIT_AMOUNT);
        assertEq(oldStake.totalStaked(), DEPOSIT_AMOUNT);
        assertEq(newStake.totalStaked(), 0);

        // User performs migration
        vm.startPrank(user);

        // Expect events for withdrawal and migration
        vm.expectEmit(true, true, false, true);
        emit Stake.Withdrawn(user, DEPOSIT_AMOUNT);
        vm.expectEmit(true, true, false, true);
        emit Stake.Migrated(user, address(newStake), DEPOSIT_AMOUNT);

        // Call migrate - now handles the complete migration in one transaction
        uint256 migratedAmount = oldStake.migrate(address(newStake));
        assertEq(migratedAmount, DEPOSIT_AMOUNT);

        // Check user's stake has been reset in old contract
        (uint256 oldStakedAmount,) = oldStake.userInfo(user);
        assertEq(oldStakedAmount, 0);
        assertEq(oldStake.totalStaked(), 0);

        // Verify tokens are now directly in the new contract
        (uint256 newStakedAmount,) = newStake.userInfo(user);
        assertEq(newStakedAmount, DEPOSIT_AMOUNT);
        assertEq(newStake.totalStaked(), DEPOSIT_AMOUNT);

        // Ensure user's wallet balance is unchanged (tokens went directly from old to new contract)
        assertEq(stakingToken.balanceOf(user), USER_BALANCE - DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function test_MigrateWithRewards() public {
        // Add some rewards to old contract (simulating time passing)
        vm.prank(owner);
        rewardToken.transfer(address(oldStake), REWARD_AMOUNT);

        // Configure rewards for immediate updates with no decay for testing
        vm.startPrank(owner);
        oldStake.setMinRewardUpdateDelay(0); // No delay between updates
        oldStake.setRewardDecayFactor(1); // No decay (release all rewards)
        vm.stopPrank();

        // Update rewards - with the parameters set above, all rewards will be processed
        oldStake.updateRewards();

        // Check initial pending rewards
        uint256 pendingRewards = oldStake.pendingRewards(user);
        assertTrue(pendingRewards > 0, "User should have pending rewards");

        // Store initial reward balance for later comparison
        uint256 initialRewardBalance = rewardToken.balanceOf(user);

        // User migrates - now handles the complete migration in one transaction
        vm.startPrank(user);
        uint256 migratedAmount = oldStake.migrate(address(newStake));
        assertEq(migratedAmount, DEPOSIT_AMOUNT);

        // Verify rewards were claimed during migration
        uint256 newRewardBalance = rewardToken.balanceOf(user);
        assertTrue(newRewardBalance > initialRewardBalance, "User should have received rewards");

        // Verify tokens are now directly in the new contract
        (uint256 newStakedAmount,) = newStake.userInfo(user);
        assertEq(newStakedAmount, DEPOSIT_AMOUNT);
        assertEq(newStake.totalStaked(), DEPOSIT_AMOUNT);

        // Ensure user's wallet balance is unchanged (tokens went directly from old to new contract)
        assertEq(stakingToken.balanceOf(user), USER_BALANCE - DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function test_RevertMigrateToInvalidContract() public {
        // Create a stake contract with different staking token
        MockERC1363 differentToken = new MockERC1363(INITIAL_SUPPLY);
        Stake invalidStake = new Stake(address(differentToken), address(rewardToken));

        vm.startPrank(user);

        // Should revert when trying to migrate to a contract with different staking token
        vm.expectRevert("Stake: incompatible staking token");
        oldStake.migrate(address(invalidStake));

        vm.stopPrank();
    }

    function test_RevertMigrateZeroAddress() public {
        vm.startPrank(user);

        vm.expectRevert("Stake: new contract is the zero address");
        oldStake.migrate(address(0));

        vm.stopPrank();
    }

    function test_RevertMigrateToSelf() public {
        vm.startPrank(user);

        vm.expectRevert("Stake: cannot migrate to self");
        oldStake.migrate(address(oldStake));

        vm.stopPrank();
    }

    function test_RevertMigrateNoStake() public {
        // Create a new user with no stake
        address noStakeUser = makeAddr("noStakeUser");

        vm.startPrank(noStakeUser);

        vm.expectRevert("Stake: no tokens to migrate");
        oldStake.migrate(address(newStake));

        vm.stopPrank();
    }

    function test_MultipleUsersMigration() public {
        // Create additional users
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        uint256 user2Deposit = 200 ether;
        uint256 user3Deposit = 300 ether;

        // Setup initial stakes for additional users
        vm.startPrank(owner);
        stakingToken.transfer(user2, USER_BALANCE);
        stakingToken.transfer(user3, USER_BALANCE);
        vm.stopPrank();

        // User2 deposits
        vm.startPrank(user2);
        stakingToken.approve(address(oldStake), user2Deposit);
        oldStake.deposit(user2Deposit);
        vm.stopPrank();

        // User3 deposits
        vm.startPrank(user3);
        stakingToken.approve(address(oldStake), user3Deposit);
        oldStake.deposit(user3Deposit);
        vm.stopPrank();

        // Add rewards and configure for immediate distribution
        vm.startPrank(owner);
        rewardToken.transfer(address(oldStake), REWARD_AMOUNT * 3);
        oldStake.setMinRewardUpdateDelay(0);
        oldStake.setRewardDecayFactor(1);
        vm.stopPrank();

        // Update rewards to distribute them
        oldStake.updateRewards();

        // Store initial reward balances and pending rewards
        uint256 user1InitialRewards = rewardToken.balanceOf(user);
        uint256 user2InitialRewards = rewardToken.balanceOf(user2);
        uint256 user3InitialRewards = rewardToken.balanceOf(user3);

        uint256 user1PendingRewards = oldStake.pendingRewards(user);
        uint256 user2PendingRewards = oldStake.pendingRewards(user2);
        uint256 user3PendingRewards = oldStake.pendingRewards(user3);

        // Verify that rewards are proportional to stake amounts
        assertGt(user1PendingRewards, 0);
        assertGt(user2PendingRewards, user1PendingRewards); // user2 has 2x the stake of user1
        assertGt(user3PendingRewards, user2PendingRewards); // user3 has 1.5x the stake of user2

        // Users migrate one by one
        vm.prank(user);
        uint256 migratedAmount1 = oldStake.migrate(address(newStake));

        vm.prank(user2);
        uint256 migratedAmount2 = oldStake.migrate(address(newStake));

        vm.prank(user3);
        uint256 migratedAmount3 = oldStake.migrate(address(newStake));

        // Verify migrated amounts
        assertEq(migratedAmount1, DEPOSIT_AMOUNT);
        assertEq(migratedAmount2, user2Deposit);
        assertEq(migratedAmount3, user3Deposit);

        // Verify final stakes in new contract
        (uint256 newStake1,) = newStake.userInfo(user);
        (uint256 newStake2,) = newStake.userInfo(user2);
        (uint256 newStake3,) = newStake.userInfo(user3);

        assertEq(newStake1, DEPOSIT_AMOUNT);
        assertEq(newStake2, user2Deposit);
        assertEq(newStake3, user3Deposit);

        // Verify exact reward amounts received
        assertEq(
            rewardToken.balanceOf(user) - user1InitialRewards,
            user1PendingRewards,
            "User1 didn't receive correct reward amount"
        );
        assertEq(
            rewardToken.balanceOf(user2) - user2InitialRewards,
            user2PendingRewards,
            "User2 didn't receive correct reward amount"
        );
        assertEq(
            rewardToken.balanceOf(user3) - user3InitialRewards,
            user3PendingRewards,
            "User3 didn't receive correct reward amount"
        );

        // Verify total staked amount in new contract
        assertEq(newStake.totalStaked(), DEPOSIT_AMOUNT + user2Deposit + user3Deposit);
        assertEq(oldStake.totalStaked(), 0);
    }
}
