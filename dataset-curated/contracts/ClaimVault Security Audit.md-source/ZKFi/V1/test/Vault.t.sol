// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/IVault.sol";
import "./MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VaultTest is Test {
    Vault public vault;
    MockERC20 public token;
    address public owner = address(1);
    address public user = address(2);
    address public ceffu = address(3);

    function setUp() public {
        vm.startPrank(owner);

        // Create new Contract
        token = new MockERC20();

        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = address(token);
        uint256[] memory rewardRate = new uint256[](1);
        rewardRate[0] = 700;
        uint256[] memory minStakeAmount = new uint256[](1);
        minStakeAmount[0] = 0;
        uint256[] memory maxStakeAmount = new uint256[](1);
        maxStakeAmount[0] = type(uint256).max;

        vault = new Vault(
            supportedTokens, 
            rewardRate,
            minStakeAmount, 
            maxStakeAmount, 
            owner, // admin
            owner, // bot
            ceffu, 
            14 days
        );

        vm.stopPrank();

        vm.warp(block.timestamp + 1);
    }

    function testStake() public {
        // should be zero if user does not stake anything
        uint256 claimableAssets = vault.getClaimableAssets(user, address(token));
        uint256 claimableRewards = vault.getClaimableRewards(user, address(token));
        uint256 totalRewards = vault.getTotalRewards(user, address(token));
        assertEq(claimableAssets, 0);
        assertEq(claimableRewards, 0);
        assertEq(totalRewards, 0);

        vm.startPrank(user);
        token.mint(user, 1000 ether);
        token.approve(address(vault), 500 ether);

        // Stake 500 tokens
        vault.stake_66380860(address(token), 500 ether);

        // Check user's staked amount
        uint256 stakedAmount = vault.getStakedAmount(user, address(token));
        assertEq(stakedAmount, 500 ether);

        // Ensure Vault's token balance updated
        assertEq(token.balanceOf(address(vault)), 500 ether);

        vm.stopPrank();
    }

    function testRequestClaim() public {
        vm.startPrank(user);
        token.mint(user, 500 ether);
        token.approve(address(vault), 500 ether);

        // Stake tokens
        vault.stake_66380860(address(token), 500 ether);

        // Request to withdraw 500 tokens
        uint256 requestID = vault.requestClaim_8135334(address(token), 500 ether);

        // Validate the withdrawal request
        ClaimItem memory claimItem = vault.getClaimQueueInfo(requestID);
        assertEq(claimItem.totalAmount, 500 ether);
        assertEq(claimItem.token, address(token));

        vm.stopPrank();
    }

    function testSetStakeLimit() public {
        vm.startPrank(owner);

        vault.setStakeLimit(address(token), 1, 2);
        assertEq(vault.minStakeAmount(address(token)), 1);
        assertEq(vault.maxStakeAmount(address(token)), 2);

        vm.stopPrank();
    }

    // 1. stake 500 ether for 1 year
    // 2. request: principal + reward
    // 3. wait for 14 days
    // 4. claim
    function testClaimAssets_Scenario_A() public {
        uint256 tvl = vault.getTVL(address(token));
        assertEq(tvl, 0);

        vm.startPrank(user);
        token.mint(user, 500 ether);
        token.approve(address(vault), 500 ether);

        uint256 stakeTime = block.timestamp;
        vault.stake_66380860(address(token), 500 ether);

        tvl = vault.getTVL(address(token));
        assertEq(tvl, 500 ether);

        vm.warp(block.timestamp + 365.25 days);
        uint256 claimableAssets = vault.getClaimableAssets(user, address(token));
        assertEq(claimableAssets, 535 ether);

        uint256 requestID = vault.requestClaim_8135334(address(token), type(uint256).max);

        tvl = vault.getTVL(address(token));
        assertEq(tvl, 500 ether);

        vm.expectRevert();
        vault.requestClaim_8135334(address(token), 1); // no claimable assets

        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);
        // owner fetches assets from ceffu
        token.mint(address(vault), 35 ether);

        vm.startPrank(user);
        vault.claim_41202704(requestID);
        assertEq(token.balanceOf(address(vault)), 0);
        // Reward = (stakedAmount * rewardRate * elapsedTime) / (secondsInYear * 100)
        //        = (500 ether * 700 * 365days) / (365days * 10000)
        //        = 35 ether
        // Principal = 500 ether
        // Total claimable assets = Reward + Principal = 535 ether
        assertEq(token.balanceOf(user), 535 ether);

        tvl = vault.getTVL(address(token));
        assertEq(tvl, 0);

        StakeItem memory stakeItem = vault.getStakeHistory(user, address(token), 0);
        assertEq(stakeItem.token, address(token));
        assertEq(stakeItem.user, user);
        assertEq(stakeItem.amount, 500 ether);
        assertEq(stakeItem.stakeTimestamp, stakeTime);
        
        ClaimItem memory claimItem = vault.getClaimHistory(user, address(token), 0);
        assertEq(claimItem.token, address(token));
        assertEq(claimItem.user, user);
        assertEq(claimItem.totalAmount, 535 ether);
        assertEq(claimItem.claimTime, block.timestamp);

        vm.stopPrank();
    }

    // 1. stake 500 ether for 1 year
    // 2. stake 500 ether for 1 year again
    // 3. wait for 14 days
    // 4. claim
    function testClaimAssets_Scenario_B() public {

        vm.startPrank(user);
        token.mint(user, 1_000 ether);
        token.approve(address(vault), 1_000 ether);

        vault.stake_66380860(address(token), 500 ether);
        vm.warp(block.timestamp + 365.25 days); // reward: 35 ether

        vault.stake_66380860(address(token), 500 ether);
        uint256 targetClaimableRewardsAmount = vault.getClaimableRewardsWithTargetTime(user, address(token), block.timestamp + 365.25 days);
        //   reward:               70 ether(stake 1_000 ether for 1 year)
        //   newAccumulatedReward: 35 ether
        assertEq(targetClaimableRewardsAmount, 105 ether);

        uint256 claimableAssets = vault.getClaimableAssets(user, address(token));
        assertEq(claimableAssets, 500 ether + 500 ether + 35 ether);

        vm.warp(block.timestamp + 365.25 days);

        // owner fetches assets from ceffu
        token.mint(address(vault), 105 ether);

        // testing some view functions
        uint256 stakedAmount = vault.getStakedAmount(user, address(token));
        assertEq(stakedAmount, 1_000 ether);
        uint256 contractTokenBalance = vault.getContractBalance(address(token));
        assertEq(contractTokenBalance, 1_000 ether + 105 ether);
        (uint256 rewardRate, ) = vault.getCurrentRewardRate(address(token));
        assertEq(rewardRate, 700);

        uint256 requestID = vault.requestClaim_8135334(address(token), 500 ether + 500 ether + 105 ether);
        uint256[] memory userIDs = vault.getClaimQueueIDs(user, address(token));
        assertEq(userIDs[0], requestID);

        vm.warp(block.timestamp + 14 days);

        vault.claim_41202704(requestID);
        assertEq(token.balanceOf(user), 500 ether + 500 ether + 105 ether);
        assertEq(token.balanceOf(address(vault)), 0);
        vm.stopPrank();

        ClaimItem memory queueItem = vault.getClaimQueueInfo(1);
        assertEq(queueItem.token, address(token));
        assertEq(queueItem.user, user);
        assertEq(queueItem.totalAmount, 500 ether + 500 ether + 105 ether);
        assertEq(queueItem.claimTime, block.timestamp);

        uint256 totalRewards = vault.getTotalRewards(user, address(token));
        assertEq(totalRewards, 105 ether);
    }

    // 1. stake 500 ether for 1 year
    // 2. set the reward from 700 to 1400
    // 3. stake 500 ether for 1 year again
    // 4. wait for 14 days
    // 5. claim
    function testClaimAssets_Scenario_C() public {

        vm.startPrank(user);
        token.mint(user, 1_000 ether);
        token.approve(address(vault), 1_000 ether);

        vault.stake_66380860(address(token), 500 ether);
        vm.warp(block.timestamp + 365.25 days); // reward: 35 ether
        vm.stopPrank();

        //   reward:               35 ether(stake 500 ether for 1 year, rate=700)
        //   newAccumulatedReward: 0

        vm.startPrank(owner);
        vault.setRewardRate(address(token), 1400);
        vm.stopPrank();

        vm.startPrank(user);
        vault.stake_66380860(address(token), 500 ether);

        uint256 targetClaimableRewardsAmount = vault.getClaimableRewardsWithTargetTime(user, address(token), block.timestamp + 365.25 days);
        //   reward:               140 ether(stake 1_000 ether for 1 year, rate=1400)
        //   newAccumulatedReward: 35 ether
        assertEq(targetClaimableRewardsAmount, 175 ether);
        vm.warp(block.timestamp + 365.25 days);

        uint256 requestID = vault.requestClaim_8135334(address(token), 500 ether + 500 ether + 175 ether);

        // owner fetches assets from ceffu
        token.mint(address(vault), 175 ether);

        vm.warp(block.timestamp + 14 days);

        vault.claim_41202704(requestID);
        assertEq(token.balanceOf(user), 500 ether + 500 ether + 175 ether);
        assertEq(token.balanceOf(address(vault)), 0);
        vm.stopPrank();

        ClaimItem memory queueItem = vault.getClaimQueueInfo(1);
        assertEq(queueItem.token, address(token));
        assertEq(queueItem.user, user);
        assertEq(queueItem.totalAmount, 500 ether + 500 ether + 175 ether);
        assertEq(queueItem.claimTime, block.timestamp);
    }

    // 1. stake 500 ether for 1 year
    // 2. request: principal
    // 3. request: reward
    // 4. wait for 14 days
    // 5. claim
    function testClaimAssets_Scenario_D() public {
        vm.startPrank(user);
        token.mint(user, 500 ether);
        token.approve(address(vault), 500 ether);

        uint256 stakeTime = block.timestamp;
        vault.stake_66380860(address(token), 500 ether);

        vm.warp(block.timestamp + 365.25 days);
        uint256 claimablePrincipal = vault.getStakedAmount(user, address(token));
        uint256 claimableAssets = vault.getClaimableAssets(user, address(token));
        uint256 claimableRewards = claimableAssets - claimablePrincipal;
        assertEq(claimableAssets, 535 ether);
        assertEq(claimablePrincipal, 500 ether);
        assertEq(claimableRewards, 35 ether);

        uint256 requestID1 = vault.requestClaim_8135334(address(token), claimablePrincipal);
        uint256 requestID2 = vault.requestClaim_8135334(address(token), claimableRewards);

        uint256 tvl = vault.getTVL(address(token));
        assertEq(tvl, 500 ether);

        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);
        // owner fetches assets from ceffu
        token.mint(address(vault), 35 ether);

        vm.startPrank(user);
        vault.claim_41202704(requestID1);
        vault.claim_41202704(requestID2);
        assertEq(token.balanceOf(address(vault)), 0);
        // Reward = (stakedAmount * rewardRate * elapsedTime) / (secondsInYear * 100)
        //        = (500 ether * 700 * 365days) / (365days * 10000)
        //        = 35 ether
        // Principal = 500 ether
        // Total claimable assets = Reward + Principal = 535 ether
        assertEq(token.balanceOf(user), 535 ether);

        StakeItem memory stakeItem = vault.getStakeHistory(user, address(token), 0);
        assertEq(stakeItem.token, address(token));
        assertEq(stakeItem.user, user);
        assertEq(stakeItem.amount, 500 ether);
        assertEq(stakeItem.stakeTimestamp, stakeTime);
        
        // principal
        ClaimItem memory claimItem1 = vault.getClaimHistory(user, address(token), 0);
        assertEq(claimItem1.token, address(token));
        assertEq(claimItem1.user, user);
        assertEq(claimItem1.totalAmount, 500 ether);
        assertEq(claimItem1.claimTime, block.timestamp);
        // rewards
        ClaimItem memory claimItem2 = vault.getClaimHistory(user, address(token), 1);
        assertEq(claimItem2.token, address(token));
        assertEq(claimItem2.user, user);
        assertEq(claimItem2.totalAmount, 35 ether);
        assertEq(claimItem2.claimTime, block.timestamp);

        uint256[] memory IDs = vault.getClaimQueueIDs(user, address(token));
        assertEq(IDs.length, 0);

        tvl = vault.getTVL(address(token));
        assertEq(tvl, 0);

        vm.stopPrank();
    }

    function testSetAndTransferToCeffu() public {
        vm.startPrank(owner);

        address newCeffuAddress = address(4);
        vault.setCeffu(address(newCeffuAddress));

        vm.expectRevert();
        vault.setCeffu(address(0));

        token.mint(address(vault), 1000 ether);
        vault.transferToCeffu(address(token), 1000 ether);
        assertEq(token.balanceOf(address(vault)), 0 ether);
        assertEq(token.balanceOf(address(vault.ceffu())), 1000 ether);

        vm.stopPrank();
    }

    function testAddSupportedToken() public {
        vm.startPrank(owner);

        address usdt = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);

        vault.addSupportedToken(usdt, 1, 2);
        assertEq(vault.supportedTokens(usdt), true);

        vm.stopPrank();
    }

    function testSetWaitingTime() public {
        vm.startPrank(owner);

        vault.setWaitingTime(15 days);
        assertEq(vault.WAITING_TIME(), 15 days);

        vm.stopPrank();
    }

    function testEmergencyWithdraw() public {
        vm.startPrank(owner);

        token.mint(address(vault), 1000 ether);
        vault.emergencyWithdraw(address(token), owner);
        assertEq(token.balanceOf(owner), 1000 ether);

        vm.stopPrank();
    }

    function testGetTVL() public {
        uint256 tvl = vault.getTVL(address(token));
        assertEq(tvl, 0);

        vm.startPrank(user);
        token.mint(user, 500 ether);
        token.approve(address(vault), 500 ether);

        vault.stake_66380860(address(token), 500 ether);

        tvl = vault.getTVL(address(token));
        assertEq(tvl, 500 ether);

        vm.warp(block.timestamp + 365.25 days);

        // rewards: 35 ether, principal: 101 ether
        uint256 requestID = vault.requestClaim_8135334(address(token), 136 ether);

        tvl = vault.getTVL(address(token));
        assertEq(tvl, 500 ether);

        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);
        // owner fetches assets from ceffu
        token.mint(address(vault), 36 ether);

        vm.startPrank(user);
        vault.claim_41202704(requestID);

        tvl = vault.getTVL(address(token));
        assertEq(tvl, 500 ether - 101 ether);

        vm.stopPrank();
    }    
}
