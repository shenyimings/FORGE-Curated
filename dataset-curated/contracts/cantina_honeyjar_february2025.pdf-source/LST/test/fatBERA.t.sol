// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {fatBERA} from "../src/fatBERA.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWETH} from "./mocks/MockWETH.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract fatBERATest is Test {
    uint256 public maxDeposits = 36000000 ether;
    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    fatBERA public vault;
    MockWETH public wbera;
    MockERC20 public rewardToken1;
    MockERC20 public rewardToken2;

    uint256 tolerance = 1e7;

    uint256 public constant INITIAL_MINT = 36000000 ether;

    function setUp() public {
        // Deploy mock WBERA
        wbera = new MockWETH();
        rewardToken1 = new MockERC20("Reward Token 1", "RWD1", 18);
        rewardToken2 = new MockERC20("Reward Token 2", "RWD2", 18);

        // Deploy vault with admin as DEFAULT_ADMIN_ROLE
        bytes memory initData = abi.encodeWithSelector(
            fatBERA.initialize.selector,
            address(wbera),
            admin, // Now initial admin
            maxDeposits
        );

        // Deploy proxy using the implementation - match deployment script approach
        address proxy = Upgrades.deployUUPSProxy("fatBERA.sol:fatBERA", initData);
        vault = fatBERA(payable(proxy));

        // Debug logs
        // console2.log("Admin address:", admin);
        // console2.log("Proxy address:", address(proxy));
        // console2.log("Implementation address:", Upgrades.getImplementationAddress(address(proxy)));
        // console2.log("Admin has DEFAULT_ADMIN_ROLE:", vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin));
        // console2.log("Admin has REWARD_NOTIFIER_ROLE:", vault.hasRole(vault.REWARD_NOTIFIER_ROLE(), admin));

        // Mint initial tokens to test accounts
        wbera.mint(alice, INITIAL_MINT);
        wbera.mint(bob, INITIAL_MINT);
        wbera.mint(charlie, INITIAL_MINT);
        wbera.mint(admin, INITIAL_MINT);

        rewardToken1.mint(admin, INITIAL_MINT);
        rewardToken2.mint(admin, INITIAL_MINT);

        // Approve vault to spend tokens
        vm.prank(alice);
        wbera.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        wbera.approve(address(vault), type(uint256).max);
        vm.prank(charlie);
        wbera.approve(address(vault), type(uint256).max);
        vm.startPrank(admin);
        wbera.approve(address(vault), type(uint256).max);
        rewardToken1.approve(address(vault), type(uint256).max);
        rewardToken2.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        // Fund test accounts with ETH
        vm.deal(alice, INITIAL_MINT);
        vm.deal(bob, INITIAL_MINT);
        vm.deal(charlie, INITIAL_MINT);

        // VAULT DURATION
        vm.startPrank(admin);
        vault.setRewardsDuration(address(wbera), 7 days);
        vault.setRewardsDuration(address(rewardToken1), 7 days);
        vault.setRewardsDuration(address(rewardToken2), 7 days);
        vm.stopPrank();
    }

    function notifyAndWarp(address token, uint256 amount) public {
        vm.prank(admin);
        vault.notifyRewardAmount(token, amount);
        vm.warp(block.timestamp + 1 + 7 days);
    }

    function test_Initialize() public view {
        // Check roles instead of owner
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin), "Admin should have DEFAULT_ADMIN_ROLE");
        assertEq(address(vault.asset()), address(wbera));
        assertEq(vault.paused(), true);
        (uint256 rewardPerShareStored, uint256 totalRewards,,,,,) = vault.rewardData(address(wbera));
        assertEq(rewardPerShareStored, 0);
        assertEq(totalRewards, 0);
        assertEq(vault.depositPrincipal(), 0);
    }

    function test_DepositWhenPaused() public {
        // Should succeed even when paused
        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(100e18, alice);

        assertEq(sharesMinted, 100e18, "Shares should be 1:1 with deposit");
        assertEq(vault.balanceOf(alice), 100e18);
    }

    function test_WithdrawWhenPaused() public {
        // First deposit (should work while paused)
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Try to withdraw while paused (should fail)
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(50e18, alice, alice);
    }

    function test_PreviewRewardsAccuracy() public {
        // Define an acceptable tolerance (in wei) to account for rounding differences.
        // 10^7 wei tolerance (0.00001 WBERA approximately)

        // Alice deposits 100 WBERA
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // First reward: 10 WBERA provided by admin
        notifyAndWarp(address(wbera), 10e18);

        // Expect that Alice receives approximately 10e18 reward, allowing for slight rounding differences
        uint256 expectedAliceFirstReward = 10e18; // 10 WBERA
        assertApproxEqAbs(
            vault.previewRewards(alice, address(wbera)),
            expectedAliceFirstReward,
            tolerance,
            "First reward preview mismatch"
        );

        // Bob deposits 100 WBERA, so now the total supply = 200 WBERA.
        vm.prank(bob);
        vault.deposit(100e18, bob);

        // Second reward: 20 WBERA provided by admin
        notifyAndWarp(address(wbera), 20e18);

        // With 200 shares total for the new reward, each share earns (20e18 / 200) = 0.1e18 reward.
        // - Alice had already received ~10e18 from the first round and will earn an additional ~10e18.
        // - Bob will earn ~10e18 from the second reward only.
        uint256 expectedAliceTotalReward = 20e18;
        uint256 expectedBobReward = 10e18;

        assertApproxEqAbs(
            vault.previewRewards(alice, address(wbera)),
            expectedAliceTotalReward,
            tolerance,
            "Alice's total reward mismatch after second reward"
        );
        assertApproxEqAbs(
            vault.previewRewards(bob, address(wbera)), expectedBobReward, tolerance, "Bob's reward preview mismatch"
        );

        // After Alice claims her rewards, her preview should return 0 but Bob's should remain unchanged.
        vm.prank(alice);
        vault.claimRewards(address(alice));
        assertApproxEqAbs(
            vault.previewRewards(alice, address(wbera)), 0, tolerance, "Alice should have 0 rewards after claim"
        );
        assertApproxEqAbs(
            vault.previewRewards(bob, address(wbera)),
            expectedBobReward,
            tolerance,
            "Bob's rewards unchanged after Alice's claim"
        );
    }

    function test_BasicDepositAndReward() public {
        // Admin already has REWARD_NOTIFIER_ROLE from initialize()
        // No need to grant it again

        // Alice deposits 100 WBERA
        uint256 aliceDeposit = 100e18;
        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(aliceDeposit, alice);

        assertEq(sharesMinted, aliceDeposit, "Shares should be 1:1 with deposit");
        assertEq(vault.balanceOf(alice), aliceDeposit);
        assertEq(vault.depositPrincipal(), aliceDeposit);
        assertEq(vault.totalSupply(), aliceDeposit);
        assertEq(vault.totalAssets(), aliceDeposit);

        // Add reward
        notifyAndWarp(address(wbera), 10e18);
        // Check Alice's claimable rewards
        assertApproxEqAbs(
            vault.previewRewards(alice, address(wbera)), 10e18, tolerance, "Alice should have 10e18 rewards"
        );
    }

    function test_MultipleDepositorsRewardDistribution() public {
        vm.prank(admin);
        vault.unpause();

        // Alice deposits 100 WBERA
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Admin adds 10 WBERA reward
        notifyAndWarp(address(wbera), 10e18);

        // Bob deposits 100 WBERA
        vm.prank(bob);
        vault.deposit(100e18, bob);

        // Admin adds another 10 WBERA reward
        notifyAndWarp(address(wbera), 10e18);

        // Check rewards
        assertApproxEqAbs(
            vault.previewRewards(alice, address(wbera)),
            15e18,
            tolerance,
            "Alice should have first reward + half of second"
        );
        assertApproxEqAbs(
            vault.previewRewards(bob, address(wbera)), 5e18, tolerance, "Bob should have half of second reward only"
        );
    }

    function test_ClaimRewards() public {
        vm.prank(admin);
        vault.unpause();

        // Alice deposits
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Add reward
        notifyAndWarp(address(wbera), 10e18);

        // Record balance before claim
        uint256 balanceBefore = wbera.balanceOf(alice);

        // Claim rewards
        vm.prank(alice);
        vault.claimRewards(address(alice));

        // Verify reward received
        assertApproxEqAbs(wbera.balanceOf(alice) - balanceBefore, 10e18, tolerance, "Should receive full reward");
        assertEq(vault.previewRewards(alice, address(wbera)), 0, "Rewards should be zero after claim");
    }

    function test_OwnerWithdrawPrincipal() public {
        vm.prank(admin);
        vault.unpause();

        // Alice deposits
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Admin withdraws principal for staking
        vm.prank(admin);
        vault.withdrawPrincipal(50e18, admin);

        // Check state
        assertEq(vault.depositPrincipal(), 50e18, "Principal should be reduced");
        assertEq(vault.totalSupply(), 100e18, "Total supply unchanged");
        assertEq(vault.totalAssets(), 100e18, "Total assets matches supply");
        assertEq(vault.balanceOf(alice), 100e18, "Alice's shares unchanged");
    }

    function test_CannotWithdrawWhenPaused() public {
        vm.prank(admin);
        vault.unpause();

        // Alice deposits
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Pause vault
        vm.prank(admin);
        vault.pause();

        // Try to withdraw
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(50e18, alice, alice);
    }

    function test_MultipleRewardCycles() public {
        vm.prank(admin);
        vault.unpause();

        // Alice and Bob deposit
        vm.prank(alice);
        vault.deposit(100e18, alice);
        vm.prank(bob);
        vault.deposit(100e18, bob);

        // First reward cycle
        notifyAndWarp(address(wbera), 10e18);

        // Alice claims
        vm.prank(alice);
        vault.claimRewards(address(alice));

        // Second reward cycle
        notifyAndWarp(address(wbera), 10e18);

        // Verify rewards
        assertApproxEqAbs(
            vault.previewRewards(alice, address(wbera)), 5e18, tolerance, "Alice should have half of second reward"
        );
        assertApproxEqAbs(
            vault.previewRewards(bob, address(wbera)),
            10e18,
            tolerance,
            "Bob should have unclaimed rewards from both cycles"
        );
    }

    function test_RewardDistributionWithPartialClaims() public {
        // Alice deposits 100
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // First reward: 10 WBERA
        notifyAndWarp(address(wbera), 10e18);

        // Bob deposits 100
        vm.prank(bob);
        vault.deposit(100e18, bob);

        // Alice claims her first reward
        vm.prank(alice);
        vault.claimRewards(address(alice));

        // Second reward: 20 WBERA (split between Alice and Bob)
        notifyAndWarp(address(wbera), 20e18);

        // Charlie deposits 200
        vm.prank(charlie);
        vault.deposit(200e18, charlie);

        // Third reward: 40 WBERA (split between all three)
        notifyAndWarp(address(wbera), 40e18);

        // Verify final reward states
        assertApproxEqAbs(
            vault.previewRewards(alice, address(wbera)),
            20e18,
            tolerance,
            "Alice should have share of second and third rewards"
        );
        assertApproxEqAbs(
            vault.previewRewards(bob, address(wbera)), 20e18, tolerance, "Bob should have all unclaimed rewards"
        );
        assertApproxEqAbs(
            vault.previewRewards(charlie, address(wbera)),
            20e18,
            tolerance,
            "Charlie should have share of third reward only"
        );
    }

    function test_SequentialDepositsAndRewards() public {
        // Alice deposits 100
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Reward 1: 10 WBERA
        notifyAndWarp(address(wbera), 10e18);

        // Bob deposits 200
        vm.prank(bob);
        vault.deposit(200e18, bob);

        // Reward 2: 30 WBERA
        notifyAndWarp(address(wbera), 30e18);

        // Alice claims
        vm.prank(alice);
        vault.claimRewards(address(alice));

        // Charlie deposits 300
        vm.prank(charlie);
        vault.deposit(300e18, charlie);

        // Reward 3: 60 WBERA
        notifyAndWarp(address(wbera), 60e18);

        // Verify complex reward distribution
        assertApproxEqAbs(
            vault.previewRewards(alice, address(wbera)), 10e18, tolerance, "Alice's new rewards after claim"
        );
        assertApproxEqAbs(vault.previewRewards(bob, address(wbera)), 40e18, tolerance, "Bob's accumulated rewards");
        assertApproxEqAbs(
            vault.previewRewards(charlie, address(wbera)), 30e18, tolerance, "Charlie's portion of last reward"
        );
    }

    function test_notifyRewardAmount() public {
        // Try to notify reward with no deposits (should revert with ZeroShares)
        vm.prank(admin);
        vm.expectRevert(fatBERA.ZeroShares.selector);
        vault.notifyRewardAmount(address(wbera), 10e18);

        // Alice deposits after failed reward
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Verify no rewards from before deposit
        assertEq(vault.previewRewards(alice, address(wbera)), 0, "Should have no rewards from before deposit");

        // New reward should work
        notifyAndWarp(address(wbera), 10e18);
        assertApproxEqAbs(vault.previewRewards(alice, address(wbera)), 10e18, tolerance, "Should receive new rewards");
    }

    function test_OwnerWithdrawAndRewardCycles() public {
        // Initial deposits
        vm.prank(alice);
        vault.deposit(100e18, alice);
        vm.prank(bob);
        vault.deposit(100e18, bob);

        // Admin withdraws 150 for staking
        vm.prank(admin);
        vault.withdrawPrincipal(150e18, admin);

        // Verify deposit principal reduced but shares unchanged
        assertEq(vault.depositPrincipal(), 50e18, "Deposit principal should be reduced");
        assertEq(vault.totalSupply(), 200e18, "Total supply should be unchanged");

        // Add rewards (simulating staking returns)
        notifyAndWarp(address(wbera), 30e18);

        // Verify rewards still work correctly
        assertApproxEqAbs(vault.previewRewards(alice, address(wbera)), 15e18, tolerance, "Alice's reward share");
        assertApproxEqAbs(vault.previewRewards(bob, address(wbera)), 15e18, tolerance, "Bob's reward share");
    }

    function test_MaxDeposits() public {
        // Try to deposit more than max
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector, alice, maxDeposits + 1, maxDeposits
            )
        );
        vault.deposit(maxDeposits + 1, alice);

        // Deposit up to max should work
        vm.prank(alice);
        vault.deposit(maxDeposits, alice);

        // Any further deposit should fail
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector, bob, 1, 0));
        vault.deposit(1, bob);
    }

    function test_MaxDepositsWithMint() public {
        // Try to mint more than max
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Upgradeable.ERC4626ExceededMaxMint.selector, alice, maxDeposits + 1, maxDeposits
            )
        );
        vault.mint(maxDeposits + 1, alice);

        // Mint up to max should work
        vm.prank(alice);
        vault.mint(maxDeposits, alice);

        // Any further mint should fail
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxMint.selector, bob, 1, 0));
        vault.mint(1, bob);
    }

    function test_MaxDepositsWithMultipleUsers() public {
        uint256 halfMax = maxDeposits / 2;

        // First user deposits half
        vm.prank(alice);
        vault.deposit(halfMax, alice);

        // Second user deposits slightly less than half
        vm.prank(bob);
        vault.deposit(halfMax - 1 ether, bob);

        // Third user tries to deposit more than remaining
        vm.prank(charlie);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector, charlie, 2 ether, 1 ether)
        );
        vault.deposit(2 ether, charlie);

        // But can deposit exactly the remaining amount
        vm.prank(charlie);
        vault.deposit(1 ether, charlie);
    }

    function test_MaxDepositsUpdate() public {
        // Initial deposit at current max
        vm.prank(alice);
        vault.deposit(maxDeposits, alice);
        // New deposit should still fail since vault is already at initial max
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector, bob, 1 ether, 0));
        vault.deposit(1 ether, bob);

        // Admin updates max deposits to double
        vm.prank(admin);
        vault.setMaxDeposits(maxDeposits + 1 ether);

        // New deposit should work
        vm.prank(bob);
        vault.deposit(1 ether, bob);

        // New deposit should fail
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector, bob, 1 ether, 0));
        vault.deposit(1 ether, bob);
    }

    function test_GetRewardTokensList() public {
        // First make a deposit to avoid ZeroShares error
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Add first reward token
        vm.startPrank(admin);
        rewardToken1.transfer(address(vault), 20e18);
        vault.notifyRewardAmount(address(rewardToken1), 20e18);

        // Add second reward token
        rewardToken2.transfer(address(vault), 40e18);
        vault.notifyRewardAmount(address(rewardToken2), 40e18);
        vm.stopPrank();

        // Get reward tokens list
        address[] memory rewardTokens = vault.getRewardTokens();

        // Verify list contents
        assertEq(rewardTokens.length, 2, "Should have 2 reward tokens");
        assertEq(rewardTokens[0], address(rewardToken1), "First reward token mismatch");
        assertEq(rewardTokens[1], address(rewardToken2), "Second reward token mismatch");
    }

    // Fuzz Tests
    function testFuzz_Deposit(uint256 amount) public {
        // Bound amount between 1 and maxDeposits to avoid unrealistic values
        amount = bound(amount, 1, maxDeposits);

        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(amount, alice);

        assertEq(sharesMinted, amount, "Shares minted should equal deposit amount");
        assertEq(vault.balanceOf(alice), amount, "Balance should equal deposit");
        assertEq(vault.depositPrincipal(), amount, "Principal should equal deposit");
    }

    function testFuzz_DepositWithExistingBalance(uint256 firstAmount, uint256 secondAmount) public {
        // Bound amounts to avoid overflow and unrealistic values
        firstAmount = bound(firstAmount, 1, maxDeposits / 2);
        secondAmount = bound(secondAmount, 1, maxDeposits - firstAmount);

        // First deposit
        vm.prank(alice);
        vault.deposit(firstAmount, alice);

        // Second deposit
        vm.prank(alice);
        vault.deposit(secondAmount, alice);

        assertEq(vault.balanceOf(alice), firstAmount + secondAmount, "Total balance incorrect");
        assertEq(vault.depositPrincipal(), firstAmount + secondAmount, "Total principal incorrect");
    }

    function testFuzz_Mint(uint256 shares) public {
        // Bound shares between 1 and maxDeposits
        shares = bound(shares, 1, maxDeposits);

        vm.prank(alice);
        uint256 assets = vault.mint(shares, alice);

        assertEq(assets, shares, "Assets should equal shares for 1:1 ratio");
        assertEq(vault.balanceOf(alice), shares, "Balance should equal minted shares");
        assertEq(vault.depositPrincipal(), assets, "Principal should equal assets");
    }

    function testFuzz_NotifyRewardAmount(uint256 depositAmount, uint256 rewardAmount) public {
        // Bound deposit amount between 1 and maxDeposits
        depositAmount = bound(depositAmount, 1 ether / 10000, maxDeposits);
        // Bound reward amount between 1 and maxDeposits (reasonable range for rewards)
        rewardAmount = bound(rewardAmount, 1 ether / 1000, maxDeposits);

        // Initial deposit
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Add reward
        notifyAndWarp(address(wbera), rewardAmount);

        // Record balance before claim
        uint256 balanceBefore = wbera.balanceOf(alice);

        // Claim rewards
        vm.prank(alice);
        vault.claimRewards(address(alice));

        // Verify actual rewards received with 0.00001% relative tolerance
        uint256 rewardsReceived = wbera.balanceOf(alice) - balanceBefore;
        assertApproxEqRel(
            rewardsReceived,
            rewardAmount,
            1e11, //
            "Reward amount received should be approximately equal"
        );
    }

    function testFuzz_MultiUserRewardDistribution(uint256 aliceDeposit, uint256 bobDeposit, uint256 rewardAmount)
        public
    {
        // Bound deposits to avoid overflow and unrealistic values
        aliceDeposit = bound(aliceDeposit, 1 ether / 10000, maxDeposits / 2);
        bobDeposit = bound(bobDeposit, 1 ether / 10000, maxDeposits - aliceDeposit);
        // Bound reward to a reasonable range
        rewardAmount = bound(rewardAmount, 1 ether / 1000, maxDeposits);

        // Alice and Bob deposit
        vm.prank(alice);
        vault.deposit(aliceDeposit, alice);
        vm.prank(bob);
        vault.deposit(bobDeposit, bob);

        // Add reward
        notifyAndWarp(address(wbera), rewardAmount);

        // Calculate expected rewards using the same mulDiv logic as the contract
        uint256 totalDeposits = aliceDeposit + bobDeposit;
        uint256 expectedAliceReward = FixedPointMathLib.mulDiv(rewardAmount, aliceDeposit, totalDeposits);
        uint256 expectedBobReward = FixedPointMathLib.mulDiv(rewardAmount, bobDeposit, totalDeposits);

        // Record balances before claims
        uint256 aliceBalanceBefore = wbera.balanceOf(alice);
        uint256 bobBalanceBefore = wbera.balanceOf(bob);

        // Claim rewards
        vm.prank(alice);
        vault.claimRewards(address(alice));
        vm.prank(bob);
        vault.claimRewards(address(bob));

        // Verify actual rewards received with 0.00001% relative tolerance
        uint256 aliceRewardsReceived = wbera.balanceOf(alice) - aliceBalanceBefore;
        uint256 bobRewardsReceived = wbera.balanceOf(bob) - bobBalanceBefore;

        // Verify rewards with 0.00001% relative tolerance
        assertApproxEqRel(
            aliceRewardsReceived, expectedAliceReward, 1e11, "Alice rewards should be approximately equal to expected"
        );
        assertApproxEqRel(
            bobRewardsReceived, expectedBobReward, 1e11, "Bob rewards should be approximately equal to expected"
        );

        // Critical safety check - protocol should never over-distribute
        assertLe(
            aliceRewardsReceived + bobRewardsReceived,
            rewardAmount,
            "Total distributed rewards should not exceed input amount"
        );
    }

    function test_MultiTokenRewards() public {
        // Initial deposits
        vm.prank(alice);
        vault.deposit(100e18, alice);
        vm.prank(bob);
        vault.deposit(100e18, bob);

        // Add first reward token
        notifyAndWarp(address(rewardToken1), 20e18);

        // Add second reward token
        notifyAndWarp(address(rewardToken2), 40e18);

        // Verify reward preview for both tokens
        assertApproxEqAbs(
            vault.previewRewards(alice, address(rewardToken1)), 10e18, tolerance, "Alice's RWD1 rewards incorrect"
        );
        assertApproxEqAbs(
            vault.previewRewards(alice, address(rewardToken2)), 20e18, tolerance, "Alice's RWD2 rewards incorrect"
        );
        assertApproxEqAbs(
            vault.previewRewards(bob, address(rewardToken1)), 10e18, tolerance, "Bob's RWD1 rewards incorrect"
        );
        assertApproxEqAbs(
            vault.previewRewards(bob, address(rewardToken2)), 20e18, tolerance, "Bob's RWD2 rewards incorrect"
        );

        // Claim rewards and verify balances
        uint256 aliceRwd1Before = rewardToken1.balanceOf(alice);
        uint256 aliceRwd2Before = rewardToken2.balanceOf(alice);

        vm.prank(alice);
        vault.claimRewards(address(alice));

        assertApproxEqAbs(
            rewardToken1.balanceOf(alice) - aliceRwd1Before, 10e18, tolerance, "Alice's RWD1 claim incorrect"
        );
        assertApproxEqAbs(
            rewardToken2.balanceOf(alice) - aliceRwd2Before, 20e18, tolerance, "Alice's RWD2 claim incorrect"
        );
    }

    function test_MultiTokenRewardsWithPartialClaims() public {
        // Initial deposits
        vm.prank(alice);
        vault.deposit(100e18, alice);
        vm.prank(bob);
        vault.deposit(100e18, bob);

        // First reward cycle with both tokens
        notifyAndWarp(address(rewardToken1), 20e18);
        notifyAndWarp(address(rewardToken2), 40e18);

        // Alice claims only rewardToken1
        vm.prank(alice);
        vault.claimRewards(address(rewardToken1), address(alice));

        // Second reward cycle
        notifyAndWarp(address(rewardToken1), 30e18);
        notifyAndWarp(address(rewardToken2), 60e18);

        // Verify rewards state
        assertApproxEqAbs(
            vault.previewRewards(alice, address(rewardToken1)),
            15e18,
            tolerance,
            "Alice's RWD1 rewards after partial claim"
        );
        assertApproxEqAbs(
            vault.previewRewards(alice, address(rewardToken2)), 50e18, tolerance, "Alice's RWD2 rewards accumulated"
        );
        assertApproxEqAbs(
            vault.previewRewards(bob, address(rewardToken1)), 25e18, tolerance, "Bob's RWD1 total rewards"
        );
        assertApproxEqAbs(
            vault.previewRewards(bob, address(rewardToken2)), 50e18, tolerance, "Bob's RWD2 total rewards"
        );
    }

    function testFuzz_MultiTokenRewardDistribution(
        uint256 aliceDeposit,
        uint256 bobDeposit,
        uint256 reward1Amount,
        uint256 reward2Amount
    ) public {
        // Bound deposits to avoid overflow and unrealistic values
        aliceDeposit = bound(aliceDeposit, 1 ether / 10000, maxDeposits / 2);
        bobDeposit = bound(bobDeposit, 1 ether / 10000, maxDeposits - aliceDeposit);
        // Bound rewards to reasonable ranges
        reward1Amount = bound(reward1Amount, 1 ether / 1000, maxDeposits);
        reward2Amount = bound(reward2Amount, 1 ether / 1000, maxDeposits);

        // Alice and Bob deposit
        vm.prank(alice);
        vault.deposit(aliceDeposit, alice);
        vm.prank(bob);
        vault.deposit(bobDeposit, bob);

        notifyAndWarp(address(rewardToken1), reward1Amount);
        notifyAndWarp(address(rewardToken2), reward2Amount);

        // Calculate expected rewards
        uint256 totalDeposits = aliceDeposit + bobDeposit;
        uint256 expectedAliceReward1 = FixedPointMathLib.mulDiv(reward1Amount, aliceDeposit, totalDeposits);
        uint256 expectedAliceReward2 = FixedPointMathLib.mulDiv(reward2Amount, aliceDeposit, totalDeposits);
        uint256 expectedBobReward1 = FixedPointMathLib.mulDiv(reward1Amount, bobDeposit, totalDeposits);
        uint256 expectedBobReward2 = FixedPointMathLib.mulDiv(reward2Amount, bobDeposit, totalDeposits);

        // Record balances before claims
        uint256 aliceReward1Before = rewardToken1.balanceOf(alice);
        uint256 aliceReward2Before = rewardToken2.balanceOf(alice);
        uint256 bobReward1Before = rewardToken1.balanceOf(bob);
        uint256 bobReward2Before = rewardToken2.balanceOf(bob);

        // Claim rewards
        vm.prank(alice);
        vault.claimRewards(address(alice));
        vm.prank(bob);
        vault.claimRewards(address(bob));

        // Verify rewards with 0.00001% relative tolerance
        assertApproxEqRel(
            rewardToken1.balanceOf(alice) - aliceReward1Before, expectedAliceReward1, 1e11, "Alice reward1 mismatch"
        );
        assertApproxEqRel(
            rewardToken2.balanceOf(alice) - aliceReward2Before, expectedAliceReward2, 1e11, "Alice reward2 mismatch"
        );
        assertApproxEqRel(
            rewardToken1.balanceOf(bob) - bobReward1Before, expectedBobReward1, 1e11, "Bob reward1 mismatch"
        );
        assertApproxEqRel(
            rewardToken2.balanceOf(bob) - bobReward2Before, expectedBobReward2, 1e11, "Bob reward2 mismatch"
        );

        // Verify total rewards don't exceed input amounts
        assertLe(
            (rewardToken1.balanceOf(alice) - aliceReward1Before) + (rewardToken1.balanceOf(bob) - bobReward1Before),
            reward1Amount,
            "Total reward1 distribution exceeds input"
        );
        assertLe(
            (rewardToken2.balanceOf(alice) - aliceReward2Before) + (rewardToken2.balanceOf(bob) - bobReward2Before),
            reward2Amount,
            "Total reward2 distribution exceeds input"
        );
    }

    // Native Deposit Specific Tests
    function test_DepositNativeBasic() public {
        uint256 depositAmount = 1 ether;
        vm.prank(alice);
        vault.depositNative{value: depositAmount}(alice);

        assertEq(vault.balanceOf(alice), depositAmount, "Shares minted");
        assertEq(vault.depositPrincipal(), depositAmount, "Principal tracking");
        assertEq(address(vault).balance, 0, "No leftover ETH");
    }

    function test_DepositNativeRevertZeroValue() public {
        vm.prank(alice);
        vm.expectRevert(fatBERA.ZeroPrincipal.selector);
        vault.depositNative{value: 0}(alice);
    }

    function test_DepositNativeExceedsMax() public {
        uint256 maxDeposit = maxDeposits - 1 ether;

        // Fill up to max
        vm.prank(alice);
        vault.deposit(maxDeposit, alice);

        // Try to deposit 1.01 ETH native
        vm.prank(bob);
        vm.expectRevert(fatBERA.ExceedsMaxDeposits.selector);
        vault.depositNative{value: 1.01 ether}(bob);
    }

    function test_DepositNativeWETHBalance() public {
        uint256 depositAmount = 5 ether;
        uint256 initialWETHBalance = wbera.balanceOf(address(vault));

        vm.prank(alice);
        vault.depositNative{value: depositAmount}(alice);

        assertEq(
            wbera.balanceOf(address(vault)),
            initialWETHBalance + depositAmount,
            "WETH balance should increase by deposit amount"
        );
    }

    function test_MixedDepositMethods() public {
        uint256 nativeDeposit = 2 ether;
        uint256 erc20Deposit = 3 ether;

        // Native deposit
        vm.prank(alice);
        vault.depositNative{value: nativeDeposit}(alice);

        // ERC20 deposit
        vm.prank(alice);
        vault.deposit(erc20Deposit, alice);

        assertEq(vault.depositPrincipal(), nativeDeposit + erc20Deposit, "Should track both deposit types");
        assertEq(vault.balanceOf(alice), nativeDeposit + erc20Deposit, "Shares should be cumulative");
    }

    function test_NativeDepositWithRewards() public {
        uint256 depositAmount = 10 ether;

        vm.prank(alice);
        vault.depositNative{value: depositAmount}(alice);

        // Add rewards
        notifyAndWarp(address(wbera), 10 ether);

        // Verify rewards
        assertApproxEqAbs(
            vault.previewRewards(alice, address(wbera)), 10 ether, tolerance, "Should accrue rewards correctly"
        );
    }

    // Fuzz Tests
    function testFuzz_DepositNative(uint256 amount) public {
        amount = bound(amount, 1 wei, maxDeposits);
        vm.deal(alice, amount);

        vm.prank(alice);
        vault.depositNative{value: amount}(alice);

        assertEq(vault.balanceOf(alice), amount, "Shares should match deposit");
        assertEq(vault.depositPrincipal(), amount, "Principal should match");
    }

    function testFuzz_MixedDepositTypes(uint256 nativeAmount, uint256 erc20Amount) public {
        nativeAmount = bound(nativeAmount, 1 wei, maxDeposits / 2);
        erc20Amount = bound(erc20Amount, 1 wei, maxDeposits - nativeAmount);
        vm.deal(alice, nativeAmount);

        // Native deposit
        vm.prank(alice);
        vault.depositNative{value: nativeAmount}(alice);

        // ERC20 deposit
        vm.prank(alice);
        vault.deposit(erc20Amount, alice);

        assertEq(vault.depositPrincipal(), nativeAmount + erc20Amount, "Total principal should sum both types");
    }

    function test_RoleManagement() public {
        address newNotifier = makeAddr("newNotifier");

        // First verify initial roles
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin), "Admin should have DEFAULT_ADMIN_ROLE");
        assertTrue(vault.hasRole(vault.REWARD_NOTIFIER_ROLE(), admin), "Admin should have REWARD_NOTIFIER_ROLE");

        // Admin grants REWARD_NOTIFIER_ROLE to new address
        vm.startPrank(admin);
        vault.grantRole(vault.REWARD_NOTIFIER_ROLE(), newNotifier);
        vm.stopPrank();

        // Verify roles after granting
        assertTrue(vault.hasRole(vault.REWARD_NOTIFIER_ROLE(), newNotifier), "New notifier should have role");
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin), "Admin should still have admin role");
        assertTrue(vault.hasRole(vault.REWARD_NOTIFIER_ROLE(), admin), "Admin should still have notifier role");

        // Test revoking role
        vm.startPrank(admin);
        vault.revokeRole(vault.REWARD_NOTIFIER_ROLE(), newNotifier);
        vm.stopPrank();
        assertFalse(vault.hasRole(vault.REWARD_NOTIFIER_ROLE(), newNotifier), "Role should be revoked");
        console.log("newNotifier", newNotifier);

        bytes32 role = vault.REWARD_NOTIFIER_ROLE();

        // Test that non-admin cannot grant roles
        vm.startPrank(newNotifier);
        vm.expectRevert();
        vault.grantRole(role, alice);
        vm.stopPrank();
    }

    function test_only_admin_can_pause_and_unpause() public {
        // Non-admin attempts
        vm.prank(alice);
        vm.expectRevert();
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.unpause();

        // Admin attempts should succeed
        vm.startPrank(admin);
        vault.unpause();
        assertTrue(!vault.paused(), "Vault should be unpaused");

        vault.pause();
        assertTrue(vault.paused(), "Vault should be paused");
        vm.stopPrank();
    }

    function test_only_admin_can_set_max_rewards_tokens() public {
        uint256 newMax = 20;

        // Non-admin attempt
        vm.prank(alice);
        vm.expectRevert();
        vault.setMaxRewardsTokens(newMax);

        // Admin attempt should succeed
        vm.prank(admin);
        vault.setMaxRewardsTokens(newMax);
        assertEq(vault.MAX_REWARDS_TOKENS(), newMax, "MAX_REWARDS_TOKENS not updated");
    }

    function test_setRewardsDuration_active_period_reverts() public {
        // First make a deposit to avoid ZeroShares error
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Set initial duration
        vm.prank(admin);
        vault.setRewardsDuration(address(wbera), 7 days);

        // Notify reward to start period
        vm.prank(admin);
        vault.notifyRewardAmount(address(wbera), 10e18);

        // Attempt to update duration during active period
        vm.prank(admin);
        vm.expectRevert(fatBERA.RewardPeriodStillActive.selector);
        vault.setRewardsDuration(address(wbera), 14 days);
    }

    /**
     * @dev Test that rewards accrue linearly over time.
     * After notifying a reward, we warp forward a fraction of the reward period and verify
     * that the accrued rewards match the expected proportion.
     */
    function test_PartialTimeRewardAccrual() public {
        // Unpause the vault so that deposits are permitted.
        vm.prank(admin);
        vault.unpause();

        // Alice deposits 100 tokens.
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Record the starting time.
        uint256 startTime = block.timestamp;

        // Notify a reward amount that will be distributed linearly over 7 days.
        uint256 rewardAmount = 70e18; // For example, 70 WBERA reward
        vm.prank(admin);
        vault.notifyRewardAmount(address(wbera), rewardAmount);

        // Immediately after notification, no reward should have accrued.
        uint256 initialAccrued = vault.previewRewards(alice, address(wbera));
        assertEq(initialAccrued, 0, "No reward should accrue immediately after notification");

        // Warp forward by half of the reward duration (i.e. 3.5 days).
        uint256 halfTime = 7 days / 2;
        vm.warp(startTime + halfTime);

        // Expected reward is proportional: (rewardAmount * elapsedTime) / rewardsDuration.
        uint256 expectedReward = rewardAmount * halfTime / (7 days);
        uint256 accruedReward = vault.previewRewards(alice, address(wbera));
        assertApproxEqAbs(accruedReward, expectedReward, tolerance, "Partial time reward accrual mismatch");
    }

    /**
     * @dev Test that once the entire reward period elapses, the total accrued rewards equal the full reward,
     * and that further time passage does not increase rewards beyond the notified amount.
     */
    function test_FullTimeRewardAccrual() public {
        vm.prank(admin);
        vault.unpause();

        vm.prank(alice);
        vault.deposit(100e18, alice);

        uint256 startTime = block.timestamp;
        uint256 rewardAmount = 50e18;
        vm.prank(admin);
        vault.notifyRewardAmount(address(wbera), rewardAmount);

        // Warp exactly to the end of the reward period.
        vm.warp(startTime + 7 days);
        uint256 accruedReward = vault.previewRewards(alice, address(wbera));
        // Expect the full reward amount to have accrued.
        assertApproxEqAbs(accruedReward, rewardAmount, tolerance, "Full time reward accrual mismatch");

        // Warp further in time; rewards should not exceed the full reward.
        vm.warp(startTime + 7 days + 1 days);
        uint256 accruedRewardAfterExtra = vault.previewRewards(alice, address(wbera));
        assertApproxEqAbs(
            accruedRewardAfterExtra, rewardAmount, tolerance, "Reward should not accrue past reward period"
        );
    }

    /**
     * @dev Test that reward accumulations over successive cycles are additive.
     * The test first notifies a reward, waits for the entire period (thus accruing the full first reward),
     * then notifies a second reward and checks that the total accrued rewards equal the sum of the full first reward
     * and a partial accrual of the second reward.
     */
    function test_CumulativeTimeBasedRewards() public {
        vm.prank(admin);
        vault.unpause();

        // Alice deposits 100 tokens.
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Record the initial timestamp.
        uint256 startTime = block.timestamp;

        // First reward: 40 WBERA distributed over 7 days.
        uint256 rewardAmount1 = 40e18;
        vm.prank(admin);
        vault.notifyRewardAmount(address(wbera), rewardAmount1);

        // Warp to the end of the first reward period.
        vm.warp(startTime + 7 days);
        uint256 accruedFirst = vault.previewRewards(alice, address(wbera));
        // Should equal the full first reward amount.
        assertApproxEqAbs(accruedFirst, rewardAmount1, tolerance, "First reward full accrual mismatch");

        // Second reward: notify a new reward immediately after the first period.
        uint256 rewardAmount2 = 60e18;
        vm.prank(admin);
        vault.notifyRewardAmount(address(wbera), rewardAmount2);
        uint256 secondStartTime = block.timestamp; // Should equal startTime + 7 days

        // Warp forward by half of the second reward period.
        uint256 halfTimeSecond = 7 days / 2;
        vm.warp(secondStartTime + halfTimeSecond);
        uint256 accruedSecond = rewardAmount2 * halfTimeSecond / (7 days);

        // Total expected rewards are the sum of the first (fully accrued) and second (partially accrued).
        uint256 totalExpected = rewardAmount1 + accruedSecond;
        uint256 totalAccrued = vault.previewRewards(alice, address(wbera));
        assertApproxEqAbs(totalAccrued, totalExpected, tolerance, "Cumulative reward accrual mismatch");
    }

    /**
     * @dev Test that a sandwich attack is mitigated. In a vulnerable design, an attacker depositing
     * just before notifyRewardAmount() and quickly claiming would capture the full reward.
     * With time-based accrual, the attacker only earns rewards for the very short time they are staked.
     * Withdrawals are disabled, so previewRewards() is used to verify the minimal reward accumulation.
     */
    function test_SandwichAttackMitigation() public {
        // Unpause the vault to allow deposits.
        vm.prank(admin);
        vault.unpause();

        // --- Attacker deposits borrowed WBERA before the reward is notified ---
        uint256 attackerDeposit = 100e18;
        vm.prank(bob);
        vault.deposit(attackerDeposit, bob);

        // Capture the block timestamp as the notify time.
        uint256 notifyTime = block.timestamp;

        // --- Admin notifies a reward ---
        // For example, notify 50 WBERA to be distributed linearly over 7 days.
        uint256 totalReward = 50e18;
        vm.prank(admin);
        vault.notifyRewardAmount(address(wbera), totalReward);

        // --- Simulate the attacker quickly exiting ---
        // Immediately after notifying, simulate a brief time passage of 1 second.
        vm.warp(notifyTime + 1);

        // Instead of withdrawing (withdrawals are disabled), check what reward accrual preview shows.
        uint256 attackerRewardPreview = vault.previewRewards(bob, address(wbera));

        // With a linear accrual the reward earned over 1 second should be:
        //   rewardRate = totalReward / rewardsDuration (7 days = 604800 seconds)
        // Thus, expectedReward = 1 * (totalReward / 604800)
        uint256 expectedAttackerReward = totalReward / 604800;

        // We use a modest tolerance (1e10 wei) after accounting for arithmetic precision.
        assertApproxEqAbs(
            attackerRewardPreview,
            expectedAttackerReward,
            1e10,
            "Attacker reward preview exceeds expected minimal accrual"
        );
    }

    /**
     * @dev Test to ensure that transferring shares does not allow a recipient
     *      to claim rewards accrued before the transfer.
     *      This test fails in the vulnerable contract (without reward update on transfer)
     *      and passes once the fix (calling _updateRewards on share transfers) is applied.
     */
    function test_TransferDoesNotStealRewards() public {
        // Alice deposits 100 WBERA
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Notify a reward of 10 WBERA
        uint256 rewardAmount = 10e18;
        vm.prank(admin);
        vault.notifyRewardAmount(address(wbera), rewardAmount);

        // Warp forward by half the reward duration (3.5 days)
        uint256 halfPeriod = 7 days / 2;
        vm.warp(block.timestamp + halfPeriod);

        // Capture Alice's accrued rewards before the transfer
        uint256 aliceRewardsBefore = vault.previewRewards(alice, address(wbera));
        assertGt(aliceRewardsBefore, 0, "Alice should have accrued rewards before transfer");

        // Alice transfers half of her shares (50e18) to Bob
        uint256 transferAmount = depositAmount / 2;
        vm.prank(alice);
        vault.transfer(bob, transferAmount);

        // Immediately after transfer:
        // 1. Alice's rewards should remain the same (she keeps rewards accrued before transfer)
        uint256 aliceRewardsAfter = vault.previewRewards(alice, address(wbera));
        assertEq(aliceRewardsAfter, aliceRewardsBefore, "Alice's rewards should not change after transfer");

        // 2. Bob should start with 0 rewards (should not inherit Alice's rewards)
        uint256 bobRewardsAfter = vault.previewRewards(bob, address(wbera));
        assertEq(bobRewardsAfter, 0, "Bob should not have any accrued rewards from transferred shares");

        // 3. If Bob claims rewards immediately, he should get nothing
        uint256 bobBalanceBefore = wbera.balanceOf(bob);
        vm.prank(bob);
        vault.claimRewards(bob);
        uint256 bobClaimed = wbera.balanceOf(bob) - bobBalanceBefore;
        assertEq(bobClaimed, 0, "Bob should not be able to claim any rewards from transferred shares");

        // 4. After some time passes, Bob should start accruing new rewards
        vm.warp(block.timestamp + 1 days);
        uint256 bobRewardsLater = vault.previewRewards(bob, address(wbera));
        assertGt(bobRewardsLater, 0, "Bob should accrue new rewards after time passes");
    }

    function test_setWhitelistedVault_access() public {
        address vaultAddress = makeAddr("vault");

        // Non-admin attempt
        vm.prank(alice);
        vm.expectRevert();
        vault.setWhitelistedVault(vaultAddress, true);

        // Admin attempt should succeed
        vm.prank(admin);
        vault.setWhitelistedVault(vaultAddress, true);
        assertTrue(vault.isWhitelistedVault(vaultAddress), "Vault should be whitelisted");

        // Admin can also unset
        vm.prank(admin);
        vault.setWhitelistedVault(vaultAddress, false);
        assertFalse(vault.isWhitelistedVault(vaultAddress), "Vault should not be whitelisted");
    }

    function test_transfer_to_whitelisted_vault_updates_vaultedShares() public {
        address vaultAddress = makeAddr("vault");
        uint256 depositAmount = 100e18;
        uint256 transferAmount = 50e18;

        // Setup: Alice deposits and vault is whitelisted
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.prank(admin);
        vault.setWhitelistedVault(vaultAddress, true);

        // Transfer to vault
        vm.prank(alice);
        vault.transfer(vaultAddress, transferAmount);

        // Check vaulted shares
        assertEq(vault.vaultedShares(alice), transferAmount, "Vaulted shares not updated correctly");
        assertEq(vault.effectiveBalance(alice), depositAmount, "Effective balance should remain unchanged");
    }

    function test_transfer_from_whitelisted_vault_fails_if_insufficient() public {
        address vaultAddress = makeAddr("vault");
        uint256 depositAmount = 100e18;
        uint256 transferAmount = 50e18;

        // Setup: Alice deposits and transfers to vault
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.prank(admin);
        vault.setWhitelistedVault(vaultAddress, true);

        vm.prank(alice);
        vault.transfer(vaultAddress, transferAmount);

        // Attempt to transfer more than vaulted shares from vault
        vm.prank(vaultAddress);
        vm.expectRevert("Insufficient vaulted shares");
        vault.transfer(bob, transferAmount + 1e18);
    }

    function test_deposit_principal_consistency() public {
        // Track total deposits
        uint256 totalDeposited;

        // Native deposit
        uint256 nativeAmount = 1 ether;
        vm.deal(alice, nativeAmount);
        vm.prank(alice);
        vault.depositNative{value: nativeAmount}(alice);
        totalDeposited += nativeAmount;

        // Regular deposit
        uint256 regularAmount = 2 ether;
        vm.prank(bob);
        vault.deposit(regularAmount, bob);
        totalDeposited += regularAmount;

        // Mint shares
        uint256 mintShares = 3 ether;
        vm.prank(charlie);
        uint256 assetsForMint = vault.mint(mintShares, charlie);
        totalDeposited += assetsForMint;

        // Verify consistency
        assertEq(vault.depositPrincipal(), totalDeposited, "depositPrincipal mismatch");
        assertEq(vault.totalSupply(), totalDeposited, "totalSupply mismatch");
        assertEq(vault.totalAssets(), totalDeposited, "totalAssets mismatch");
    }

    function test_RewardSimulationScenario1() public {
        // Initial setup
        vm.prank(admin);
        vault.unpause();

        address userA = makeAddr("userA");
        address userB = makeAddr("userB");

        // Setup initial balances and approvals
        wbera.mint(userA, 10 ether);
        wbera.mint(userB, 5 ether);
        wbera.mint(admin, 1000000 ether);

        vm.prank(userA);
        wbera.approve(address(vault), type(uint256).max);
        vm.prank(userB);
        wbera.approve(address(vault), type(uint256).max);
        vm.prank(admin);
        wbera.approve(address(vault), type(uint256).max);

        console.log("\nScenario 1: 2-day reward duration, hourly notifications over 1 week");
        console.log("==============================================");

        // Set reward duration to 2 days
        vm.prank(admin);
        vault.setRewardsDuration(address(wbera), 2 days);

        // User A deposits 10 fatBERA at hour 0
        vm.prank(userA);
        vault.deposit(10 ether, userA);
        console.log("Initial deposit - User A: 10 BERA");

        uint256 startTime = block.timestamp;

        // Simulate hourly notifications for first scenario over a week
        for (uint256 hour = 1; hour <= 168; hour++) {
            vm.warp(startTime + hour * 1 hours);

            // Calculate hourly reward: 1 BERA per day per fatBERA
            uint256 totalStaked = hour <= 24 ? 10 ether : 15 ether;
            uint256 hourlyReward = (totalStaked / 10) / 24; // Direct calculation for hourly rate

            vm.prank(admin);
            vault.notifyRewardAmount(address(wbera), hourlyReward);

            // Add User B's deposit at 24 hours
            if (hour == 24) {
                vm.prank(userB);
                vault.deposit(5 ether, userB);
                console.log("\nHour 24 - User B deposits 5 BERA");
                console.log("User A rewards: %d", vault.previewRewards(userA, address(wbera)));
                console.log("User B rewards: %d", vault.previewRewards(userB, address(wbera)));
            }

            // Log at specific intervals
            if (hour == 48 || hour == 96 || hour == 144) {
                console.log("\nHour %d", hour);
                console.log("User A rewards: %d", vault.previewRewards(userA, address(wbera)));
                console.log("User B rewards: %d", vault.previewRewards(userB, address(wbera)));
            }
        }

        // Log final state
        console.log("\nFinal State (Hour 168):");
        console.log("User A rewards: %d", vault.previewRewards(userA, address(wbera)));
        console.log("User B rewards: %d", vault.previewRewards(userB, address(wbera)));
    }

    function test_RewardSimulationScenario2() public {
        // Initial setup
        vm.prank(admin);
        vault.unpause();

        address userA = makeAddr("userA");
        address userB = makeAddr("userB");

        // Setup initial balances and approvals
        wbera.mint(userA, 10 ether);
        wbera.mint(userB, 5 ether);
        wbera.mint(admin, 1000000 ether);

        vm.prank(userA);
        wbera.approve(address(vault), type(uint256).max);
        vm.prank(userB);
        wbera.approve(address(vault), type(uint256).max);
        vm.prank(admin);
        wbera.approve(address(vault), type(uint256).max);

        console.log("\nScenario 2: 2-day reward duration, 48-hour notifications over 1 week");
        console.log("==============================================");

        // Set reward duration to 2 days
        vm.prank(admin);
        vault.setRewardsDuration(address(wbera), 2 days);

        // User A deposits for second scenario
        vm.prank(userA);
        vault.deposit(10 ether, userA);
        console.log("Initial deposit - User A: 10 BERA");

        uint256 startTime = block.timestamp;
        uint256 totalRewardsNotified = 0;

        // Simulate hourly checks but 48-hour notifications
        for (uint256 hour = 1; hour <= 168; hour++) {
            vm.warp(startTime + hour * 1 hours);

            // Notify rewards every 48 hours (2 days)
            if (hour % 48 == 0) {
                uint256 totalStaked = hour <= 24 ? 10 ether : 15 ether;
                uint256 twoDayReward = (totalStaked / 10) * 2;

                vm.prank(admin);
                vault.notifyRewardAmount(address(wbera), twoDayReward);
                totalRewardsNotified += twoDayReward;

                console.log("\nHour %d - Notified reward: %d", hour, twoDayReward);
                console.log("User A rewards: %d", vault.previewRewards(userA, address(wbera)));
                console.log("User B rewards: %d", vault.previewRewards(userB, address(wbera)));
            }

            // Add User B's deposit at 24 hours
            if (hour == 24) {
                vm.prank(userB);
                vault.deposit(5 ether, userB);
                console.log("\nHour 24 - User B deposits 5 BERA");
                console.log("User A rewards: %d", vault.previewRewards(userA, address(wbera)));
                console.log("User B rewards: %d", vault.previewRewards(userB, address(wbera)));
            }
        }

        // Log final state
        console.log("\nFinal State (Hour 168):");
        console.log("Total Rewards Notified: %d", totalRewardsNotified);
        console.log("User A rewards: %d", vault.previewRewards(userA, address(wbera)));
        console.log("User B rewards: %d", vault.previewRewards(userB, address(wbera)));
    }
}
