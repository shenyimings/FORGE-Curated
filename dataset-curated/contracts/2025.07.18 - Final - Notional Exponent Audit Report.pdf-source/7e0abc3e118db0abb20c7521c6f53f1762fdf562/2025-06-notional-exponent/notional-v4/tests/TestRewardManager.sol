// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "./TestMorphoYieldStrategy.sol";
import "../src/interfaces/IRewardManager.sol";
import "../src/utils/Constants.sol";
import "../src/interfaces/IWithdrawRequestManager.sol";
import "../src/withdraws/GenericERC20.sol";
import {AbstractRewardManager, RewardPoolStorage} from "../src/rewards/AbstractRewardManager.sol";
import {RewardManagerMixin} from "../src/rewards/RewardManagerMixin.sol";
import {ConvexRewardManager} from "../src/rewards/ConvexRewardManager.sol";

contract TestRewardManager is TestMorphoYieldStrategy {
    IRewardManager rm;
    ERC20 rewardToken;
    ERC20 emissionsToken;
    IWithdrawRequestManager withdrawRequestManager;
    address rmImpl;

    function deployYieldStrategy() internal override {
        w = new MockRewardPool(address(USDC));

        withdrawRequestManager = new GenericERC20WithdrawRequestManager(address(w));
        vm.startPrank(owner);
        ADDRESS_REGISTRY.setWithdrawRequestManager(address(withdrawRequestManager));
        vm.stopPrank();

        rmImpl = address(new ConvexRewardManager());
        o = new MockOracle(1e18);
        y = new MockRewardVault(
            address(USDC),
            address(w),
            0.0010e18, // 0.1% fee rate
            address(rmImpl)
        );
    }

    function postDeploySetup() internal override {
        // We use the delegate call here.
        rm = IRewardManager(address(y));

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
        rewardToken = MockRewardPool(address(w)).rewardToken();

        // Set the initial reward pool
        vm.startPrank(owner);
        emissionsToken = new MockERC20("MockEmissionsToken", "MET");
        emissionsToken.transfer(address(rm), 100_0000e18);
        rm.migrateRewardPool(address(USDC), RewardPoolStorage({
            rewardPool: address(w),
            forceClaimAfter: 0,
            lastClaimTimestamp: 0
        }));
        rm.updateRewardToken(0, address(rewardToken), 0, 0);

        withdrawRequestManager.setApprovedVault(address(y), true);

        vm.stopPrank();
    }

    function test_migrateRewardPool() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        assertGt(y.totalSupply(), 0);
        

        address newRewardPool = address(new MockRewardPool(address(USDC)));
        address newVault = address(new MockRewardVault(
            address(USDC),
            address(newRewardPool),
            0.0010e18, // 0.1% fee rate
            address(rmImpl)
        ));


        MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        // Now we deploy a new reward pool and migrate all the tokens into it
        vm.startPrank(owner);
        TRADING_MODULE.setPriceOracle(newRewardPool, AggregatorV2V3Interface(address(o)));

        TimelockUpgradeableProxy(payable(address(y))).initiateUpgrade(address(newVault));
        vm.warp(block.timestamp + 7 days);
        TimelockUpgradeableProxy(payable(address(y))).executeUpgrade(abi.encodeWithSelector(
            AbstractRewardManager.migrateRewardPool.selector, address(USDC), RewardPoolStorage({
                rewardPool: address(newRewardPool),
                forceClaimAfter: 0,
                lastClaimTimestamp: 0
        })));

        rm.updateRewardToken(1, address(MockRewardPool(address(newRewardPool)).rewardToken()), 0, 0);
        vm.stopPrank();

        (VaultRewardState[] memory rewardStates, RewardPoolStorage memory rewardPool) = rm.getRewardSettings();
        assertEq(rewardStates.length, 2);
        assertEq(rewardPool.rewardPool, address(newRewardPool));
        assertEq(rewardPool.forceClaimAfter, 0);
        assertEq(rewardPool.lastClaimTimestamp, block.timestamp);

        address user = makeAddr("user");
        vm.prank(owner);
        asset.transfer(user, defaultDeposit);

        // Assert that we can claim rewards and also enter the position
        _enterPosition(user, defaultDeposit, defaultBorrow);

        // Claim rewards
        {
            vm.prank(msg.sender);
            uint256[] memory rewardInitial = lendingRouter.claimRewards(address(y));
            assertGt(rewardInitial[0], 0);
            assertEq(rewardInitial[1], 0);

            // No additional rewards for second user
            vm.prank(user);
            uint256[] memory rewardSecondUser = lendingRouter.claimRewards(address(y));
            assertEq(rewardSecondUser[0], 0);
            assertEq(rewardSecondUser[1], 0);
        }

        // Set more rewards
        MockRewardPool(address(newRewardPool)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        // Claim rewards for the second time
        {
            vm.prank(msg.sender);
            uint256[] memory rewardInitial = lendingRouter.claimRewards(address(y));
            assertEq(rewardInitial[0], 0);
            assertGt(rewardInitial[1], 0);

            vm.prank(user);
            uint256[] memory rewardSecondUser = lendingRouter.claimRewards(address(y));
            assertEq(rewardSecondUser[0], 0);
            assertGt(rewardSecondUser[1], 0);
        }

        vm.warp(block.timestamp + 6 minutes);

        // Both users can exit the pool
        vm.startPrank(msg.sender);
        lendingRouter.exitPosition(msg.sender, address(y), msg.sender, lendingRouter.balanceOfCollateral(msg.sender, address(y)), type(uint256).max, "");
        vm.stopPrank();

        vm.startPrank(user);
        lendingRouter.exitPosition(user, address(y), user, lendingRouter.balanceOfCollateral(user, address(y)), type(uint256).max, "");
        vm.stopPrank();
    }

    function test_callUpdateRewardToken_RevertIf_NotRewardManager() public {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        rm.updateRewardToken(0, address(rewardToken), 0, 0);
    }

    function test_callUpdateAccountRewards_RevertIf_NotVault() public {
        vm.expectRevert();
        rm.updateAccountRewards(msg.sender, 0, 0, 0, true);
    }

    function test_enterPosition_withRewards(bool hasEmissions, bool hasRewards) public {
        if (hasEmissions) {
            vm.prank(owner);
            rm.updateRewardToken(1, address(emissionsToken), 365e18, uint32(block.timestamp + 365 days));
        }

        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        // Check balance of reward token
        assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
        assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0, "Reward debt is empty");

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.effectiveSupply()));
        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        rm.claimRewardTokens();

        // Still no reward debt
        assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
        assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0, "Reward debt is empty");

        uint256 sharesBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 expectedRewards = hasRewards ? y.convertSharesToYieldToken(sharesBefore) : 0;

        vm.prank(msg.sender);
        uint256[] memory rewards = lendingRouter.claimRewards(address(y));

        assertApproxEqRel(rewards[0], expectedRewards, 0.0001e18, "Rewards are incorrect");
        if (hasEmissions) assertApproxEqRel(rewards[1], 1e18, 0.0001e18, "Emissions tokens are incorrect");

        if (hasRewards) {
            assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards, 0.0001e18, "Rewards are claimed");
            assertApproxEqRel(rm.getRewardDebt(address(rewardToken), msg.sender), expectedRewards, 0.0001e18, "Reward debt is updated");
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0, "Reward debt is empty");
        }

        if (hasEmissions) {
            assertApproxEqRel(emissionsToken.balanceOf(msg.sender), 1e18, 0.0001e18, "Emissions tokens are claimed");
            assertApproxEqRel(rm.getRewardDebt(address(emissionsToken), msg.sender), 1e18, 0.0001e18, "Emissions debt is updated");
        }

        vm.prank(msg.sender);
        rewards = lendingRouter.claimRewards(address(y));
        assertEq(rewards[0], 0, "Rewards are empty");
        if (hasEmissions) assertEq(rewards[1], 0, "Emissions tokens are empty");

        if (hasRewards) {
            assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards, 0.0001e18, "Rewards are claimed");
            assertApproxEqRel(rm.getRewardDebt(address(rewardToken), msg.sender), expectedRewards, 0.0001e18, "Reward debt is updated");
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), 0);
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0);
        }

        if (hasEmissions) {
            assertApproxEqRel(emissionsToken.balanceOf(msg.sender), 1e18, 0.0001e18, "Emissions tokens are claimed");
            assertApproxEqRel(rm.getRewardDebt(address(emissionsToken), msg.sender), 1e18, 0.0001e18, "Emissions debt is updated");
        }

        _enterPosition(msg.sender, defaultDeposit, 0);
        uint256 sharesAfter = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 expectedRewardsAfter = hasRewards ? y.convertSharesToYieldToken(sharesAfter) : 0;
        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.effectiveSupply()));

        vm.prank(msg.sender);
        lendingRouter.claimRewards(address(y));
        if (hasRewards) {
            assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards + expectedRewardsAfter, 0.0001e18, "Rewards are claimed");
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
        }
        // No additional emissions tokens are claimed
        if (hasEmissions) assertApproxEqRel(emissionsToken.balanceOf(msg.sender), 1e18, 0.0001e18, "Emissions tokens are claimed");
    }

    function test_exitPosition_withRewards(bool isFullExit, bool hasRewards, bool hasEmissions) public {
        if (hasEmissions) {
            vm.prank(owner);
            rm.updateRewardToken(1, address(emissionsToken), 365e18, uint32(block.timestamp + 365 days));
        }

        _enterPosition(owner, defaultDeposit, defaultBorrow);
        _enterPosition(msg.sender, defaultDeposit * 4, defaultBorrow);

        vm.warp(block.timestamp + 7 days);

        // Rewards are 1-1 with yield tokens
        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        uint256 sharesBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 expectedRewards = hasRewards ? y.convertSharesToYieldToken(sharesBefore) : 0;
        uint256 emissionsForUser = 7e18 * sharesBefore / y.totalSupply();
        vm.startPrank(msg.sender);
        if (isFullExit) {
            lendingRouter.exitPosition(
                msg.sender,
                address(y),
                msg.sender,
                sharesBefore,
                type(uint256).max,
                getRedeemData(msg.sender, sharesBefore)
            );
        } else {
            // Partial exit
            lendingRouter.exitPosition(
                msg.sender,
                address(y),
                msg.sender,
                sharesBefore / 10,
                defaultBorrow / 10,
                getRedeemData(msg.sender, sharesBefore / 10)
            );
        }
        vm.stopPrank();

        if (hasRewards) {
            assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards, 0.0001e18, "Rewards are claimed");
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
        }

        if (hasEmissions) {
            assertApproxEqRel(emissionsToken.balanceOf(msg.sender), emissionsForUser, 0.0010e18, "Emissions tokens are claimed");
        }

        if (isFullExit) {
            assertEq(rm.getRewardDebt(address(emissionsToken), msg.sender), 0, "Emissions debt is updated");
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0, "Reward debt is updated");
        }

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));
        uint256 sharesAfter = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 expectedRewardsAfter = hasRewards ? y.convertSharesToYieldToken(sharesAfter) : 0;

        rm.claimRewardTokens();

        vm.prank(msg.sender);
        uint256[] memory rewards = lendingRouter.claimRewards(address(y));
        if (isFullExit) {
            assertEq(rewards.length, 0);
        } else {
            assertEq(rewards.length, hasEmissions ? 2 : 1);
            assertApproxEqRel(rewards[0], expectedRewardsAfter, 0.0001e18, "Rewards are correct");
            if (hasEmissions) assertEq(rewards[1], 0, "Emissions tokens are claimed");
        }

        if (hasRewards) {
            assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards + expectedRewardsAfter, 0.0001e18, "Rewards are claimed");
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
        }

        if (hasEmissions) {
            assertApproxEqRel(emissionsToken.balanceOf(msg.sender), emissionsForUser, 0.0010e18, "Emissions tokens are claimed");
        }

        if (isFullExit) {
            assertEq(rm.getRewardDebt(address(emissionsToken), msg.sender), 0, "Emissions debt is updated");
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0, "Reward debt is updated");
        }

        // Since there were two claims before, the owner should receive 2x the rewards
        // as the balance of shares.
        vm.prank(owner);
        lendingRouter.claimRewards(address(y));
        uint256 sharesAfterOwner = lendingRouter.balanceOfCollateral(owner, address(y));
        uint256 expectedRewardsForOwner = hasRewards ? y.convertSharesToYieldToken(sharesAfterOwner) * 2 : 0;
        if (hasRewards) {
            assertApproxEqRel(rewardToken.balanceOf(owner), expectedRewardsForOwner, 0.0001e18, "Rewards are claimed");
        } else {
            assertEq(rewardToken.balanceOf(owner), 0, "Rewards are empty");
        }

        if (hasEmissions) {
            uint256 emissionsForOwner = 7e18 - emissionsForUser;
            assertApproxEqRel(emissionsToken.balanceOf(owner), emissionsForOwner, 0.0010e18, "Emissions tokens are claimed for owner");
        }
    }

    function test_liquidate_withRewards(bool hasEmissions, bool hasRewards, bool isPartialLiquidation) public {
        int256 originalPrice = o.latestAnswer();
        address liquidator = makeAddr("liquidator");
        if (hasEmissions) {
            vm.prank(owner);
            rm.updateRewardToken(1, address(emissionsToken), 365e18, uint32(block.timestamp + 365 days));
        }

        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        _enterPosition(owner, defaultDeposit, 0);

        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        else vm.warp(block.timestamp + 6 minutes);
        
        vm.prank(owner);
        asset.transfer(liquidator, defaultDeposit + defaultBorrow);

        o.setPrice(originalPrice * 0.90e18 / 1e18);

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        vm.startPrank(liquidator);
        uint256 sharesBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 emissionsForUser = 1e18 * sharesBefore / y.totalSupply();
        uint256 expectedRewards = hasRewards ? y.convertSharesToYieldToken(sharesBefore) : 0;
        asset.approve(address(lendingRouter), type(uint256).max);
        uint256 sharesToLiquidate = isPartialLiquidation ? sharesBefore / 2 : sharesBefore;
        // This should trigger a claim on rewards
        uint256 sharesToLiquidator = lendingRouter.liquidate(msg.sender, address(y), sharesToLiquidate, 0);
        vm.stopPrank();

        if (hasRewards) assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards, 0.0001e18, "Liquidated account shares");
        if (hasEmissions) {
            assertApproxEqRel(emissionsToken.balanceOf(msg.sender), emissionsForUser, 0.0010e18, "Liquidated account emissions");
        }

        assertEq(rewardToken.balanceOf(liquidator), 0, "Liquidator account rewards");
        assertEq(emissionsToken.balanceOf(liquidator), 0, "Liquidator account emissions");

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));
        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        uint256 emissionsForLiquidator = 1e18 * sharesToLiquidator / y.totalSupply();

        // This second parameter is ignored because we get the balanceOf from
        // the contract itself.
        RewardManagerMixin(address(rm)).claimAccountRewards(liquidator, type(uint256).max);

        uint256 expectedRewardsForLiquidator = hasRewards ? y.convertSharesToYieldToken(sharesToLiquidator) : 0;
        if (hasRewards) assertApproxEqRel(rewardToken.balanceOf(liquidator), expectedRewardsForLiquidator, 0.0001e18, "Liquidator account rewards");
        if (hasEmissions) assertApproxEqRel(emissionsToken.balanceOf(liquidator), emissionsForLiquidator, 0.0010e18, "Liquidator account emissions");

        vm.prank(msg.sender);
        lendingRouter.claimRewards(address(y));
        uint256 sharesAfterUser = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 emissionsForUserAfter = 1e18 * sharesAfterUser / y.totalSupply();

        if (hasRewards) assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards + expectedRewards - expectedRewardsForLiquidator, 0.0001e18, "Liquidated account rewards");
        if (hasEmissions) assertApproxEqRel(emissionsToken.balanceOf(msg.sender), emissionsForUser + emissionsForUserAfter, 0.0010e18, "Liquidated account emissions");
    }

    function test_migrate_withRewards(bool hasEmissions, bool hasRewards) public {
        address user = msg.sender;
        if (hasEmissions) {
            vm.prank(owner);
            rm.updateRewardToken(1, address(emissionsToken), 365e18, uint32(block.timestamp + 365 days));
        }

        // Create a first position to ensure that the user doesn't just claim all the rewards
        _enterPosition(owner, defaultDeposit, 0);

        MorphoLendingRouter lendingRouter2 = setup_migration_test(user);

        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        else vm.warp(block.timestamp + 6 minutes);

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        vm.startPrank(user);
        uint256 sharesBefore = lendingRouter.balanceOfCollateral(user, address(y));
        uint256 expectedEmissions = hasEmissions ? 1e18 * sharesBefore / y.totalSupply() : 0;
        uint256 expectedRewards = hasRewards ? y.convertSharesToYieldToken(sharesBefore) : 0;
        lendingRouter2.migratePosition(user, address(y), address(lendingRouter));
        vm.stopPrank();

        // During migration shares are transferred from one lending router to another but there is no
        // minting or redemption of yield tokens so no claim occurs.
        assertEq(rewardToken.balanceOf(user), 0, "No rewards after migration");
        assertEq(emissionsToken.balanceOf(user), 0, "No emissions after migration");

        // Must claim rewards through the new lending router
        vm.prank(user);
        lendingRouter2.claimRewards(address(y));

        // Assert that rewards are claimed on the position during migration
        assertApproxEqRel(rewardToken.balanceOf(user), expectedRewards, 0.0001e18, "Rewards are claimed");
        assertApproxEqRel(emissionsToken.balanceOf(user), expectedEmissions, 0.0010e18, "Emissions are claimed");
    }

    function test_withdrawRequest_exitPosition_withRewards(bool hasEmissions, bool hasRewards) public {
        address user = msg.sender;
        if (hasEmissions) {
            vm.prank(owner);
            rm.updateRewardToken(1, address(emissionsToken), 365e18, uint32(block.timestamp + 365 days));
        }

        // Create two positions with rewards
        _enterPosition(user, defaultDeposit, defaultBorrow);
        _enterPosition(owner, defaultDeposit, 0);

        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        else vm.warp(block.timestamp + 6 minutes);

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        // Both positions should have rewards
        vm.prank(msg.sender);
        lendingRouter.claimRewards(address(y));
        vm.prank(owner);
        lendingRouter.claimRewards(address(y));

        uint256 emissionsBefore1 = emissionsToken.balanceOf(msg.sender);
        uint256 emissionsBefore2 = emissionsToken.balanceOf(owner);
        uint256 rewardsBefore1 = rewardToken.balanceOf(msg.sender);
        uint256 rewardsBefore2 = rewardToken.balanceOf(owner);
        if (hasEmissions) {
            assertGt(emissionsBefore1, 0, "User account emissions");
            assertGt(emissionsBefore2, 0, "Owner account emissions");
        } else {
            assertEq(emissionsBefore1, 0, "User account emissions");
            assertEq(emissionsBefore2, 0, "Owner account emissions");
        }

        if (hasRewards) {
            assertGt(rewardsBefore1, 0, "User account rewards");
            assertGt(rewardsBefore2, 0, "Owner account rewards");
        } else {
            assertEq(rewardsBefore1, 0, "User account rewards");
            assertEq(rewardsBefore2, 0, "Owner account rewards");
        }

        // Initiate a withdraw request on the first position
        vm.startPrank(msg.sender);
        lendingRouter.initiateWithdraw(
            msg.sender,
            address(y),
            getWithdrawRequestData(msg.sender, lendingRouter.balanceOfCollateral(msg.sender, address(y)))
        );
        vm.stopPrank();

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        // Exit the position, no rewards should be claimed
        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        else vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(msg.sender);
        lendingRouter.exitPosition(
            msg.sender,
            address(y),
            msg.sender,
            lendingRouter.balanceOfCollateral(msg.sender, address(y)),
            type(uint256).max,
            getRedeemData(msg.sender, lendingRouter.balanceOfCollateral(msg.sender, address(y)))
        );
        vm.stopPrank();

        vm.prank(owner);
        lendingRouter.claimRewards(address(y));

        // No rewards should be claimed for the user but the owner should have accrued more rewards since it
        // does not have a withdraw request.
        uint256 emissionsAfter1 = emissionsToken.balanceOf(msg.sender);
        uint256 emissionsAfter2 = emissionsToken.balanceOf(owner);
        assertEq(emissionsAfter1, emissionsBefore1, "User account emissions no change");
        if (hasEmissions) assertGt(emissionsAfter2, emissionsBefore2, "Owner account emissions change");

        uint256 rewardsAfter1 = rewardToken.balanceOf(msg.sender);
        uint256 rewardsAfter2 = rewardToken.balanceOf(owner);
        assertEq(rewardsAfter1, rewardsBefore1, "User account rewards no change");
        if (hasRewards) assertGt(rewardsAfter2, rewardsBefore2, "Owner account rewards change");

        // Now reopen the position and test to see if rewards are properly claimed
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        vm.prank(msg.sender);
        lendingRouter.claimRewards(address(y));

        if (hasRewards) {
            assertGt(rewardToken.balanceOf(msg.sender), rewardsBefore1, "User account rewards claimed");
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), rewardsBefore1, "User account rewards no change");
        }

        if (hasEmissions) {
            assertGt(emissionsToken.balanceOf(msg.sender), emissionsBefore1, "User account emissions claimed");
        } else {
            assertEq(emissionsToken.balanceOf(msg.sender), emissionsBefore1, "User account emissions no change");
        }

        // Now re-open the position and see that the user will start receiving rewards again
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        vm.prank(msg.sender);
        lendingRouter.claimRewards(address(y));

        if (hasRewards) {
            assertGt(rewardToken.balanceOf(msg.sender), rewardsBefore1, "User account rewards claimed");
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), rewardsBefore1, "User account rewards no change");
        }

        if (hasEmissions) {
            assertGt(emissionsToken.balanceOf(msg.sender), emissionsBefore1, "User account emissions claimed");
        } else {
            assertEq(emissionsToken.balanceOf(msg.sender), emissionsBefore1, "User account emissions no change");
        }
    }

    function test_liquidate_withdrawRequest_withRewards(bool hasEmissions, bool hasRewards) public {
        int256 originalPrice = o.latestAnswer();
        address liquidator = makeAddr("liquidator");
        if (hasEmissions) {
            vm.prank(owner);
            rm.updateRewardToken(1, address(emissionsToken), 365e18, uint32(block.timestamp + 365 days));
        }

        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        else vm.warp(block.timestamp + 6 minutes);

        // Rewards are claimed on the withdraw
        uint256 sharesBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 emissionsForUser = 1e18 * sharesBefore / y.totalSupply();
        uint256 expectedRewards = hasRewards ? y.convertSharesToYieldToken(sharesBefore) : 0;

        // Initiate a withdraw request on the first position
        vm.startPrank(msg.sender);
        lendingRouter.initiateWithdraw(
            msg.sender,
            address(y),
            getWithdrawRequestData(msg.sender, lendingRouter.balanceOfCollateral(msg.sender, address(y)))
        );
        vm.stopPrank();

        if (hasRewards) {
            assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards, 0.0001e18, "Liquidated account rewards");
        }
        if (hasEmissions) {
            assertApproxEqRel(emissionsToken.balanceOf(msg.sender), emissionsForUser, 0.0010e18, "Liquidated account emissions");
        }

        vm.prank(owner);
        asset.transfer(liquidator, defaultDeposit + defaultBorrow);

        o.setPrice(originalPrice * 0.90e18 / 1e18);

        vm.startPrank(liquidator);
        asset.approve(address(lendingRouter), type(uint256).max);
        // This should trigger a claim on rewards, but none here because inside a withdraw request
        lendingRouter.liquidate(msg.sender, address(y), sharesBefore / 2, 0);
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(liquidator), 0, "Liquidator account rewards");
        assertEq(emissionsToken.balanceOf(liquidator), 0, "Liquidator account emissions");

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(1e18);
        if (hasEmissions) vm.warp(block.timestamp + 1 days);

        // This second parameter is ignored because we get the balanceOf from
        // the contract itself.
        RewardManagerMixin(address(rm)).claimAccountRewards(liquidator, type(uint256).max);

        // No claims here because inside a withdraw request
        if (hasRewards) assertEq(rewardToken.balanceOf(liquidator), 0, "Liquidator account rewards");
        if (hasEmissions) assertEq(emissionsToken.balanceOf(liquidator), 0, "Liquidator account emissions");

        uint256 initialRewards = rewardToken.balanceOf(msg.sender);
        uint256 initialEmissions = emissionsToken.balanceOf(msg.sender);
        vm.prank(msg.sender);
        lendingRouter.claimRewards(address(y));

        // No claims here because inside a withdraw request
        if (hasRewards) assertEq(rewardToken.balanceOf(msg.sender), initialRewards, "Liquidated account rewards 2");
        if (hasEmissions) assertEq(emissionsToken.balanceOf(msg.sender), initialEmissions, "Liquidated account emissions 2");
    }

    function test_withdrawRequest_migratePosition_withRewards(bool hasEmissions, bool hasRewards) public {
        address user = msg.sender;
        if (hasEmissions) {
            vm.prank(owner);
            rm.updateRewardToken(1, address(emissionsToken), 365e18, uint32(block.timestamp + 365 days));
        }

        // Create a first position to ensure that the user doesn't just claim all the rewards
        _enterPosition(owner, defaultDeposit, 0);

        MorphoLendingRouter lendingRouter2 = setup_migration_test(user);

        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        else vm.warp(block.timestamp + 6 minutes);

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        // Initiate a withdraw request on the first position
        vm.startPrank(user);
        lendingRouter.initiateWithdraw(
            user,
            address(y),
            getWithdrawRequestData(user, lendingRouter.balanceOfCollateral(user, address(y)))
        );
        vm.stopPrank();

        // Accrued rewards should be claimed for both accounts
        uint256 emissionsBefore1 = emissionsToken.balanceOf(msg.sender);
        uint256 rewardsBefore1 = rewardToken.balanceOf(msg.sender);
        if (hasEmissions) {
            assertGt(emissionsBefore1, 0, "User account emissions");
        } else {
            assertEq(emissionsBefore1, 0, "User account emissions");
        }

        if (hasRewards) {
            assertGt(rewardsBefore1, 0, "User account rewards");
        } else {
            assertEq(rewardsBefore1, 0, "User account rewards");
        }

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));
        if (hasEmissions) vm.warp(block.timestamp + 1 days);

        // No rewards claimed on migration
        vm.prank(user);
        lendingRouter2.migratePosition(user, address(y), address(lendingRouter));

        assertEq(emissionsToken.balanceOf(user), emissionsBefore1, "User account emissions no change");
        assertEq(rewardToken.balanceOf(user), rewardsBefore1, "User account rewards no change");

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));
        if (hasEmissions) vm.warp(block.timestamp + 1 days);

        // No rewards claimed on claim via the second lending router
        vm.prank(user);
        lendingRouter2.claimRewards(address(y));

        assertEq(emissionsToken.balanceOf(user), emissionsBefore1, "User account emissions no change");
        assertEq(rewardToken.balanceOf(user), rewardsBefore1, "User account rewards no change");

        // No rewards claimed on exit via the second lending router
        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));
        if (hasEmissions) vm.warp(block.timestamp + 1 days);

        vm.warp(block.timestamp + 6 minutes);
        vm.startPrank(user);
        lendingRouter2.exitPosition(
            user,
            address(y),
            user,
            lendingRouter2.balanceOfCollateral(user, address(y)),
            type(uint256).max,
            getRedeemData(user, lendingRouter2.balanceOfCollateral(user, address(y)))
        );
        vm.stopPrank();

        assertEq(emissionsToken.balanceOf(user), emissionsBefore1, "User account emissions no change");
        assertEq(rewardToken.balanceOf(user), rewardsBefore1, "User account rewards no change");
    }

    function test_withdrawRequest_claimRewards_withRewards(bool hasEmissions, bool hasRewards) public {
        if (hasEmissions) {
            vm.prank(owner);
            rm.updateRewardToken(1, address(emissionsToken), 365e18, uint32(block.timestamp + 365 days));
        }

        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        _enterPosition(owner, defaultDeposit, 0);

        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        else vm.warp(block.timestamp + 6 minutes);
        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        // Initiate a withdraw request on the first position
        vm.startPrank(msg.sender);
        lendingRouter.initiateWithdraw(
            msg.sender,
            address(y),
            getWithdrawRequestData(msg.sender, lendingRouter.balanceOfCollateral(msg.sender, address(y)))
        );
        vm.stopPrank();

        // Rewards are claimed on the first position
        uint256 emissionsBefore1 = emissionsToken.balanceOf(msg.sender);
        uint256 rewardsBefore1 = rewardToken.balanceOf(msg.sender);
        if (hasEmissions) {
            assertGt(emissionsBefore1, 0, "User account emissions");
        } else {
            assertEq(emissionsBefore1, 0, "User account emissions");
        }

        if (hasRewards) {
            assertGt(rewardsBefore1, 0, "User account rewards");
        } else {
            assertEq(rewardsBefore1, 0, "User account rewards");
        }

        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        // No rewards are claimed after the withdraw request
        vm.prank(msg.sender);
        lendingRouter.claimRewards(address(y));

        assertEq(emissionsToken.balanceOf(msg.sender), emissionsBefore1, "User account emissions no change");
        assertEq(rewardToken.balanceOf(msg.sender), rewardsBefore1, "User account rewards no change");
    }

}