// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../contracts/DIAWhitelistedStaking.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../contracts/DIAStakingCommons.sol";


// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Test contract for DIAWhitelistedStaking
contract DIAWhitelistedStakingTest is Test {
    DIAWhitelistedStaking stakingContract;
    IERC20 stakingToken;
    address owner = address(this);
    address user = address(0x123);
    address user2 = address(0x222);

    address rewardsWallet = address(0x124);

        uint256 constant STAKING_LIMIT = 100000000 * 10 ** 18;


    uint256 constant STAKE_AMOUNT = 100 * 10 ** 18;
    uint256 constant INITIAL_USER_BALANCE = 1000 * 10 ** 18;
    uint256 constant INITIAL_CONTRACT_BALANCE = 1000 * 10 ** 18;

    address[10] users;

    // Setup function for initializing contracts and balances
    function setUp() public {
        stakingToken = IERC20(address(new MockERC20("TestToken", "TT", 18)));
        stakingContract = new DIAWhitelistedStaking(
            3 days,
            address(stakingToken),
            rewardsWallet,
            100
        );

                stakingContract.setDailyWithdrawalThreshold(1);


        deal(address(stakingToken), user, INITIAL_USER_BALANCE);
        deal(address(stakingToken), owner, INITIAL_USER_BALANCE);

        deal(address(stakingToken), rewardsWallet, 10000000 * 10 ** 18);
        deal(
            address(stakingToken),
            address(stakingContract),
            INITIAL_CONTRACT_BALANCE
        );

        for (uint i = 0; i < 10; i++) {
            users[i] = address(uint160(i + 1));
            deal(address(stakingToken), users[i], INITIAL_USER_BALANCE);
        }

        vm.startPrank(rewardsWallet);
        stakingToken.approve(address(stakingContract), 10000000 * 10 ** 18);
        vm.stopPrank();
    }

    // Helper function for staking tokens
    function stakeTokens(uint256 amount) internal {
        vm.startPrank(owner);

        stakingContract.addWhitelistedStaker(address(user));
        vm.startPrank(user);
        stakingToken.approve(address(stakingContract), amount);
        stakingContract.stake(amount);
        vm.stopPrank();
    }

    function stakeForTokens(uint256 amount, address user) internal {
        vm.startPrank(owner);

        stakingContract.addWhitelistedStaker(address(user));
        stakingToken.approve(address(stakingContract), amount);
        console.log("stakeforaddress");

        stakingContract.stakeForAddress(user, amount, 0);
        vm.stopPrank();
    }

    // Test staking functionality
    function testStake() public {
        uint256 initialUserBalance = stakingToken.balanceOf(user);
        uint256 initialContractBalance = stakingToken.balanceOf(
            address(stakingContract)
        );

        stakeTokens(STAKE_AMOUNT);

        uint256 finalUserBalance = stakingToken.balanceOf(user);
        uint256 finalContractBalance = stakingToken.balanceOf(
            address(stakingContract)
        );

        // Ensure balances are updated correctly
        assertEq(
            finalContractBalance,
            initialContractBalance + STAKE_AMOUNT,
            "Contract balance should increase"
        );
        assertEq(
            finalUserBalance,
            initialUserBalance - STAKE_AMOUNT,
            "User balance should decrease"
        );

        // Verify staking store
        (address beneficiary, , , uint256 principal, , , , , ) = stakingContract
            .stakingStores(1);
        assertEq(beneficiary, user, "Beneficiary should match the user");
        assertEq(
            principal,
            STAKE_AMOUNT,
            "Principal should match the staked amount"
        );
    }

    // Test unstaking request
    function testRequestUnstake() public {
        testStake();
        vm.startPrank(user);
        stakingContract.requestUnstake(1);
        (, , , , , , , uint256 unstakingRequestTime, ) = stakingContract
            .stakingStores(1);

        console.log("Unstaking request time", unstakingRequestTime);
        // You may assert unstakingRequestTime here if needed
        // assertGt(unstakingRequestTime, 0, "Unstaking request time should be greater than 0");
    }

    // Test unstaking after the period
    function testUnstake() public {
        stakeTokens(STAKE_AMOUNT);
        vm.startPrank(user);
        stakingContract.requestUnstake(1);

        // Fast-forward time by 4 days
        vm.warp(block.timestamp + 4 days);

        stakingContract.unstake(1);
        vm.stopPrank();

        // Verify reward is zero after unstake (no rewards accumulated in this test)
        (, , , , uint256 reward, , , , ) = stakingContract.stakingStores(1);
        assertEq(reward, 0, "Reward should be zero after unstaking");
    }

    

    // Test reward accumulation over time
    function testRewardAccumulation() public {
        stakeTokens(STAKE_AMOUNT);

        // Simulate time passing (5 days)
        vm.warp(block.timestamp + 5 days);

        // Calculate the expected reward and verify (stubbed for now)
        // uint256 expectedReward = ...;
        // uint256 actualReward = stakingContract.getRewardForStakingStore(1);
        // assertApproxEqRel(actualReward, expectedReward, 0.01e18);
    }

    // Test if unstaking fails before the period has elapsed
    function testUnstakeBeforePeriodFails() public {
        testStake();
        vm.startPrank(user);
        stakingContract.requestUnstake(1);

        // Fast-forward time by only 2 days (not enough to unstake)
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(
            UnstakingPeriodNotElapsed.selector
        );
        stakingContract.unstake(1);
    }

    // Test if unstaking without request fails
    function testUnstakeWithoutRequestFails() public {
        testStake();
        vm.startPrank(user);

        // Attempt unstake without requesting
        vm.expectRevert(UnstakingNotRequested.selector);
        stakingContract.unstake(1);
    }

    // TODO: Test full stake and unstake flow
    // function testFullStakeAndUnstake() public {
    //     stakeForTokens(STAKE_AMOUNT, user);
    //     vm.startPrank(user);
    //     stakingContract.requestUnstake(1);

    //     // Fast-forward time by 4 days
    //     vm.warp(block.timestamp + 4 days);

    //     vm.startPrank(address(0x044));

    //     stakingContract.unstake(1);
    //     uint256 rewardBeforeUnstake = stakingContract.getRewardForStakingStore(
    //         1
    //     );

    //     console.log("INITIAL_USER_BALANCE", INITIAL_USER_BALANCE);
    //     console.log("rewardBeforeUnstake unstakePrincipal", rewardBeforeUnstake);

    //     vm.expectRevert();
    //     stakingContract.unstakePrincipal(1);

    //     vm.stopPrank();

    //     // Verify user balance is restored after unstake

    //     assertEq(
    //         stakingToken.balanceOf(user),
    //         INITIAL_USER_BALANCE + rewardBeforeUnstake,
    //         "User balance should be restored after unstake"
    //     );
    // }

    function testUnAuthorizedUnstake() public {
        testStake();
                vm.warp(block.timestamp + 4 days);

  

       

        vm.startPrank(user);
        stakingContract.requestUnstake(1);
                vm.warp(block.timestamp + 60 days);

         

        vm.startPrank(address(0x001));

        vm.expectRevert(NotPrincipalUnstaker.selector);
        stakingContract.unstakePrincipal(1,100);

        vm.stopPrank();

        // Verify user balance is restored after unstake
    }


    function test_UnstakingPeriodNotElapsed() public {
        testStake();
        vm.startPrank(user);
        stakingContract.requestUnstake(1);


        // Fast-forward time by 4 days
        // vm.warp(block.timestamp + 4 days);

        vm.expectRevert(UnstakingPeriodNotElapsed.selector);

        stakingContract.unstake(1);
 
     }

    // Helper function for staking tokens
    function stakeTokensforUser(address u, uint256 amount) internal {
        vm.startPrank(owner);
        stakingContract.addWhitelistedStaker(u);
        vm.startPrank(u);
        stakingToken.approve(address(stakingContract), amount);
        stakingContract.stake(amount);
        vm.stopPrank();
    }

    function testMultipleStakeUnstakeUsers() public {
        uint256 initialContractBalance = stakingToken.balanceOf(
            address(stakingContract)
        );

        // Stake tokens for 10 users
        for (uint i = 0; i < 10; i++) {
            stakeTokensforUser(users[i], STAKE_AMOUNT);
        }

        // Check final contract balance and ensure it increased by the total amount staked by all users
        uint256 finalContractBalance = stakingToken.balanceOf(
            address(stakingContract)
        );
        uint256 totalStakedAmount = STAKE_AMOUNT * 10;

        assertEq(
            finalContractBalance,
            initialContractBalance + totalStakedAmount,
            "Contract balance should reflect total staking amount"
        );

        // Verify that each user has their staking store registered
        for (uint i = 0; i < 10; i++) {
            (
                address beneficiary,
                ,
                ,
                uint256 principal,
                ,
                ,
                ,
                ,
                

            ) = stakingContract.stakingStores(i + 1);
            assertEq(
                beneficiary,
                users[i],
                "Beneficiary should match the user"
            );
            assertEq(
                principal,
                STAKE_AMOUNT,
                "Principal should match the staked amount"
            );
        }
    }

    function testDoubleUnstakeFails() public {
        stakeTokens(STAKE_AMOUNT);
        vm.startPrank(user);
        stakingContract.requestUnstake(1);

        // Fast-forward time by 4 days to surpass the unstaking period
        vm.warp(block.timestamp + 4 days);

        // First unstake should succeed
        stakingContract.unstake(1);

        // Attempt to unstake again should revert
        vm.expectRevert();
        stakingContract.unstake(1);
    }

    function testOwnerCanSetPrincipalUnstaker() public {
        stakeTokens(STAKE_AMOUNT);

        vm.startPrank(user);
        stakingContract.updatePrincipalUnstaker(user2, 1);
        vm.stopPrank();

        (
            address beneficiary,
            address principalPayoutWallet,
            address principalUnstaker,
            uint256 principal,
            uint256 reward,
            uint256 paidOutReward,
            uint256 stakingStartTime,
            uint256 unstakingRequestTime,
            uint32 principalWalletShareBps
            

        ) = stakingContract.stakingStores(1);

        assertEq(
            principalUnstaker,
            user2,
            "Principal unstaker should be set by the owner."
        );
    }

    function testOnlyPrincipalUnstakerCanUpdate() public {
        stakeForTokens(STAKE_AMOUNT, user);

        // Owner sets the initial principal unstaker
        vm.startPrank(owner);
        stakingContract.updatePrincipalUnstaker(user, 1);
        vm.stopPrank();

        // The initial unstaker (user) successfully updates it to another address
        vm.startPrank(user);

        stakingContract.updatePrincipalUnstaker(address(0x5678), 1);
        vm.stopPrank();

        (
            address beneficiary,
            address principalPayoutWallet,
            address principalUnstaker,
            uint256 principal,
            uint256 reward,
            uint256 paidOutReward,
            uint256 stakingStartTime,
            uint256 unstakingRequestTime,


        ) = stakingContract.stakingStores(1);

        assertEq(
            principalUnstaker,
            address(0x5678),
            "Principal unstaker should be updated by the previous unstaker."
        );
    }

    function testNonOwnerCannotSetInitialPrincipalUnstaker() public {
        stakeTokens(STAKE_AMOUNT);
        vm.startPrank(address(0x5678));

        vm.expectRevert(NotPrincipalUnstaker.selector);
        stakingContract.updatePrincipalUnstaker(user, 1);
        vm.stopPrank();
    }

    function testUpdatePrincipalPayoutWallet() public {
        stakeTokens(STAKE_AMOUNT);

        address newPayoutWallet = address(0x9876);

         (, address principalPayoutWallet, , , , , , , ) = stakingContract
            .stakingStores(1);

            console.log("principalPayoutWallet",principalPayoutWallet);
            console.log("owner",owner);


        // Ensure only the principal unstaker can update
        vm.startPrank(address(0x123));
        stakingContract.updatePrincipalPayoutWallet(newPayoutWallet, 1);
        vm.stopPrank();

        (,   principalPayoutWallet, , , , , , , ) = stakingContract
            .stakingStores(1);

        assertEq(
            principalPayoutWallet,
            newPayoutWallet,
            "Principal payout wallet should be updated correctly."
        );
    }

       function testUpdatePrincipalPayoutWallet_NotPrincipalUnstaker() public {
        stakeTokens(STAKE_AMOUNT);

        address newPayoutWallet = address(0x9876);

         (, address principalPayoutWallet, , , , , , , ) = stakingContract
            .stakingStores(1);

            console.log("principalPayoutWallet",principalPayoutWallet);
            console.log("owner",owner);


        // Ensure only the principal unstaker can update
        vm.startPrank(address(0x121));
        vm.expectRevert(NotPrincipalUnstaker.selector);
        stakingContract.updatePrincipalPayoutWallet(newPayoutWallet, 1);
        vm.stopPrank();
 
    }

    function testRequestUnstakeNotBeneficiary() public {
        stakeTokens(STAKE_AMOUNT); // Stake on behalf of `user`

        // Attempt unstake from `user2`, who is not the beneficiary
        vm.startPrank(user2);
        vm.expectRevert(AccessDenied.selector);
        stakingContract.requestUnstake(1);
        vm.stopPrank();
    }

    function testRequestUnstakeAlreadyRequested() public {
        stakeTokens(STAKE_AMOUNT); // Stake on behalf of `user`

        vm.startPrank(user);
        stakingContract.requestUnstake(1); // First request should succeed

        // Second request should fail
        vm.expectRevert(AlreadyRequestedUnstake.selector);
        stakingContract.requestUnstake(1);
        vm.stopPrank();
    }

    function testRemoveWhitelistedStakerNotWhitelisted() public {
        vm.startPrank(owner);

        // Attempt to remove a non-whitelisted staker
        vm.expectRevert(NotWhitelisted.selector);
        stakingContract.removeWhitelistedStaker(user);

        vm.stopPrank();
    }

    function testRemoveWhitelistedStaker() public {
        vm.startPrank(owner);

        // Add user to the whitelist first
        stakingContract.addWhitelistedStaker(user);
        assertEq(
            stakingContract.stakingWhitelist(user),
            true,
            "User should be whitelisted"
        );

        // Remove the user from whitelist
        stakingContract.removeWhitelistedStaker(user);
        assertEq(
            stakingContract.stakingWhitelist(user),
            false,
            "User should be removed from whitelist"
        );

        vm.stopPrank();
    }

    function testSetUnstakingDurationTooShort() public {
        vm.startPrank(owner);

        // Attempt to set duration less than 1 day
        vm.expectRevert(
            UnstakingDurationTooShort.selector
        );
        stakingContract.setUnstakingDuration(0.5 days);

        vm.stopPrank();
    }

    function testSetUnstakingDurationTooLong() public {
        vm.startPrank(owner);

        // Attempt to set duration more than 20 days
        vm.expectRevert(
            UnstakingDurationTooLong.selector
        );
        stakingContract.setUnstakingDuration(21 days);

        vm.stopPrank();
    }

    function testSetUnstakingDurationValid() public {
        vm.startPrank(owner);

        // Set a valid duration and verify it updates correctly
        uint256 newDuration = 10 days;
        stakingContract.setUnstakingDuration(newDuration);
        assertEq(
            stakingContract.unstakingDuration(),
            newDuration,
            "Unstaking duration should be updated"
        );

        vm.stopPrank();
    }

    function testAddWhitelistedStakerAlreadyWhitelisted() public {
        vm.startPrank(owner);

        // First time adding should succeed
        stakingContract.addWhitelistedStaker(user);
        assertEq(
            stakingContract.stakingWhitelist(user),
            true,
            "User should be whitelisted"
        );

        // Attempting to add again should revert
        vm.expectRevert(DIAWhitelistedStaking.AlreadyWhitelisted.selector);
        stakingContract.addWhitelistedStaker(user);

        vm.stopPrank();
    }

    function testUpdateRewardRate() public {
        vm.startPrank(owner);

        // First time adding should succeed
        stakingContract.updateRewardRatePerDay(12);

        vm.stopPrank();
    }

    function testUpdateRewardWallet() public {
        vm.startPrank(owner);

        // First time adding should succeed
        stakingContract.updateRewardsWallet(address(0x123));

        vm.stopPrank();
    }

    function testUpdateZeroRewardWallet() public {
        vm.startPrank(owner);

        // First time adding should succeed
        vm.expectRevert();
        stakingContract.updateRewardsWallet(address(0x00));

        vm.stopPrank();
    }

    function test_StakeForAddress_NotWhitelisted()public {

         stakingToken.approve(address(stakingContract), STAKE_AMOUNT);
         vm.expectRevert(NotWhitelisted.selector);
        stakingContract.stakeForAddress(address(0x09), STAKE_AMOUNT, 400); // Principal wallet gets 4% reward

        vm.stopPrank();

    }

    function testSplitStakeAndUnstake() public {

        vm.startPrank(owner);

        stakingContract.addWhitelistedStaker(address(user));
        
        address delegator = address(0x345);
        deal(address(stakingToken), delegator, INITIAL_USER_BALANCE);

        uint256 start = block.timestamp;

        // Stake tokens
        uint256 initialUserBalance = stakingToken.balanceOf(user);
        uint256 initialDelegatorBalance = stakingToken.balanceOf(user);

        uint256 initialContractBalance = stakingToken.balanceOf(
            address(stakingContract)
        );

        // stakeTokens(STAKE_AMOUNT);

        vm.startPrank(delegator);
        stakingToken.approve(address(stakingContract), STAKE_AMOUNT);
        stakingContract.stakeForAddress(user, STAKE_AMOUNT, 400); // Principal wallet gets 4% reward

        vm.stopPrank();

        uint256 finalUserBalance = stakingToken.balanceOf(delegator);
        uint256 finalContractBalance = stakingToken.balanceOf(
            address(stakingContract)
        );

        // Ensure balances are updated correctly
        assertEq(
            finalContractBalance,
            initialContractBalance + STAKE_AMOUNT,
            "Contract balance should increase"
        );
        assertEq(
            finalUserBalance,
            initialDelegatorBalance - STAKE_AMOUNT,
            "User balance should decrease"
        );

        // Verify staking store
     


              (address beneficiary, , , uint256 principal, , , , , ) = stakingContract
            .stakingStores(1);
        assertEq(beneficiary, user, "Beneficiary should match the user");
        assertEq(
            principal,
            STAKE_AMOUNT,
            "Principal should match the staked amount"
        );

        vm.warp(start + 4 days);

        // Start by requesting unstake
        vm.startPrank(delegator);

        stakingContract.requestUnstake(1);

        // Simulate 4 days passing (reward accumulation happens during this period)
        vm.warp(start + 8 days);

        // Store the current reward balance before unstaking
        uint256 rewardBeforeUnstake = stakingContract.getRewardForStakingStore(
            1
        );

        console.log("Total Rewards", rewardBeforeUnstake);

        uint256 userRewards = ((rewardBeforeUnstake * 96) / 100); // 96% of rewards

        console.log("96% Rewards", userRewards);

 
          (  beneficiary, , ,   principal, , , , ,) = stakingContract
            .stakingStores(1);

        // Unstake tokens
        stakingContract.unstake(1);
        vm.stopPrank();

        // Verify user balance is restored after unstake

        assertEq(
            stakingToken.balanceOf(user),
            INITIAL_USER_BALANCE + userRewards,
            "User balance should be restored after unstake"
        );

        // Verify that the reward is non-zero and has been distributed correctly
        uint256 rewardAfterUnstake = stakingContract.getRewardForStakingStore(
            1
        );
        assertEq(
            rewardAfterUnstake,
            0,
            "Reward should be paid out upon unstaking"
        );

        // If rewards were accumulated, ensure the user received the reward amount
        finalUserBalance = stakingToken.balanceOf(user);
        uint256 expectedUserBalance = INITIAL_USER_BALANCE + userRewards;
        console.log("finalUserBalance", finalUserBalance);

        assertEq(
            finalUserBalance,
            expectedUserBalance,
            "User balance should include the staked amount and accumulated rewards"
        );
    }

    function test_RequestPrincipalWalletShareUpdate() public {
    uint256 principal = 1_000e18;
    uint32 newShareBps = 5000; // 50%
    uint64 gracePeriod = 1 days;



    vm.prank(owner);

    stakingContract.addWhitelistedStaker(address(user));

        vm.prank(user);
        stakingToken.approve(address(stakingContract), 10000000 * 10 ** 18);


    // Setup staking
    vm.prank(user);
    stakingContract.stake(principal);
    uint256[] memory index = stakingContract.getStakingIndicesByBeneficiary(address(user));
 
    // Attempt update by unauthorized user
    vm.expectRevert(NotBeneficiary.selector);
    stakingContract.requestPrincipalWalletShareUpdate(index[0], newShareBps);


    // Request update by beneficiary
    vm.prank(user);
    stakingContract.requestPrincipalWalletShareUpdate(index[0], newShareBps);

    // Check pending update is stored correctly
    (uint32 bps, uint64 requestTime) = stakingContract.pendingShareUpdates(1);
    assertEq(bps, newShareBps, "Stored BPS should match requested BPS");
    assertEq(requestTime, block.timestamp, "Stored timestamp should be current");

    // Try invalid BPS > 10000
    vm.prank(user);
    vm.expectRevert();
    stakingContract.requestPrincipalWalletShareUpdate(index[0], 10001);
}

  function test_InvalidWithdrawalCap() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidWithdrawalCap.selector, 10001)
        );
        stakingContract.setWithdrawalCapBps(10001);
    }


    function testSetInvalidDailyWithdrawalThreshold() public {
        uint256 newThreshold = 0;

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidDailyWithdrawalThreshold.selector,
                newThreshold
            )
        );

        stakingContract.setDailyWithdrawalThreshold(newThreshold);
    }

        function testGetStakingIndicesByPrincipalUnstaker() public {

                stakeTokens(1*10**18);


        uint256[] memory indices = stakingContract.getStakingIndicesByPrincipalUnstaker(
            user
        );
        assertEq(indices.length, 1);
    }

    function testGetStakingIndicesByPayoutWallet() public {

               stakeTokens(1*10**18);

        uint256[] memory indices = stakingContract.getStakingIndicesByPayoutWallet(
            user
        );
        assertEq(indices.length, 1);
     }

    //   function test_UnstakeExceedsDailyLimitFails() public {
    //     // Stake and request unstake
    //     uint256 STAKE_AMOUNT = 100 * 10 ** 18;

    //     stakeTokens(STAKE_AMOUNT);

    //     vm.startPrank(owner);

    //     stakingContract.setDailyWithdrawalThreshold(10 * 10 ** 18);

    //     vm.startPrank(user);
    //     stakingContract.requestUnstake(1);

    //     // Simulate passage of time past unstaking delay
    //     vm.warp(block.timestamp + 4 days);

    //     // Attempt to unstake, should fail due to limit
    //     vm.expectRevert(DailyWithdrawalLimitExceeded.selector);
    //     stakingContract.unstake(1);

    //     vm.stopPrank();
    // }

    function test_RevertWhen_InvalidPrincipalShare() public {
        uint256 amount = 1000 * 10 ** 18;
        uint32 principalShareBps = 10001; // Above 100%

 

          vm.prank(owner);

        stakingContract.addWhitelistedStaker(address(user));
        vm.startPrank(user);
        stakingToken.approve(address(stakingContract), amount);
                  vm.expectRevert(InvalidPrincipalWalletShare.selector);

        stakingContract.stakeForAddress(user, amount, principalShareBps);

         vm.stopPrank();



     }

       function test_RevertWhen_AmountBelowMinimumStake() public {
        uint256 amount = 0.5 * 10 ** 18;
        uint32 principalShareBps = 10000; // Above 100%

 

          vm.prank(owner);

        stakingContract.addWhitelistedStaker(address(user));
        vm.startPrank(user);
        stakingToken.approve(address(stakingContract), amount);

      vm.expectRevert(
            abi.encodeWithSelector(
                AmountBelowMinimumStake.selector,
                amount
            )
        );
        stakingContract.stakeForAddress(user, amount, principalShareBps);

         vm.stopPrank();



     }

    function test_GetCurrentPrincipalWalletShareBps() public {
        // Setup initial stake with 50% share
        vm.startPrank(owner);
        stakingContract.addWhitelistedStaker(user);
        vm.startPrank(user);
        stakingToken.approve(address(stakingContract), STAKE_AMOUNT);
        stakingContract.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Check initial share (should be 0% as no share was specified)
        uint32 initialShare = stakingContract.getCurrentPrincipalWalletShareBps(1);
        assertEq(initialShare, 10000, "Initial share should be 100%");

        // Request share update to 75%
        vm.startPrank(user);
        stakingContract.requestPrincipalWalletShareUpdate(1, 7500);
        vm.stopPrank();

        // Check share before grace period (should still be 0%)
        uint32 shareBeforeGrace = stakingContract.getCurrentPrincipalWalletShareBps(1);
        assertEq(shareBeforeGrace, 10000, "Share should not change before grace period");

        // Fast forward to just before grace period
        vm.warp(block.timestamp + stakingContract.SHARE_UPDATE_GRACE_PERIOD() - 1);
        uint32 shareJustBeforeGrace = stakingContract.getCurrentPrincipalWalletShareBps(1);
        assertEq(shareJustBeforeGrace, 10000, "Share should not change before grace period ends");

        // Fast forward past grace period
        vm.warp(block.timestamp + 2);
        uint32 shareAfterGrace = stakingContract.getCurrentPrincipalWalletShareBps(1);
        assertEq(shareAfterGrace, 7500, "Share should update to 75% after grace period");
    }

    function test_UnstakePrincipal() public {
        // Setup initial stake
        vm.startPrank(owner);
        stakingContract.setDailyWithdrawalThreshold(1000000000000000000);
        deal(address(stakingToken), user, STAKE_AMOUNT *2);
        stakingContract.setWithdrawalCapBps(10000);
        stakingContract.addWhitelistedStaker(user);
        vm.startPrank(user);
        stakingToken.approve(address(stakingContract), STAKE_AMOUNT *2);
        stakingContract.stake(STAKE_AMOUNT);
        stakingContract.stake(STAKE_AMOUNT);

        vm.stopPrank();

        // Request unstake
        vm.startPrank(user);
        stakingContract.requestUnstake(1);
        vm.stopPrank();

        // Fast forward past unstaking period
        vm.warp(block.timestamp + stakingContract.unstakingDuration() + 1);

        // Get initial balances
        uint256 initialPrincipalBalance = stakingToken.balanceOf(user);
        uint256 initialContractBalance = stakingToken.balanceOf(address(stakingContract));

        // Unstake principal
        vm.startPrank(user);
        stakingContract.unstakePrincipal(1, STAKE_AMOUNT);
        vm.stopPrank();

        // Verify balances
        uint256 finalPrincipalBalance = stakingToken.balanceOf(user);
        uint256 finalContractBalance = stakingToken.balanceOf(address(stakingContract));

        assertEq(
            finalPrincipalBalance - initialPrincipalBalance,
            STAKE_AMOUNT,
            "Principal amount should be returned to user"
        );
        assertEq(
            initialContractBalance - finalContractBalance,
            STAKE_AMOUNT,
            "Contract balance should decrease by principal amount"
        );
    }

    function test_UnstakePrincipal_NotPrincipalUnstaker() public {
        // Setup initial stake
        vm.startPrank(owner);
        stakingContract.addWhitelistedStaker(user);
        deal(address(stakingToken), user, STAKE_AMOUNT *2);
        stakingContract.setDailyWithdrawalThreshold(1000000000000000000);
        stakingContract.setWithdrawalCapBps(10000);
        vm.startPrank(user);
        stakingToken.approve(address(stakingContract), STAKE_AMOUNT *2);
        stakingContract.stake(STAKE_AMOUNT);
        stakingContract.stake(STAKE_AMOUNT);

        vm.stopPrank();

        // Request unstake
        vm.startPrank(user);
        stakingContract.requestUnstake(1);
        vm.stopPrank();

        // Fast forward past unstaking period
        vm.warp(block.timestamp + stakingContract.unstakingDuration() + 1);

        // Try to unstake with different address
        vm.startPrank(address(0x1234));
        vm.expectRevert(NotPrincipalUnstaker.selector);
        stakingContract.unstakePrincipal(1, STAKE_AMOUNT);
        vm.stopPrank();
    }

    function test_UnstakePrincipal_UnstakingNotRequested() public {
        // Setup initial stake
        vm.startPrank(owner);
        stakingContract.addWhitelistedStaker(user);
        deal(address(stakingToken), user, STAKE_AMOUNT *2);
        stakingContract.setDailyWithdrawalThreshold(1000000000000000000);
        stakingContract.setWithdrawalCapBps(10000);
        vm.startPrank(user);
        stakingToken.approve(address(stakingContract), STAKE_AMOUNT *2);
        stakingContract.stake(STAKE_AMOUNT);
        stakingContract.stake(STAKE_AMOUNT);


        // Try to unstake without requesting
        vm.startPrank(user);
        vm.expectRevert(UnstakingNotRequested.selector);
        stakingContract.unstakePrincipal(1, STAKE_AMOUNT);
        vm.stopPrank();
    }

    function test_UnstakePrincipal_PeriodNotElapsed() public {
        // Setup initial stake
       vm.startPrank(owner);
        stakingContract.addWhitelistedStaker(user);
        deal(address(stakingToken), user, STAKE_AMOUNT *2);
        stakingContract.setDailyWithdrawalThreshold(1000000000000000000);
        stakingContract.setWithdrawalCapBps(10000);
        vm.startPrank(user);
        stakingToken.approve(address(stakingContract), STAKE_AMOUNT *2);
        stakingContract.stake(STAKE_AMOUNT);
        stakingContract.stake(STAKE_AMOUNT);


        // Request unstake
        vm.startPrank(user);
        stakingContract.requestUnstake(1);
        vm.stopPrank();

        // Try to unstake before period elapsed
        vm.startPrank(user);
        vm.expectRevert(UnstakingPeriodNotElapsed.selector);
        stakingContract.unstakePrincipal(1, STAKE_AMOUNT);
        vm.stopPrank();
    }

    function test_UnstakePrincipal_AmountExceedsStaked() public {
        // Setup initial stake
        vm.startPrank(owner);
        deal(address(stakingToken), user, STAKE_AMOUNT * 2);
        stakingContract.addWhitelistedStaker(user);
        stakingContract.setDailyWithdrawalThreshold(1000000000000000000);
        stakingContract.setWithdrawalCapBps(10000);
        vm.startPrank(user);
        stakingToken.approve(address(stakingContract), STAKE_AMOUNT *2);
        stakingContract.stake(STAKE_AMOUNT);
        stakingContract.stake(STAKE_AMOUNT);

        vm.stopPrank();

        // Request unstake
        vm.startPrank(user);
        stakingContract.requestUnstake(1);
        vm.stopPrank();

        // Fast forward past unstaking period
        vm.warp(block.timestamp + stakingContract.unstakingDuration() + 1);

        // Try to unstake more than staked
        vm.startPrank(user);
        vm.expectRevert(AmountExceedsStaked.selector);
        stakingContract.unstakePrincipal(1, STAKE_AMOUNT + 1);
        vm.stopPrank();
    }

}
