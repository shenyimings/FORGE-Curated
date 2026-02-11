// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Stake} from "../contracts/Stake.sol";
import {StakeSweeper} from "../contracts/StakeSweeper.sol";
import {MockERC1363} from "./mocks/MockERC1363.sol";
import {MockUniswapRouter} from "./mocks/MockUniswapRouter.sol";

contract StakeSweepTest is Test {
    Stake public stake;
    MockERC1363 public stakingToken;
    MockERC1363 public rewardToken;
    MockERC1363 public extraToken; // Token to be swept
    MockUniswapRouter public router;
    StakeSweeper public sweeper;
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 public constant EXTRA_TOKEN_AMOUNT = 100 ether;
    uint256 public constant EXCHANGE_RATE = 2; // 1 extra token = 2 reward tokens

    function setUp() public {
        // Deploy tokens and stake contracts as owner
        vm.startPrank(owner);

        // Create tokens for staking, rewards, and an extra token to sweep
        stakingToken = new MockERC1363(INITIAL_SUPPLY);
        rewardToken = new MockERC1363(INITIAL_SUPPLY);
        extraToken = new MockERC1363(INITIAL_SUPPLY);

        // Deploy stake contract
        stake = new Stake(address(stakingToken), address(rewardToken));

        // Deploy mock router
        router = new MockUniswapRouter();
        // Set exchange rate in the router
        router.setExchangeRate(EXCHANGE_RATE);

        // Deploy sweeper contract
        sweeper = new StakeSweeper(address(rewardToken), address(router));

        // Fund the router with reward tokens so it can perform swaps
        rewardToken.transfer(address(router), INITIAL_SUPPLY / 10);

        // Send some extraToken to the staking contract (simulating a token that needs to be swept)
        extraToken.transfer(address(stake), EXTRA_TOKEN_AMOUNT);

        vm.stopPrank();
    }

    function test_SweepBasic() public {
        // Stake some tokens to begin with
        vm.startPrank(owner);
        stakingToken.approve(address(stake), 100 ether);
        stake.deposit(100 ether);
        vm.stopPrank();

        // Initial state
        assertEq(extraToken.balanceOf(address(stake)), EXTRA_TOKEN_AMOUNT);
        uint256 initialRewardBalance = rewardToken.balanceOf(address(stake));

        // Set router first
        vm.startPrank(owner);
        stake.setSweeper(address(sweeper));

        vm.warp(block.timestamp + 1 days + 1);

        // Expect TokenSwept event
        vm.expectEmit(true, false, false, false);
        emit Stake.TokenSwept(address(extraToken), EXTRA_TOKEN_AMOUNT, EXTRA_TOKEN_AMOUNT * EXCHANGE_RATE);

        // Call sweep function with just the token parameter
        uint256 amountReceived = stake.sweep(address(extraToken));

        // Verify sweep results
        assertEq(amountReceived, EXTRA_TOKEN_AMOUNT * EXCHANGE_RATE);
        assertEq(extraToken.balanceOf(address(stake)), 0); // All extra tokens should be gone

        // Verify rewards increased
        uint256 finalRewardBalance = rewardToken.balanceOf(address(stake));
        assertEq(finalRewardBalance, initialRewardBalance + amountReceived);

        // Verify lastRewardBalance was updated to include the new rewards
        assertEq(stake.lastRewardBalance() * stake.rewardDecayFactor(), finalRewardBalance);

        vm.stopPrank();
    }

    function test_SweepWithSweeper() public {
        // Send more extraToken to the stake contract for this test
        vm.startPrank(owner);
        extraToken.transfer(address(stake), EXTRA_TOKEN_AMOUNT);

        // Set sweeper
        vm.expectEmit(true, false, false, false);
        emit Stake.SweeperSet(address(sweeper));
        stake.setSweeper(address(sweeper));
        vm.stopPrank();

        // Check initial state
        assertEq(extraToken.balanceOf(address(stake)), EXTRA_TOKEN_AMOUNT * 2);
        uint256 initialRewardBalance = rewardToken.balanceOf(address(stake));

        // Sweep using the default router as a regular user
        vm.startPrank(user);

        // Expect TokenSwept event with correct parameters
        vm.expectEmit(true, false, false, false);
        emit Stake.TokenSwept(address(extraToken), EXTRA_TOKEN_AMOUNT * 2, EXTRA_TOKEN_AMOUNT * 2 * EXCHANGE_RATE);

        // Call sweep function with just the token parameter (using default router)
        uint256 amountReceived = stake.sweep(address(extraToken));

        // Verify sweep results
        assertEq(amountReceived, EXTRA_TOKEN_AMOUNT * 2 * EXCHANGE_RATE);
        assertEq(extraToken.balanceOf(address(stake)), 0); // All extra tokens should be gone

        // Verify rewards increased
        uint256 finalRewardBalance = rewardToken.balanceOf(address(stake));
        assertEq(finalRewardBalance, initialRewardBalance + amountReceived);

        vm.stopPrank();
    }

    function test_SweepByAnyUser() public {
        // Show that any user (not just the owner) can call sweep
        assertEq(extraToken.balanceOf(address(stake)), EXTRA_TOKEN_AMOUNT);
        uint256 initialRewardBalance = rewardToken.balanceOf(address(stake));

        // Set router first (as owner)
        vm.prank(owner);
        stake.setSweeper(address(sweeper));

        // Sweep as a regular user (not owner)
        vm.startPrank(user);

        // Call sweep function with just the token parameter
        uint256 amountReceived = stake.sweep(address(extraToken));

        // Verify sweep results
        assertEq(amountReceived, EXTRA_TOKEN_AMOUNT * EXCHANGE_RATE);
        assertEq(extraToken.balanceOf(address(stake)), 0); // All extra tokens should be gone

        // Verify rewards increased
        uint256 finalRewardBalance = rewardToken.balanceOf(address(stake));
        assertEq(finalRewardBalance, initialRewardBalance + amountReceived);

        vm.stopPrank();
    }

    function test_RevertSweepStakingToken() public {
        // Set router first
        vm.startPrank(owner);
        stake.setSweeper(address(sweeper));

        vm.expectRevert("Stake: cannot sweep staking token");
        stake.sweep(address(stakingToken));

        vm.stopPrank();
    }

    function test_RevertSweepRewardToken() public {
        // Set router first
        vm.startPrank(owner);
        stake.setSweeper(address(sweeper));

        vm.expectRevert("Stake: cannot sweep reward token");
        stake.sweep(address(rewardToken));

        vm.stopPrank();
    }

    // This test is no longer applicable since we don't allow specifying a custom router
    // We test for the default router not being set instead

    function test_RevertSweepNoTokens() public {
        // Setup a new token with zero balance in the contract
        MockERC1363 emptyToken = new MockERC1363(1000 ether);

        // Set router first
        vm.startPrank(owner);
        stake.setSweeper(address(sweeper));

        vm.expectRevert("Stake: no tokens to sweep");
        stake.sweep(address(emptyToken));

        vm.stopPrank();
    }

    function test_RevertNoSweeper() public {
        // Try to use sweep without a default router set
        vm.expectRevert("Stake: sweeper not set");
        stake.sweep(address(extraToken));
    }

    function test_SetRouterNotOwner() public {
        // Try to set router as non-owner
        vm.startPrank(user);
        bytes memory encodedErrorSelector = abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user);
        vm.expectRevert(encodedErrorSelector);
        stake.setSweeper(address(sweeper));
        vm.stopPrank();
    }

    function test_SetSweeperZeroAddress() public {
        // Try to set sweeper to zero address
        vm.startPrank(owner);
        vm.expectRevert("Stake: sweeper is the zero address");
        stake.setSweeper(address(0));
        vm.stopPrank();
    }

    // These tests are no longer needed
    // All trades will go through regardless of output amount since amountOutMin is fixed at 0
    // Transactions won't expire within the test execution time since deadline is fixed at 24 hours from now
}
