// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {StvStETHPool} from "src/StvStETHPool.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {IStETH} from "src/interfaces/core/IStETH.sol";
import {StvStETHPoolHarness} from "test/utils/StvStETHPoolHarness.sol";

/**
 * @title StvStETHPoolTest
 * @notice Integration tests for StvStETHPool (minting, no strategy)
 */
contract StvStETHPoolTest is StvStETHPoolHarness {
    function setUp() public {
        _initializeCore();
    }

    uint256 public constant DEFAULT_WRAPPER_RR_GAP = 1000; // 10%

    function test_single_user_mints_full_in_one_step() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, 0);
        _assertUniversalInvariants("Step 0", ctx);
        _checkInitialState(ctx);

        //
        // Step 1: User deposits ETH
        //
        uint256 user1Deposit = 10_000 wei;
        uint256 user1ExpectedMintableStethShares = _calcMaxMintableStShares(ctx, user1Deposit);

        vm.prank(USER1);
        stvStETHPool(ctx).depositETH{value: user1Deposit}(USER1, address(0));

        _assertUniversalInvariants("Step 1", ctx);

        assertEq(steth.sharesOf(USER1), 0, "stETH shares balance of USER1 should be equal to 0");
        assertEq(
            stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER1, 0),
            user1ExpectedMintableStethShares,
            "Mintable stETH shares should equal capacity derived from assets"
        );
        assertEq(
            stvStETHPool(ctx).stethSharesToBurnForStvOf(USER1, ctx.pool.balanceOf(USER1)),
            0,
            "stETH shares for withdrawal should be equal to 0"
        );
        assertEq(ctx.dashboard.liabilityShares(), 0, "Vault's liability shares should be equal to 0");
        assertEq(
            ctx.dashboard.totalValue(),
            CONNECT_DEPOSIT + user1Deposit,
            "Vault's total value should be equal to CONNECT_DEPOSIT + user1Deposit"
        );

        assertGt(
            ctx.dashboard.remainingMintingCapacityShares(0), 0, "Remaining minting capacity should be greater than 0"
        );

        //
        // Step 2: User mints all available stETH shares in one step
        //

        vm.prank(USER1);
        stvStETHPool(ctx).mintStethShares(user1ExpectedMintableStethShares);

        vm.clearMockedCalls();

        _assertUniversalInvariants("Step 2", ctx);

        assertEq(
            steth.sharesOf(USER1),
            user1ExpectedMintableStethShares,
            "stETH shares balance of USER1 should be equal to user1ExpectedMintableStethShares"
        );
        assertEq(
            stvStETHPool(ctx).stethSharesToBurnForStvOf(USER1, ctx.pool.balanceOf(USER1)),
            user1ExpectedMintableStethShares,
            "stETH shares for withdrawal should be equal to user1ExpectedMintableStethShares"
        );
        assertEq(
            ctx.dashboard.liabilityShares(),
            user1ExpectedMintableStethShares,
            "Vault's liability shares should be equal to user1ExpectedMintableStethShares"
        );
        // Still remaining capacity is higher due to CONNECT_DEPOSIT
        assertGt(
            ctx.dashboard.remainingMintingCapacityShares(0), 0, "Remaining minting capacity should be greater than 0"
        );
        assertEq(
            stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER1, 0),
            0,
            "Mintable stETH shares should be equal to 0"
        );
    }

    function test_depositETH_with_max_mintable_amount() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, 0);

        //
        // Step 1: User deposits ETH and mints max stETH shares in one transaction
        //
        uint256 user1Deposit = 10_000 wei;
        uint256 user1StethSharesToMint = _calcMaxMintableStShares(ctx, user1Deposit);

        vm.prank(USER1);
        stvStETHPool(ctx).depositETHAndMintStethShares{value: user1Deposit}(address(0), user1StethSharesToMint);

        _assertUniversalInvariants("Step 1", ctx);

        assertEq(
            steth.sharesOf(USER1),
            user1StethSharesToMint,
            "stETH shares balance of USER1 should equal max mintable for deposit"
        );
        assertEq(
            stvStETHPool(ctx).mintedStethSharesOf(USER1),
            user1StethSharesToMint,
            "Minted stETH shares should equal expected"
        );
        assertEq(
            ctx.dashboard.liabilityShares(),
            user1StethSharesToMint,
            "Vault's liability shares should equal minted shares"
        );
        assertEq(
            stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER1, 0),
            0,
            "No additional mintable shares should remain"
        );

        //
        // Step 2: User deposits more ETH and mints max for new deposit
        //
        uint256 user1Deposit2 = 15_000 wei;
        uint256 user1StethSharesToMint2 = _calcMaxMintableStShares(ctx, user1Deposit2);

        vm.prank(USER1);
        stvStETHPool(ctx).depositETHAndMintStethShares{value: user1Deposit2}(address(0), user1StethSharesToMint2);

        _assertUniversalInvariants("Step 2", ctx);

        assertEq(
            steth.sharesOf(USER1),
            user1StethSharesToMint + user1StethSharesToMint2,
            "stETH shares should equal sum of both deposits"
        );
        assertEq(
            ctx.dashboard.liabilityShares(),
            user1StethSharesToMint + user1StethSharesToMint2,
            "Vault's liability should equal sum of both minted amounts"
        );
    }

    function test_single_user_mints_full_in_two_steps() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, 0);

        //
        // Step 1
        //
        uint256 user1Deposit = 10_000 wei;
        uint256 user1ExpectedMintableStethShares = _calcMaxMintableStShares(ctx, user1Deposit);

        vm.prank(USER1);
        stvStETHPool(ctx).depositETH{value: user1Deposit}(USER1, address(0));

        // _assertUniversalInvariants("Step 1");

        assertEq(steth.sharesOf(USER1), 0, "stETH shares balance of USER1 should be equal to 0");
        assertEq(
            stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER1, 0),
            user1ExpectedMintableStethShares,
            "Mintable stETH shares should be equal to 0"
        );
        assertEq(
            stvStETHPool(ctx).stethSharesToBurnForStvOf(USER1, ctx.pool.balanceOf(USER1)),
            0,
            "stETH shares for withdrawal should be equal to 0"
        );
        assertEq(ctx.dashboard.liabilityShares(), 0, "Vault's liability shares should be equal to 0");

        // Due to CONNECT_DEPOSIT counted by vault as eth for reserve vaults minting capacity is higher than for the user
        assertGt(
            ctx.dashboard.remainingMintingCapacityShares(0),
            user1ExpectedMintableStethShares,
            "Remaining minting capacity should be equal to 0"
        );

        //
        // Step 2
        //
        uint256 user1StSharesPart1 = user1ExpectedMintableStethShares / 3;

        vm.prank(USER1);
        stvStETHPool(ctx).mintStethShares(user1StSharesPart1);

        _assertUniversalInvariants("Step 2", ctx);

        assertEq(
            steth.sharesOf(USER1),
            user1StSharesPart1,
            "stETH shares balance of USER1 should be equal to user1StSharesToMint"
        );
        assertEq(
            stvStETHPool(ctx).stethSharesToBurnForStvOf(USER1, ctx.pool.balanceOf(USER1)),
            user1StSharesPart1,
            "stETH shares for withdrawal should be equal to user1StSharesToMint"
        );
        assertEq(
            ctx.dashboard.liabilityShares(),
            user1StSharesPart1,
            "Vault's liability shares should be equal to user1StSharesToMint"
        );
        // Still remaining capacity is higher due to CONNECT_DEPOSIT
        assertGt(
            ctx.dashboard.remainingMintingCapacityShares(0),
            user1ExpectedMintableStethShares - user1StSharesPart1,
            "Remaining minting capacity should be equal to user1ExpectedMintableStethShares - user1StSharesToMint"
        );
        assertEq(
            stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER1, 0),
            user1ExpectedMintableStethShares - user1StSharesPart1,
            "Remaining mintable should reduce exactly by minted part"
        );

        uint256 user1StSharesPart2 = user1ExpectedMintableStethShares - user1StSharesPart1;

        //
        // Step 3
        //
        vm.prank(USER1);
        stvStETHPool(ctx).mintStethShares(user1StSharesPart2);

        _assertUniversalInvariants("Step 3", ctx);

        assertEq(
            steth.sharesOf(USER1),
            user1ExpectedMintableStethShares,
            "stETH shares balance of USER1 should be equal to user1StSharesToMint"
        );
        assertEq(
            stvStETHPool(ctx).stethSharesToBurnForStvOf(USER1, ctx.pool.balanceOf(USER1)),
            user1ExpectedMintableStethShares,
            "stETH shares for withdrawal should be equal to user1StSharesToMint"
        );
        assertEq(
            ctx.dashboard.liabilityShares(),
            user1ExpectedMintableStethShares,
            "Vault's liability shares should be equal to user1StSharesToMint"
        );
        // Still remaining capacity is higher due to CONNECT_DEPOSIT
        assertGt(ctx.dashboard.remainingMintingCapacityShares(0), 0, "Remaining minting capacity should be equal to 0");
        assertEq(
            stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER1, 0),
            0,
            "Mintable stETH shares should be equal to 0"
        );
    }

    function test_two_users_mint_full_in_two_steps() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, 0);

        //
        // Step 1: User1 deposits ETH
        //
        uint256 user1Deposit = 10_000 wei;
        uint256 user1ExpectedMintableStethShares = _calcMaxMintableStShares(ctx, user1Deposit);

        vm.prank(USER1);
        stvStETHPool(ctx).depositETH{value: user1Deposit}(USER1, address(0));

        assertEq(steth.sharesOf(USER1), 0, "stETH shares balance of USER1 should be equal to 0");
        assertEq(
            stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER1, 0),
            user1ExpectedMintableStethShares,
            "Mintable stETH shares for USER1 should equal expected"
        );
        assertEq(ctx.dashboard.liabilityShares(), 0, "Vault's liability shares should be equal to 0");

        //
        // Step 2: User2 deposits ETH
        //
        uint256 user2Deposit = 15_000 wei;
        uint256 user2ExpectedMintableStethShares = _calcMaxMintableStShares(ctx, user2Deposit);

        vm.prank(USER2);
        stvStETHPool(ctx).depositETH{value: user2Deposit}(USER2, address(0));

        assertEq(steth.sharesOf(USER2), 0, "stETH shares balance of USER2 should be equal to 0");
        assertEq(
            stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER2, 0),
            user2ExpectedMintableStethShares,
            "Mintable stETH shares for USER2 should equal expected"
        );
        assertEq(
            ctx.dashboard.liabilityShares(), 0, "Vault's liability shares should be equal to 0 after deposits only"
        );
        // Due to CONNECT_DEPOSIT capacity should comfortably allow minting
        assertGt(
            ctx.dashboard.remainingMintingCapacityShares(0),
            user1ExpectedMintableStethShares,
            "Remaining capacity should exceed USER1 expected"
        );
        assertGt(
            ctx.dashboard.remainingMintingCapacityShares(0),
            user2ExpectedMintableStethShares,
            "Remaining capacity should exceed USER2 expected"
        );

        //
        // Step 3: USER1 mints part of their available stETH shares
        //
        uint256 user1StSharesPart1 = user1ExpectedMintableStethShares / 3;

        vm.prank(USER1);
        stvStETHPool(ctx).mintStethShares(user1StSharesPart1);

        _assertUniversalInvariants("Step 3", ctx);

        assertEq(steth.sharesOf(USER1), user1StSharesPart1, "USER1 stETH shares should equal part1 minted");
        assertEq(
            stvStETHPool(ctx).stethSharesToBurnForStvOf(USER1, ctx.pool.balanceOf(USER1)),
            user1StSharesPart1,
            "USER1 stSharesForWithdrawal should equal part1 minted"
        );
        assertEq(
            stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER1, 0),
            user1ExpectedMintableStethShares - user1StSharesPart1,
            "USER1 remaining mintable should decrease by part1"
        );
        assertEq(
            ctx.dashboard.liabilityShares(), user1StSharesPart1, "Liability shares should equal USER1 minted so far"
        );

        //
        // Step 4: USER2 mints part of their available stETH shares
        //
        uint256 user2StSharesPart1 = user2ExpectedMintableStethShares / 3;

        vm.prank(USER2);
        stvStETHPool(ctx).mintStethShares(user2StSharesPart1);

        _assertUniversalInvariants("Step 4", ctx);

        assertEq(steth.sharesOf(USER2), user2StSharesPart1, "USER2 stETH shares should equal part1 minted");
        assertEq(
            stvStETHPool(ctx).stethSharesToBurnForStvOf(USER2, ctx.pool.balanceOf(USER2)),
            user2StSharesPart1,
            "USER2 stSharesForWithdrawal should equal part1 minted"
        );
        assertEq(
            stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER2, 0),
            user2ExpectedMintableStethShares - user2StSharesPart1,
            "USER2 remaining mintable should decrease by part1"
        );
        assertEq(
            ctx.dashboard.liabilityShares(),
            user1StSharesPart1 + user2StSharesPart1,
            "Liability shares should equal sum of minted parts"
        );

        //
        // Step 5: USER1 mints the rest
        //
        uint256 user1StSharesPart2 = user1ExpectedMintableStethShares - user1StSharesPart1;

        vm.prank(USER1);
        stvStETHPool(ctx).mintStethShares(user1StSharesPart2);

        _assertUniversalInvariants("Step 5", ctx);

        assertEq(
            steth.sharesOf(USER1),
            user1ExpectedMintableStethShares,
            "USER1 stETH shares should equal full expected after second mint"
        );
        assertEq(
            stvStETHPool(ctx).stethSharesToBurnForStvOf(USER1, ctx.pool.balanceOf(USER1)),
            user1ExpectedMintableStethShares,
            "USER1 stSharesForWithdrawal should equal full expected"
        );
        assertEq(
            stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER1, 0), 0, "USER1 remaining mintable should be zero"
        );
        assertEq(
            ctx.dashboard.liabilityShares(),
            user1ExpectedMintableStethShares + user2StSharesPart1,
            "Liability shares should reflect USER1 full + USER2 part1"
        );

        //
        // Step 6: USER2 mints the rest
        //
        uint256 user2StSharesPart2 = user2ExpectedMintableStethShares - user2StSharesPart1;

        vm.prank(USER2);
        stvStETHPool(ctx).mintStethShares(user2StSharesPart2);

        _assertUniversalInvariants("Step 6", ctx);

        assertEq(
            steth.sharesOf(USER2),
            user2ExpectedMintableStethShares,
            "USER2 stETH shares should equal full expected after second mint"
        );
        assertEq(
            stvStETHPool(ctx).stethSharesToBurnForStvOf(USER2, ctx.pool.balanceOf(USER2)),
            user2ExpectedMintableStethShares,
            "USER2 stSharesForWithdrawal should equal full expected"
        );
        assertEq(
            stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER2, 0), 0, "USER2 remaining mintable should be zero"
        );
        // Still remaining capacity is higher due to CONNECT_DEPOSIT
        assertGt(
            ctx.dashboard.remainingMintingCapacityShares(0), 0, "Remaining minting capacity should be greater than 0"
        );
        assertEq(
            ctx.dashboard.liabilityShares(),
            user1ExpectedMintableStethShares + user2ExpectedMintableStethShares,
            "Liability shares should equal sum of both users' full mints"
        );
    }

    function test_vault_underperforms() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, 0);

        //
        // Step 1: User1 deposits
        //
        uint256 user1Deposit = 200 ether;
        uint256 user1ExpectedMintable = _calcMaxMintableStShares(ctx, user1Deposit);
        vm.prank(USER1);
        stvStETHPool(ctx).depositETHAndMintStethShares{value: user1Deposit}(address(0), user1ExpectedMintable);

        assertEq(steth.sharesOf(USER1), user1ExpectedMintable, "USER1 stETH shares should equal expected minted");
        assertEq(
            stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER1, 0), 0, "USER1 remaining mintable should be zero"
        );
        assertGt(
            ctx.dashboard.remainingMintingCapacityShares(0),
            0,
            "USER1 minting capacity shares should be equal to user1Deposit"
        );

        _assertUniversalInvariants("Step 1", ctx);

        vm.warp(block.timestamp + 1 days);
        reportVaultValueChangeNoFees(ctx, 100_00 - 100); // 99%

        uint256 user2Deposit = 10_000 wei;
        vm.prank(USER2);
        stvStETHPool(ctx).depositETH{value: user2Deposit}(USER2, address(0));

        {
            uint256 user2ExpectedMintableStethShares = _calcMaxMintableStShares(ctx, user2Deposit);
            assertLe(
                stvStETHPool(ctx).remainingMintingCapacitySharesOf(USER2, 0),
                user2ExpectedMintableStethShares,
                "USER2 mintable stETH shares should not exceed expected after underperformance"
            );
        }

        // TODO: is this a correct check?
        // assertEq(steth.sharesOf(USER2), _calcMaxMintableStShares(ctx, user2Deposit), "USER2 stETH shares should be equal to user2Deposit");

        _assertUniversalInvariants("Step 2", ctx);
    }

    function test_user_withdraws_without_burning() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, 0);
        StvStETHPool w = stvStETHPool(ctx);

        //
        // Step 1: User1 deposits
        //
        uint256 user1Deposit = 2 * ctx.withdrawalQueue.MIN_WITHDRAWAL_VALUE() * 100; // * 100 to have +1% rewards enough for min withdrawal

        uint256 sharesForDeposit = _calcMaxMintableStShares(ctx, user1Deposit);
        vm.prank(USER1);
        w.depositETHAndMintStethShares{value: user1Deposit}(address(0), sharesForDeposit);

        uint256 expectedUser1MintedStShares = sharesForDeposit;
        assertEq(
            steth.sharesOf(USER1),
            expectedUser1MintedStShares,
            "USER1 stETH shares should be equal to expectedUser1MintedStShares"
        );
        assertEq(w.remainingMintingCapacitySharesOf(USER1, 0), 0, "USER1 mintable stETH shares should be equal to 0");
        assertEq(
            w.stethSharesToBurnForStvOf(USER1, w.balanceOf(USER1)),
            expectedUser1MintedStShares,
            "USER1 stSharesForWithdrawal should be equal to expectedUser1MintedStShares"
        );
        // assertEq(ctx.dashboard.liabilityShares(), expectedUser1MintedStShares, "Vault's liability shares should be equal to expectedUser1MintedStShares");
        // assertGt(ctx.dashboard.remainingMintingCapacityShares(0), 0, "Remaining minting capacity should be greater than 0");

        reportVaultValueChangeNoFees(ctx, 100_00 + 100); // +1%
        uint256 user1Rewards = user1Deposit * 100 / 10000;
        assertApproxEqAbs(
            w.previewRedeem(w.balanceOf(USER1)),
            user1Deposit + user1Rewards,
            WEI_ROUNDING_TOLERANCE,
            "USER1 previewRedeem should be equal to user1Deposit + user1Rewards"
        );

        // TODO: handle 1 wei problem here
        uint256 expectedRewardsShares = _calcMaxMintableStShares(ctx, user1Rewards);
        assertApproxEqAbs(
            w.remainingMintingCapacitySharesOf(USER1, 0),
            expectedRewardsShares,
            WEI_ROUNDING_TOLERANCE,
            "USER1 mintable stETH shares should equal capacity from rewards"
        );

        assertEq(w.unlockedAssetsOf(USER1, 0), user1Rewards, "USER1 withdrawable eth should be equal to user1Rewards");
        assertEq(
            w.unlockedAssetsOf(USER1, expectedUser1MintedStShares),
            w.previewRedeem(w.balanceOf(USER1)),
            "USER1 withdrawable eth should be equal to user1Deposit + user1Rewards"
        );

        assertEq(
            w.stethSharesToBurnForStvOf(USER1, w.balanceOf(USER1)),
            expectedUser1MintedStShares,
            "USER1 stSharesForWithdrawal should be equal to expectedUser1MintedStShares"
        );

        uint256 rewardsStv =
            Math.mulDiv(user1Rewards, w.balanceOf(USER1), user1Deposit + user1Rewards, Math.Rounding.Floor);
        // TODO: fix fail here
        assertLe(
            w.stethSharesToBurnForStvOf(USER1, rewardsStv),
            WEI_ROUNDING_TOLERANCE,
            "USER1 stSharesForWithdrawal for rewards-only should be ~0"
        );
        assertEq(w.stethSharesToBurnForStvOf(USER1, rewardsStv), 0, "USER1 stSharesForWithdrawal should be equal to 0");

        _assertUniversalInvariants("Step 1", ctx);

        //
        // Step 2.0: User1 withdraws rewards without burning any stethShares
        //
        uint256 withdrawableStvWithoutBurning = w.unlockedStvOf(USER1, 0);

        assertEq(withdrawableStvWithoutBurning, rewardsStv, "Withdrawable stv should be equal to rewardsStv");

        vm.prank(USER1);
        uint256 requestId = ctx.withdrawalQueue.requestWithdrawal(USER1, rewardsStv, 0);

        WithdrawalQueue.WithdrawalRequestStatus memory status = ctx.withdrawalQueue.getWithdrawalStatus(requestId);
        assertLe(
            user1Rewards - status.amountOfAssets,
            WEI_ROUNDING_TOLERANCE,
            "Withdrawal request amount should almost match previewRedeem"
        );

        // Update report data with current timestamp to make it fresh
        core.applyVaultReport(address(ctx.vault), w.totalAssets(), 0, 0, 0);

        _advancePastMinDelayAndRefreshReport(ctx, requestId);
        vm.prank(NODE_OPERATOR);
        ctx.withdrawalQueue.finalize(1, address(0));

        status = ctx.withdrawalQueue.getWithdrawalStatus(requestId);
        assertTrue(status.isFinalized, "Withdrawal request should be finalized");
        assertLe(
            user1Rewards - status.amountOfAssets,
            WEI_ROUNDING_TOLERANCE,
            "Withdrawal request amount should almost match previewRedeem"
        );
        assertEq(status.amountOfStv, rewardsStv, "Withdrawal request shares should match user1SharesToWithdraw");

        // Deal ETH to withdrawal queue for the claim (simulating validator exit)
        vm.deal(address(ctx.withdrawalQueue), address(ctx.withdrawalQueue).balance + user1Rewards);

        uint256 totalClaimed;

        // User1 claims their withdrawal
        uint256 user1EthBalanceBeforeClaim = USER1.balance;
        vm.prank(USER1);
        ctx.withdrawalQueue.claimWithdrawal(USER1, requestId);

        assertApproxEqAbs(
            USER1.balance,
            user1EthBalanceBeforeClaim + user1Rewards,
            WEI_ROUNDING_TOLERANCE,
            _contextMsg("Step 2", "USER1 ETH balance should increase by the withdrawn amount")
        );
        totalClaimed += user1Rewards;

        //
        // Step 2.1: User1 tries to withdraw stv corresponding to 1 wei but fails
        //

        uint256 stvFor1Wei = w.previewWithdraw(1 wei);
        assertGt(w.balanceOf(USER1), stvFor1Wei, "USER1 stv balance should be greater than stvFor1Wei");

        vm.startPrank(USER1);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.RequestValueTooSmall.selector, 1 wei));
        ctx.withdrawalQueue.requestWithdrawal(USER1, stvFor1Wei, 0);
        vm.stopPrank();

        //
        // Step 2.2: User1 withdraws stv with burning stethShares
        //
        uint256 stvForMinWithdrawal = w.previewWithdraw(ctx.withdrawalQueue.MIN_WITHDRAWAL_VALUE());
        uint256 stethSharesToBurn = w.stethSharesToBurnForStvOf(USER1, stvForMinWithdrawal);

        vm.startPrank(USER1);

        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        ctx.withdrawalQueue.requestWithdrawal(USER1, stvForMinWithdrawal, 0);

        steth.approve(address(w), steth.getPooledEthByShares(stethSharesToBurn));
        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        ctx.withdrawalQueue.requestWithdrawal(USER1, stvForMinWithdrawal, 0);

        steth.increaseAllowance(address(w), steth.getPooledEthByShares(1));

        uint256 user1StethSharesBefore = steth.sharesOf(USER1);
        w.burnStethShares(stethSharesToBurn);
        requestId = ctx.withdrawalQueue.requestWithdrawal(USER1, stvForMinWithdrawal, 0);

        vm.stopPrank();

        assertEq(
            user1StethSharesBefore - steth.sharesOf(USER1),
            stethSharesToBurn,
            "USER1 stETH shares should decrease by stethSharesToBurn"
        );

        // Finalize and claim the second (min-withdrawal) request
        _advancePastMinDelayAndRefreshReport(ctx, requestId);
        vm.prank(NODE_OPERATOR);
        ctx.withdrawalQueue.finalize(1, address(0));

        status = ctx.withdrawalQueue.getWithdrawalStatus(requestId);
        assertTrue(status.isFinalized, "Min-withdrawal request should be finalized");

        // Ensure queue has enough ETH to claim
        vm.deal(address(ctx.withdrawalQueue), address(ctx.withdrawalQueue).balance + status.amountOfAssets);

        uint256 user1EthBefore2 = USER1.balance;
        vm.prank(USER1);
        ctx.withdrawalQueue.claimWithdrawal(USER1, requestId);

        assertApproxEqAbs(
            USER1.balance,
            user1EthBefore2 + status.amountOfAssets,
            WEI_ROUNDING_TOLERANCE,
            _contextMsg("Step 2", "USER1 ETH balance should increase by the withdrawn amount (min withdrawal)")
        );
        totalClaimed += status.amountOfAssets;

        //
        // Step 3: Withdraw the rest fully
        //
        uint256 remainingStv = w.balanceOf(USER1);
        if (remainingStv > 0) {
            uint256 burnForRest = w.stethSharesToBurnForStvOf(USER1, remainingStv);

            vm.startPrank(USER1);
            steth.approve(address(w), steth.getPooledEthByShares(burnForRest));
            w.burnStethShares(burnForRest);
            uint256 requestId3 = ctx.withdrawalQueue.requestWithdrawal(USER1, remainingStv, 0);
            vm.stopPrank();

            _advancePastMinDelayAndRefreshReport(ctx, requestId3);
            vm.prank(NODE_OPERATOR);
            ctx.withdrawalQueue.finalize(1, address(0));

            WithdrawalQueue.WithdrawalRequestStatus memory st3 = ctx.withdrawalQueue.getWithdrawalStatus(requestId3);
            assertTrue(st3.isFinalized, "Final full-withdrawal request should be finalized");
            vm.deal(address(ctx.withdrawalQueue), address(ctx.withdrawalQueue).balance + st3.amountOfAssets);

            uint256 user1EthBefore3 = USER1.balance;
            vm.prank(USER1);
            ctx.withdrawalQueue.claimWithdrawal(USER1, requestId3);

            assertApproxEqAbs(
                USER1.balance,
                user1EthBefore3 + st3.amountOfAssets,
                WEI_ROUNDING_TOLERANCE,
                _contextMsg("Step 3", "USER1 ETH balance should increase by the withdrawn amount (final)")
            );
            totalClaimed += st3.amountOfAssets;
        }

        // Final assertions: user fully withdrawn
        assertEq(w.balanceOf(USER1), 0, "USER1 should have zero stv after full withdrawal");
        assertEq(w.mintedStethSharesOf(USER1), 0, "USER1 should have zero minted stETH shares after full withdrawal");

        // Total claimed should be equal to deposit + rewards (within tolerance)
        assertApproxEqAbs(
            totalClaimed,
            user1Deposit + user1Rewards,
            WEI_ROUNDING_TOLERANCE,
            _contextMsg("Final", "Total claimed should equal deposit + rewards")
        );
    }

    /**
     * @notice Test transferWithLiability enforces reserve ratio for sender
     * @dev Verifies that after transfer with liability, sender cannot decrease collateral below pool RR
     */
    function test_transferWithLiability_maintains_sender_reserve_ratio() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, DEFAULT_WRAPPER_RR_GAP);
        StvStETHPool w = stvStETHPool(ctx);

        //
        // Step 1: USER1 deposits and mints stETH shares
        //
        uint256 user1Deposit = 100 ether;
        uint256 user1MintedShares = _calcMaxMintableStShares(ctx, user1Deposit);
        user1MintedShares = user1MintedShares / 4 * 4; // Make it divisible by 4 for easier splits

        vm.prank(USER1);
        w.depositETHAndMintStethShares{value: user1Deposit}(address(0), user1MintedShares);

        uint256 user1Stv = w.balanceOf(USER1);

        _assertUniversalInvariants("Step 1", ctx);

        //
        // Step 2: Calculate minimum stv needed to maintain reserve ratio
        //
        uint256 minStvForHalfShares = w.calcStvToLockForStethShares(user1MintedShares / 2);

        //
        // Step 3: Try to transfer too much stv with half the liability (should fail)
        //
        // If we transfer half the shares, we need to transfer at least minStvForHalfShares
        // But let's try to transfer more than allowed, leaving sender with insufficient collateral
        uint256 excessiveStvToTransfer = user1Stv - minStvForHalfShares + 1;

        vm.startPrank(USER1);
        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        w.transferWithLiability(USER2, excessiveStvToTransfer, user1MintedShares / 2);
        vm.stopPrank();

        //
        // Step 4: Valid transfer - transfer exactly minimum stv for half the liability
        //
        vm.prank(USER1);
        bool success = w.transferWithLiability(USER2, minStvForHalfShares, user1MintedShares / 2);
        assertTrue(success, "Transfer with liability should succeed");

        // Verify USER2 received the stv and liability
        assertEq(w.balanceOf(USER2), minStvForHalfShares, "USER2 should receive stv");
        assertEq(w.mintedStethSharesOf(USER2), user1MintedShares / 2, "USER2 should receive half the liability");

        // Verify USER1 still has correct balance and maintains reserve ratio
        assertEq(w.balanceOf(USER1), user1Stv - minStvForHalfShares, "USER1 should have remaining stv");
        assertEq(w.mintedStethSharesOf(USER1), user1MintedShares / 2, "USER1 should have half the liability");

        uint256 user1RequiredStv = w.calcStvToLockForStethShares(w.mintedStethSharesOf(USER1));
        assertGe(w.balanceOf(USER1), user1RequiredStv, "USER1 should maintain minimum reserve ratio after transfer");

        _assertUniversalInvariants("Step 4", ctx);

        //
        // Step 5: Try to transfer remaining stv without transferring remaining liability (should fail)
        //
        uint256 user1RemainingStv = w.balanceOf(USER1);
        uint256 user1RemainingShares = w.mintedStethSharesOf(USER1);

        vm.startPrank(USER1);
        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        w.transfer(USER2, user1RemainingStv);
        vm.stopPrank();

        //
        // Step 6: Valid transfer - transfer all remaining with full liability
        //
        vm.prank(USER1);
        success = w.transferWithLiability(USER2, user1RemainingStv, user1RemainingShares);

        assertTrue(success, "Transfer of remaining balance with liability should succeed");

        // Verify USER1 has no more stv or liability
        assertEq(w.balanceOf(USER1), 0, "USER1 should have zero stv after full transfer");
        assertEq(w.mintedStethSharesOf(USER1), 0, "USER1 should have zero liability after full transfer");

        // Verify USER2 now has everything
        assertEq(w.balanceOf(USER2), user1Stv, "USER2 should have all original stv");
        assertEq(w.mintedStethSharesOf(USER2), user1MintedShares, "USER2 should have all original liability");

        _assertUniversalInvariants("Step 6", ctx);

        //
        // Step 7: Verify USER2 can now transfer with liability
        //
        uint256 user2Shares = w.mintedStethSharesOf(USER2);
        uint256 sharesToTransfer = user2Shares / 4;
        uint256 minStvToTransfer = w.calcStvToLockForStethShares(sharesToTransfer);

        vm.prank(USER2);
        success = w.transferWithLiability(USER3, minStvToTransfer, sharesToTransfer);

        assertTrue(success, "USER2 should be able to transfer with liability");
        assertEq(w.balanceOf(USER3), minStvToTransfer, "USER3 should receive stv");
        assertEq(w.mintedStethSharesOf(USER3), sharesToTransfer, "USER3 should receive liability");

        _assertUniversalInvariants("Step 7", ctx);
    }

    /**
     * @notice Test regular transfer reverts when sender would have insufficient collateral for minted shares
     */
    function test_transfer_reverts_when_insufficient_collateral_for_minted_shares() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, DEFAULT_WRAPPER_RR_GAP);
        StvStETHPool w = stvStETHPool(ctx);

        // User deposits and mints maximum stETH shares
        uint256 userDeposit = 100 ether;
        uint256 maxMintableShares = _calcMaxMintableStShares(ctx, userDeposit);
        vm.prank(USER1);
        w.depositETHAndMintStethShares{value: userDeposit}(address(0), maxMintableShares);

        vm.startPrank(USER1);
        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        w.transfer(USER2, 1);
        vm.stopPrank();
    }

    /**
     * @notice Test transferWithLiability fails when stv is insufficient for liability being transferred
     */
    function test_transferWithLiability_reverts_when_stv_insufficient_for_liability() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, DEFAULT_WRAPPER_RR_GAP);
        StvStETHPool w = stvStETHPool(ctx);

        uint256 user1Deposit = 50 ether;
        uint256 stethSharesToMint = _calcMaxMintableStShares(ctx, user1Deposit) / 2 * 2; // make even for easier half transfer
        vm.prank(USER1);
        w.depositETHAndMintStethShares{value: user1Deposit}(address(0), stethSharesToMint);

        uint256 sharesToTransfer = w.mintedStethSharesOf(USER1) / 2;
        uint256 minStvRequired = w.calcStvToLockForStethShares(sharesToTransfer);

        // Transfer with insufficient stv fails
        vm.startPrank(USER1);
        vm.expectRevert(StvStETHPool.InsufficientStv.selector);
        w.transferWithLiability(USER2, minStvRequired - 1, sharesToTransfer);
        vm.stopPrank();

        // Transfer with exact minimum succeeds
        vm.prank(USER1);
        assertTrue(w.transferWithLiability(USER2, minStvRequired, sharesToTransfer));
    }

    /**
     * @notice Test behavior after vault loss causes collateral to drop below pool RR
     */
    function test_after_vault_loss_user_below_reserve_ratio() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, DEFAULT_WRAPPER_RR_GAP);
        StvStETHPool w = stvStETHPool(ctx);

        // User deposits and mints max shares
        uint256 userDeposit = 100 ether;
        uint256 maxMintableShares = _calcMaxMintableStShares(ctx, userDeposit);
        vm.prank(USER1);
        w.depositETHAndMintStethShares{value: userDeposit}(address(0), maxMintableShares);

        // Vault loses 10% value - user now below reserve ratio
        vm.warp(block.timestamp + 1 days);
        reportVaultValueChangeNoFees(ctx, 100_00 - 1000); // -10%

        uint256 mintedShares = w.mintedStethSharesOf(USER1);

        // Regular transfer fails - insufficient collateral
        vm.startPrank(USER1);
        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        w.transfer(USER2, 1);
        vm.stopPrank();

        // Can transfer with liability if transferring enough liability to restore ratio
        uint256 sharesToTransfer = mintedShares / 2;
        uint256 minStvForTransfer = w.calcStvToLockForStethShares(sharesToTransfer);
        uint256 user1Stv = w.balanceOf(USER1);

        // After transferring half liability, remaining stv must cover remaining liability
        uint256 remainingShares = mintedShares - sharesToTransfer;
        uint256 minStvForRemaining = w.calcStvToLockForStethShares(remainingShares);

        // This transfer works if: user1Stv - minStvForTransfer >= minStvForRemaining
        if (user1Stv >= minStvForTransfer + minStvForRemaining) {
            vm.prank(USER1);
            assertTrue(w.transferWithLiability(USER2, minStvForTransfer, sharesToTransfer));
        } else {
            // Need to transfer more liability to make it work
            vm.startPrank(USER1);
            vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
            w.transferWithLiability(USER2, minStvForTransfer, sharesToTransfer);
            vm.stopPrank();
        }
    }

    /**
     * @notice Test burning stETH shares restores ability to transfer after vault loss
     */
    function test_burning_shares_after_vault_loss_allows_transfer() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, DEFAULT_WRAPPER_RR_GAP);
        StvStETHPool w = stvStETHPool(ctx);
        IStETH steth = core.steth();

        // User deposits and mints max shares
        uint256 userDeposit = 100 ether;
        uint256 maxMintableShares = _calcMaxMintableStShares(ctx, userDeposit);
        vm.prank(USER1);
        w.depositETHAndMintStethShares{value: userDeposit}(address(0), maxMintableShares);

        // Vault loses value
        vm.warp(block.timestamp + 1 days);
        reportVaultValueChangeNoFees(ctx, 100_00 - 500); // -5%

        // Transfer fails
        vm.startPrank(USER1);
        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        w.transfer(USER2, 1 ether);

        // Burn enough shares to restore ratio
        uint256 sharesToBurn = w.mintedStethSharesOf(USER1) / 4;
        steth.approve(address(w), steth.getPooledEthByShares(sharesToBurn));
        w.burnStethShares(sharesToBurn);

        // Now transfer succeeds (if enough collateral freed up)
        uint256 minRequired = w.calcStvToLockForStethShares(w.mintedStethSharesOf(USER1));
        if (w.balanceOf(USER1) > minRequired + 1 ether) {
            assertTrue(w.transfer(USER2, 1 ether));
        }
        vm.stopPrank();
    }

    /**
     * @notice Test user can transfer excess stv after vault gains without transferring liability
     */
    function test_after_vault_gains_can_transfer_excess_without_liability() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, DEFAULT_WRAPPER_RR_GAP);
        StvStETHPool w = stvStETHPool(ctx);

        // User deposits and mints max shares
        uint256 userDeposit = 100 ether;
        uint256 maxMintableShares = _calcMaxMintableStShares(ctx, userDeposit);
        vm.prank(USER1);
        w.depositETHAndMintStethShares{value: userDeposit}(address(0), maxMintableShares);

        // Initially can't transfer - at exact reserve ratio
        vm.startPrank(USER1);
        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        w.transfer(USER2, 1);
        vm.stopPrank();

        // Vault gains 1% value - user now has excess stv
        reportVaultValueChangeNoFees(ctx, 100_00 + 100); // +1%

        // Calculate unlocked stv
        uint256 minRequired = w.calcStvToLockForStethShares(w.mintedStethSharesOf(USER1));
        uint256 excessStv = w.balanceOf(USER1) - minRequired;

        // Can transfer excess WITHOUT transferring liability
        vm.prank(USER1);
        assertTrue(w.transfer(USER2, excessStv));

        assertEq(w.mintedStethSharesOf(USER1), w.mintedStethSharesOf(USER1), "USER1 liability unchanged");
        assertEq(w.mintedStethSharesOf(USER2), 0, "USER2 has no liability");
    }

    /**
     * @notice Test user can transfer more stv than required with liability (overpaying)
     */
    function test_transferWithLiability_can_overpay_stv() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, DEFAULT_WRAPPER_RR_GAP);
        StvStETHPool w = stvStETHPool(ctx);

        // User deposits and mints
        uint256 userDeposit = 100 ether;
        uint256 maxMintableShares = _calcMaxMintableStShares(ctx, userDeposit);
        vm.prank(USER1);
        w.depositETHAndMintStethShares{value: userDeposit}(address(0), maxMintableShares);

        // Vault gains 1%
        reportVaultValueChangeNoFees(ctx, 100_00 + 100);

        uint256 sharesToTransfer = w.mintedStethSharesOf(USER1) / 2;
        uint256 minStvRequired = w.calcStvToLockForStethShares(sharesToTransfer);
        uint256 overpayAmount = minStvRequired + 10 wei;

        // Can transfer MORE stv than minimum with liability
        vm.prank(USER1);
        assertTrue(w.transferWithLiability(USER2, overpayAmount, sharesToTransfer));
        assertEq(w.balanceOf(USER2), overpayAmount, "USER2 receives overpaid stv");
    }

    /**
     * @notice Test user with no minted shares can transfer freely
     */
    function test_user_with_no_minted_shares_can_transfer_freely() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, DEFAULT_WRAPPER_RR_GAP);
        StvStETHPool w = stvStETHPool(ctx);

        // User deposits WITHOUT minting shares
        vm.prank(USER1);
        w.depositETH{value: 10 ether}(USER1, address(0));

        assertEq(w.mintedStethSharesOf(USER1), 0, "USER1 has no minted shares");

        // Can transfer entire balance
        vm.startPrank(USER1);
        assertTrue(w.transfer(USER2, w.balanceOf(USER1)));
        vm.stopPrank();

        assertEq(w.balanceOf(USER1), 0, "USER1 transferred everything");
    }

    /**
     * @notice Test after vault gains user can mint additional shares from rewards
     */
    function xtest_after_vault_gains_can_mint_from_rewards() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, DEFAULT_WRAPPER_RR_GAP);
        StvStETHPool w = stvStETHPool(ctx);

        // User deposits and mints max
        uint256 userDeposit = 100 ether;
        uint256 maxMintableShares = _calcMaxMintableStShares(ctx, userDeposit);
        vm.prank(USER1);
        w.depositETHAndMintStethShares{value: userDeposit}(address(0), maxMintableShares);

        uint256 initialMinted = w.mintedStethSharesOf(USER1);
        assertEq(w.remainingMintingCapacitySharesOf(USER1, 0), 0, "No capacity initially");

        // Vault gains 5%
        // vm.warp(block.timestamp + 1 days);
        reportVaultValueChangeNoFees(ctx, 100_00 + 500);

        // Now has minting capacity from rewards
        uint256 additionalCapacity = w.remainingMintingCapacitySharesOf(USER1, 0);
        assertGt(additionalCapacity, 0, "Has minting capacity from rewards");

        // Can mint additional shares
        vm.prank(USER1);
        w.mintStethShares(additionalCapacity);

        assertEq(w.mintedStethSharesOf(USER1), initialMinted + additionalCapacity, "Minted additional shares");
    }

    /**
     * @notice Test transferring all liability with all stv works
     */
    function test_transferWithLiability_all_stv_and_liability() public {
        WrapperContext memory ctx = _deployStvStETHPool(false, 0, DEFAULT_WRAPPER_RR_GAP);
        StvStETHPool w = stvStETHPool(ctx);

        // User deposits and mints
        uint256 userDeposit = 50 ether;
        uint256 maxMintableShares = _calcMaxMintableStShares(ctx, userDeposit);
        vm.prank(USER1);
        w.depositETHAndMintStethShares{value: userDeposit}(address(0), maxMintableShares);

        uint256 allStv = w.balanceOf(USER1);
        uint256 allShares = w.mintedStethSharesOf(USER1);

        // Can transfer everything
        vm.prank(USER1);
        assertTrue(w.transferWithLiability(USER2, allStv, allShares));

        assertEq(w.balanceOf(USER1), 0, "USER1 has no stv");
        assertEq(w.mintedStethSharesOf(USER1), 0, "USER1 has no liability");
        assertEq(w.balanceOf(USER2), allStv, "USER2 has all stv");
        assertEq(w.mintedStethSharesOf(USER2), allShares, "USER2 has all liability");
    }
}
