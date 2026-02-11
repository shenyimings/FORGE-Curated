// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {StvPoolHarness} from "test/utils/StvPoolHarness.sol";

/**
 * @title StvPoolTest
 * @notice Integration tests for StvPool (no minting, no strategy)
 */
contract StvPoolTest is StvPoolHarness {
    function setUp() public {
        _initializeCore();
    }

    function test_happy_path_deposit_request_finalize_claim_no_rewards() public {
        // Deploy pool system
        WrapperContext memory ctx = _deployStvPool(false, 0);

        // 1) USER1 deposits 0.01 ether (above MIN_WITHDRAWAL_VALUE)
        uint256 depositAmount = 0.01 ether;
        uint256 expectedStv = ctx.pool.previewDeposit(depositAmount);
        vm.prank(USER1);
        ctx.pool.depositETH{value: depositAmount}(USER1, address(0));
        assertEq(ctx.pool.balanceOf(USER1), expectedStv, "minted shares should match previewDeposit");
        assertEq(
            address(ctx.vault).balance, depositAmount + CONNECT_DEPOSIT, "vault balance should match deposit amount"
        );

        // 2) USER1 immediately requests withdrawal of all their shares
        vm.prank(USER1);
        uint256 requestId = ctx.withdrawalQueue.requestWithdrawal(USER1, expectedStv, 0);

        // Expected ETH to withdraw
        uint256 expectedEth = ctx.pool.previewRedeem(expectedStv);

        // 3) Advance past min delay and ensure fresh report via harness
        _advancePastMinDelayAndRefreshReport(ctx, requestId);

        // 4) Node Operator finalizes one request
        vm.prank(NODE_OPERATOR);
        ctx.withdrawalQueue.finalize(1, address(0));

        // 5) USER1 claims
        uint256 userBalanceBefore = USER1.balance;
        vm.prank(USER1);
        ctx.withdrawalQueue.claimWithdrawal(USER1, requestId);

        assertEq(USER1.balance, userBalanceBefore + expectedEth, "user should receive expected ETH on claim");
    }

    function test_happy_path_deposit_request_finalize_claim_with_rewards_report() public {
        // Deploy pool system
        WrapperContext memory ctx = _deployStvPool(false, 0);

        // 1) USER1 deposits 0.01 ether (above MIN_WITHDRAWAL_VALUE)
        uint256 depositAmount = 0.01 ether;
        uint256 expectedStv = ctx.pool.previewDeposit(depositAmount);
        vm.prank(USER1);
        ctx.pool.depositETH{value: depositAmount}(USER1, address(0));
        assertEq(ctx.pool.balanceOf(USER1), expectedStv, "minted shares should match previewDeposit");
        assertEq(
            address(ctx.vault).balance, depositAmount + CONNECT_DEPOSIT, "vault balance should match deposit amount"
        );

        // 2) USER1 immediately requests withdrawal of all their shares
        vm.prank(USER1);
        uint256 requestId = ctx.withdrawalQueue.requestWithdrawal(USER1, expectedStv, 0);

        // Expected ETH to withdraw is locked at request time
        uint256 expectedEth = ctx.pool.previewRedeem(expectedStv);
        assertEq(expectedEth, depositAmount, "expected eth should match deposit amount");
        // 3) Advance past min delay
        _advancePastMinDelayAndRefreshReport(ctx, requestId);

        // 4) Apply +3% rewards via vault report BEFORE finalization
        //    This increases total value but should not discount the request
        reportVaultValueChangeNoFees(ctx, 10300); // +3%

        // 6) Node Operator finalizes one request
        vm.prank(NODE_OPERATOR);
        ctx.withdrawalQueue.finalize(1, address(0));

        // 7) USER1 claims
        uint256 userBalanceBefore = USER1.balance;
        vm.prank(USER1);
        ctx.withdrawalQueue.claimWithdrawal(USER1, requestId);

        // Expected claim equals the amount locked at request time (no discount on rewards)
        assertEq(USER1.balance, userBalanceBefore + expectedEth, "user should receive expected ETH on claim");
    }

    function test_happy_path_deposit_request_finalize_claim_with_rewards_report_before_request() public {
        // Deploy pool system
        WrapperContext memory ctx = _deployStvPool(false, 0);

        // 1) USER1 deposits 0.01 ether (above MIN_WITHDRAWAL_VALUE)
        uint256 depositAmount = 0.01 ether;
        uint256 expectedStv = ctx.pool.previewDeposit(depositAmount);
        vm.prank(USER1);
        ctx.pool.depositETH{value: depositAmount}(USER1, address(0));
        assertEq(ctx.pool.balanceOf(USER1), expectedStv, "minted shares should match previewDeposit");
        assertEq(
            address(ctx.vault).balance, depositAmount + CONNECT_DEPOSIT, "vault balance should match deposit amount"
        );

        // 2) Apply +3% rewards via vault report BEFORE withdrawal request
        reportVaultValueChangeNoFees(ctx, 10300); // +3%

        // 3) Now request withdrawal of all USER1 shares
        //    Expected ETH is increased by ~3% compared to initial deposit
        uint256 expectedEth = ctx.pool.previewRedeem(expectedStv);
        assertApproxEqAbs(
            expectedEth, (depositAmount * 103) / 100, WEI_ROUNDING_TOLERANCE, "expected eth should be ~+3% of deposit"
        );

        vm.prank(USER1);
        uint256 requestId = ctx.withdrawalQueue.requestWithdrawal(USER1, expectedStv, 0);
        // 4) Advance past min delay and ensure a fresh report after the request (required by WQ)
        _advancePastMinDelayAndRefreshReport(ctx, requestId);

        // 6) Node Operator finalizes one request
        vm.prank(NODE_OPERATOR);
        ctx.withdrawalQueue.finalize(1, address(0));

        // 7) USER1 claims and receives the increased amount
        uint256 userBalanceBefore = USER1.balance;
        vm.prank(USER1);
        ctx.withdrawalQueue.claimWithdrawal(USER1, requestId);

        assertApproxEqAbs(
            USER1.balance,
            userBalanceBefore + ((depositAmount * 103) / 100),
            WEI_ROUNDING_TOLERANCE,
            "user should receive ~deposit * 1.03 on claim"
        );
    }

    function test_finalize_reverts_after_loss_more_than_deposit() public {
        // Deploy pool system
        WrapperContext memory ctx = _deployStvPool(false, 0);

        // 1) USER1 deposits 0.01 ether (above MIN_WITHDRAWAL_VALUE)
        uint256 depositAmount = 0.01 ether;
        uint256 expectedStv = ctx.pool.previewDeposit(depositAmount);
        vm.prank(USER1);
        ctx.pool.depositETH{value: depositAmount}(USER1, address(0));
        assertEq(ctx.pool.balanceOf(USER1), expectedStv, "minted shares should match previewDeposit");
        assertEq(
            address(ctx.vault).balance, depositAmount + CONNECT_DEPOSIT, "vault balance should match deposit amount"
        );

        // 2) USER1 immediately requests withdrawal of all their shares
        vm.prank(USER1);
        ctx.withdrawalQueue.requestWithdrawal(USER1, expectedStv, 0);

        // Expected ETH to withdraw is locked at request time (equals initial deposit for StvPool)
        uint256 expectedEthAtRequest = ctx.pool.previewRedeem(expectedStv);
        assertEq(expectedEthAtRequest, depositAmount, "expected eth should match deposit amount at request time");

        // 4) Apply -1% report BEFORE finalization (vault value decreases)
        reportVaultValueChangeNoFees(ctx, 9900); // -1%

        // After the loss report, totalValue should be less than CONNECT_DEPOSIT
        assertLt(
            ctx.dashboard.totalValue(),
            CONNECT_DEPOSIT,
            "totalValue should be less than CONNECT_DEPOSIT after loss report"
        );

        // Finalization should revert due to insufficient ETH to cover the request
        vm.prank(NODE_OPERATOR);
        vm.expectRevert();
        ctx.withdrawalQueue.finalize(1, address(0));
    }

    function test_withdrawal_request_finalized_after_reward_and_loss_reports() public {
        // Deploy pool system
        WrapperContext memory ctx = _deployStvPool(false, 0);

        // Simulate a +3% vault value report before deposit
        reportVaultValueChangeNoFees(ctx, 10300); // +3%

        // 1) USER1 deposits 0.01 ether (above MIN_WITHDRAWAL_VALUE)
        uint256 depositAmount = 0.01 ether;
        uint256 expectedStv = ctx.pool.previewDeposit(depositAmount);
        vm.prank(USER1);
        ctx.pool.depositETH{value: depositAmount}(USER1, address(0));

        // 2) USER1 requests withdrawal of all their shares
        vm.prank(USER1);
        uint256 requestId = ctx.withdrawalQueue.requestWithdrawal(USER1, expectedStv, 0);

        // 3) Advance past min delay and ensure a fresh report after the request (required by WQ)
        _advancePastMinDelayAndRefreshReport(ctx, requestId);

        // 4) Simulate a -2% vault value report after the withdrawal request
        reportVaultValueChangeNoFees(ctx, 9800); // -2%

        // 6) Node Operator finalizes one request
        vm.prank(NODE_OPERATOR);
        ctx.withdrawalQueue.finalize(1, address(0));

        // 7) USER1 claims and receives the decreased amount
        uint256 userBalanceBefore = USER1.balance;
        vm.prank(USER1);
        ctx.withdrawalQueue.claimWithdrawal(USER1, requestId);

        assertApproxEqAbs(
            USER1.balance,
            userBalanceBefore + ((depositAmount * 98) / 100),
            WEI_ROUNDING_TOLERANCE,
            "user should receive ~deposit * 0.98 on claim"
        );
    }

    function test_partial_withdrawal_pro_rata_claim() public {
        // Deploy pool system
        WrapperContext memory ctx = _deployStvPool(false, 0);

        // 1) USER1 deposits 0.01 ether
        uint256 depositAmount = 0.01 ether;
        vm.prank(USER1);
        ctx.pool.depositETH{value: depositAmount}(USER1, address(0));

        // 2) USER1 creates two partial withdrawal requests that in total withdraw all shares
        uint256 userShares = ctx.pool.balanceOf(USER1);

        // First partial: half of user shares
        uint256 firstShares = userShares / 2;
        uint256 firstAssets = ctx.pool.previewRedeem(firstShares);
        vm.prank(USER1);
        uint256 requestId1 = ctx.withdrawalQueue.requestWithdrawal(USER1, firstShares, 0);

        // Second partial: the remaining shares
        uint256 remainingShares = ctx.pool.balanceOf(USER1);
        uint256 secondShares = remainingShares;
        uint256 secondAssets = ctx.pool.previewRedeem(secondShares);
        vm.prank(USER1);
        uint256 requestId2 = ctx.withdrawalQueue.requestWithdrawal(USER1, secondShares, 0);

        // 3) Advance past min delay and ensure fresh report
        _advancePastMinDelayAndRefreshReport(ctx, requestId2);

        // 4) Finalize both requests
        vm.prank(NODE_OPERATOR);
        uint256 finalized = ctx.withdrawalQueue.finalize(2, address(0));
        assertEq(finalized, 2, "should finalize both partial requests");

        // 5) Claim both and verify total equals sum of previews; user ends with zero shares
        uint256 userBalanceBefore = USER1.balance;
        vm.prank(USER1);
        ctx.withdrawalQueue.claimWithdrawal(USER1, requestId1);
        vm.prank(USER1);
        ctx.withdrawalQueue.claimWithdrawal(USER1, requestId2);

        assertApproxEqAbs(
            USER1.balance,
            userBalanceBefore + firstAssets + secondAssets,
            WEI_ROUNDING_TOLERANCE * 2,
            "total claimed should equal sum of both previewRedeem values"
        );
        assertEq(ctx.pool.balanceOf(USER1), 0, "USER1 should have no stv shares remaining");
    }

    function test_finalize_batch_stops_then_completes_when_funded() public {
        // Deploy pool system
        WrapperContext memory ctx = _deployStvPool(false, 0);

        // 1) USER1 deposits 0.01 ether
        uint256 depositAmount = 0.01 ether;
        vm.prank(USER1);
        ctx.pool.depositETH{value: depositAmount}(USER1, address(0));

        // 2) Create two split withdrawal requests
        uint256 userShares = ctx.pool.balanceOf(USER1);
        uint256 firstShares = userShares / 3; // ~33%
        uint256 secondShares = userShares / 2; // ~50%
        uint256 firstAssets = ctx.pool.previewRedeem(firstShares);
        uint256 secondAssets = ctx.pool.previewRedeem(secondShares);

        vm.startPrank(USER1);
        uint256 requestId1 = ctx.withdrawalQueue.requestWithdrawal(USER1, firstShares, 0);
        uint256 requestId2 = ctx.withdrawalQueue.requestWithdrawal(USER1, secondShares, 0);
        vm.stopPrank();

        // 3) Advance past min delay for both
        _advancePastMinDelayAndRefreshReport(ctx, requestId2);

        // 4) Move all withdrawable out to CL, then return only enough for the first via CL (insufficient for second)
        _depositToCL(ctx);
        _withdrawFromCL(ctx, firstAssets);

        vm.prank(NODE_OPERATOR);
        uint256 finalized = ctx.withdrawalQueue.finalize(2, address(0));
        assertEq(finalized, 1, "should finalize only the first request due to insufficient withdrawable");

        // 5) Claim first, second remains unfinalized
        uint256 userBalBefore = USER1.balance;
        vm.prank(USER1);
        ctx.withdrawalQueue.claimWithdrawal(USER1, requestId1);
        assertApproxEqAbs(USER1.balance, userBalBefore + firstAssets, WEI_ROUNDING_TOLERANCE);

        // 6) Return remaining via CL and finalize second
        _withdrawFromCL(ctx, secondAssets);

        vm.prank(NODE_OPERATOR);
        finalized = ctx.withdrawalQueue.finalize(1, address(0));
        assertEq(finalized, 1, "second request should now finalize after funding");

        // 7) Claim second
        uint256 userBalBefore2 = USER1.balance;
        vm.prank(USER1);
        ctx.withdrawalQueue.claimWithdrawal(USER1, requestId2);
        assertApproxEqAbs(USER1.balance, userBalBefore2 + secondAssets, WEI_ROUNDING_TOLERANCE);
    }

    function test_initial_state() public {
        WrapperContext memory ctx2 = _deployStvPool(false, 0);
        _checkInitialState(ctx2);
    }

    /**
     * @notice Test deploying a pool with custom configuration (allowlist enabled)
     */
    function test_custom_deployment_with_allowlist() public {
        // Deploy pool with allowlist enabled
        WrapperContext memory custom = _deployStvPool(true, 0);

        // Verify the custom pool was deployed with allowlist enabled
        assertTrue(custom.pool.ALLOW_LIST_ENABLED(), "Custom pool should have allowlist enabled");

        // Deploy another pool without allowlist to compare
        WrapperContext memory def = _deployStvPool(false, 0);

        // Verify the pools are different instances
        assertTrue(address(custom.pool) != address(def.pool), "Custom pool should be different from default");
        assertTrue(
            address(custom.withdrawalQueue) != address(def.withdrawalQueue),
            "Custom queue should be different from default"
        );
        assertFalse(def.pool.ALLOW_LIST_ENABLED(), "Default pool should not have allowlist enabled");
    }

    function test_claim_before_finalization_reverts_then_succeeds_after_finalize() public {
        WrapperContext memory ctx = _deployStvPool(false, 0);

        // Deposit and request
        uint256 depositAmount = 0.01 ether;
        vm.prank(USER1);
        ctx.pool.depositETH{value: depositAmount}(USER1, address(0));
        uint256 userShares = ctx.pool.balanceOf(USER1);
        vm.prank(USER1);
        uint256 requestId = ctx.withdrawalQueue.requestWithdrawal(USER1, userShares, 0);

        // Claim before finalize reverts
        vm.expectRevert("RequestNotFoundOrNotFinalized(1)");
        vm.prank(USER1);
        ctx.withdrawalQueue.claimWithdrawal(USER1, requestId);

        // Satisfy min delay and freshness
        _advancePastMinDelayAndRefreshReport(ctx, requestId);

        // Finalize
        vm.prank(NODE_OPERATOR);
        ctx.withdrawalQueue.finalize(1, address(0));

        // Claim succeeds
        uint256 before = USER1.balance;
        vm.prank(USER1);
        ctx.withdrawalQueue.claimWithdrawal(USER1, requestId);
        assertApproxEqAbs(USER1.balance, before + depositAmount, WEI_ROUNDING_TOLERANCE);
    }
}
