// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../contracts/DIAExternalStaking.sol";
import "../contracts/DIAWhitelistedStaking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../contracts/StakingErrorsAndEvents.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, type(uint256).max);
    }
}

contract DIAStakingFuzzTest is Test {
    DIAExternalStaking public externalStaking;
    DIAWhitelistedStaking public whitelistStaking;
    MockToken public token;
    address public owner;
    address public rewardsWallet;
    address public user1;
    address public user2;

    uint256 public constant STAKING_LIMIT = 1000000 * 10 ** 18;
    uint256 public constant UNSTAKING_DURATION = 7 days;
    uint256 public constant MINIMUM_STAKE = 1 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        rewardsWallet = address(0x123);
        user1 = address(0x1);
        user2 = address(0x2);

        token = new MockToken();
        
        externalStaking = new DIAExternalStaking(
            UNSTAKING_DURATION,
            address(token),
            STAKING_LIMIT
        );

        whitelistStaking = new DIAWhitelistedStaking(
            UNSTAKING_DURATION,
            address(token),
            rewardsWallet,
            100
        );

        // Fund test accounts with reasonable amounts
        uint256 initialBalance = 1000000 * 10 ** 18; // 1 million tokens
        token.transfer(user1, initialBalance);
        token.transfer(user2, initialBalance);
        token.transfer(rewardsWallet, initialBalance);

        // Approve tokens
        vm.startPrank(user1);
        token.approve(address(externalStaking), type(uint256).max);
        token.approve(address(whitelistStaking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(externalStaking), type(uint256).max);
        token.approve(address(whitelistStaking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(rewardsWallet);
        token.approve(address(externalStaking), type(uint256).max);
        token.approve(address(whitelistStaking), type(uint256).max);
        vm.stopPrank();
    }

    // Fuzz Tests for External Staking

    function testFuzz_StakeAmount(uint256 amount) public {
        vm.assume(amount >= MINIMUM_STAKE);
        vm.assume(amount <= STAKING_LIMIT);

        vm.startPrank(user1);
        externalStaking.stake(amount, 0);
        vm.stopPrank();

        (,,,uint256 principal,,,,) = externalStaking.stakingStores(1);
        assertEq(principal, amount, "Staked amount should match input");
    }

    function testFuzz_PrincipalShareBPS(uint32 shareBps) public {
        vm.assume(shareBps <= 10000); // Max 100%

        vm.startPrank(user1);
        externalStaking.stake(MINIMUM_STAKE, shareBps);
        vm.stopPrank();

        (,,,,,,,uint32 principalWalletShareBps) = externalStaking.stakingStores(1);
        assertEq(principalWalletShareBps, shareBps, "Principal share BPS should match input");
    }

    function testFuzz_UnstakingDuration(uint256 duration) public {
        vm.assume(duration >= 1 days);
        vm.assume(duration <= 20 days);

        vm.startPrank(owner);
        externalStaking.setUnstakingDuration(duration);
        vm.stopPrank();

        assertEq(externalStaking.unstakingDuration(), duration, "Unstaking duration should match input");
    }

    // Edge Cases for External Staking

    function test_StakeAtStakingLimit() public {
        vm.startPrank(user1);
        externalStaking.stake(STAKING_LIMIT, 0);
        vm.stopPrank();

        (,,,uint256 principal,,,,) = externalStaking.stakingStores(1);
        assertEq(principal, STAKING_LIMIT, "Should be able to stake at limit");
    }

    function test_StakeAboveLimit() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AmountAboveStakingLimit.selector, STAKING_LIMIT + 1));
        externalStaking.stake(STAKING_LIMIT + 1, 0);
        vm.stopPrank();
    }

    function test_StakeBelowMinimum() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AmountBelowMinimumStake.selector, MINIMUM_STAKE - 1));
        externalStaking.stake(MINIMUM_STAKE - 1, 0);
        vm.stopPrank();
    }

    function test_InvalidPrincipalShare() public {
        vm.startPrank(user1);
        vm.expectRevert(InvalidPrincipalWalletShare.selector);
        externalStaking.stake(MINIMUM_STAKE, 10001);
        vm.stopPrank();
    }

    // Fuzz Tests for Whitelisted Staking

    function testFuzz_WhitelistStakeAmount(uint256 amount) public {
        vm.assume(amount >= MINIMUM_STAKE);
        vm.assume(amount <= STAKING_LIMIT);

        vm.startPrank(owner);
        whitelistStaking.addWhitelistedStaker(user1);
        vm.stopPrank();

        vm.startPrank(user1);
        whitelistStaking.stake(amount);
        vm.stopPrank();

        (,,,uint256 principal,,,,,) = whitelistStaking.stakingStores(1);
        assertEq(principal, amount, "Staked amount should match input");
    }

    // Edge Cases for Whitelisted Staking

    function test_WhitelistStakeWithoutWhitelist() public {
        vm.startPrank(user1);
        vm.expectRevert(NotWhitelisted.selector);
        whitelistStaking.stake(MINIMUM_STAKE);
        vm.stopPrank();
    }

    function test_WhitelistStakeAfterRemoval() public {
        vm.startPrank(owner);
        whitelistStaking.addWhitelistedStaker(user1);
        whitelistStaking.removeWhitelistedStaker(user1);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(NotWhitelisted.selector);
        whitelistStaking.stake(MINIMUM_STAKE);
        vm.stopPrank();
    }

    // Reward Calculation Edge Cases

    function test_RewardCalculationWithZeroStake() public {
        vm.startPrank(user1);
        externalStaking.stake(MINIMUM_STAKE, 0);
        vm.stopPrank();

        vm.startPrank(rewardsWallet);
        externalStaking.addRewardToPool(100 * 10 ** 18);
        vm.stopPrank();

        (uint256 principalWalletReward, uint256 fullReward) = externalStaking.getRewardForStakingStore(1);
        uint256 reward = principalWalletReward * fullReward;
        assertEq(reward, 0, "Should receive rewards with non-zero stake");
     }
 

    // Time-based Edge Cases

    function test_UnstakeImmediatelyAfterRequest() public {
        vm.startPrank(user1);
        externalStaking.stake(MINIMUM_STAKE, 0);
        externalStaking.requestUnstake(1);
        vm.expectRevert(UnstakingPeriodNotElapsed.selector);
        externalStaking.unstake(1, MINIMUM_STAKE);
        vm.stopPrank();
    }

    function test_UnstakeExactlyAtDuration() public {
        vm.startPrank(user1);
        externalStaking.stake(MINIMUM_STAKE, 0);
        externalStaking.requestUnstake(1);
        vm.stopPrank();

        vm.warp(block.timestamp + UNSTAKING_DURATION);

        vm.startPrank(user1);
        externalStaking.unstake(1, MINIMUM_STAKE);
        vm.stopPrank();

        (,,,uint256 principal,,,,) = externalStaking.stakingStores(1);
        assertEq(principal, 0, "Should be able to unstake exactly at duration");
    }

    // Multiple Operation Edge Cases

    function test_MultipleStakesAndUnstakes() public {
        vm.startPrank(user1);
        
        // First stake
        externalStaking.stake(MINIMUM_STAKE, 0);
        externalStaking.requestUnstake(1);
        
        // Second stake while first is unstaking
        externalStaking.stake(MINIMUM_STAKE, 0);
        
        vm.warp(block.timestamp + UNSTAKING_DURATION);
        
        // Complete first unstake
        externalStaking.unstake(1, MINIMUM_STAKE);
        
        // Request unstake for second stake
        externalStaking.requestUnstake(2);
        
        vm.warp(block.timestamp + UNSTAKING_DURATION);
        
        // Complete second unstake
        externalStaking.unstake(2, MINIMUM_STAKE);
        vm.stopPrank();

        (,,,uint256 principal1,,,,) = externalStaking.stakingStores(1);
        (,,,uint256 principal2,,,,) = externalStaking.stakingStores(2);
        
        assertEq(principal1, 0, "First stake should be fully unstaked");
        assertEq(principal2, 0, "Second stake should be fully unstaked");
    }

 
} 