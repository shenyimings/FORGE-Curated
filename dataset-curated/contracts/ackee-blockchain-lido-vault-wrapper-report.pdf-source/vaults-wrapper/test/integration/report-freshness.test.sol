// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {StvPool} from "src/StvPool.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {IVaultHub} from "src/interfaces/core/IVaultHub.sol";
import {StvStETHPoolHarness} from "test/utils/StvStETHPoolHarness.sol";

/**
 * @title Report Freshness Integration Tests
 * @notice Integration tests for StvPool (no minting, no strategy)
 */
contract ReportFreshnessTest is StvStETHPoolHarness {
    WrapperContext ctx;
    StvStETHPool pool;

    address requestFinalizer = NODE_OPERATOR;
    address lossSocializer;

    function setUp() public {
        _initializeCore();
        ctx = _deployStvStETHPool(false, 0, 25);
        pool = stvStETHPool(ctx);

        vm.deal(address(this), 10 ether);

        // Grant LOSS_SOCIALIZER_ROLE to a dedicated address
        lossSocializer = makeAddr("lossSocializer");
        bytes32 lossSocializerRole = pool.LOSS_SOCIALIZER_ROLE();
        vm.prank(address(ctx.timelock));
        pool.grantRole(lossSocializerRole, lossSocializer);

        // Enable loss socialization
        vm.prank(address(ctx.timelock));
        pool.setMaxLossSocializationBP(100_00); // 100%
    }

    function _waitForStaleOracleReport() internal {
        vm.warp(block.timestamp + 5 days);
        assertFalse(core.vaultHub().isReportFresh(address(ctx.vault)));
    }

    function test_deposit_requires_fresh_report() public {
        // Warp time to ensure oracle report stale
        _waitForStaleOracleReport();

        // Try to deposit. Should revert due to stale oracle report
        vm.expectRevert(StvPool.VaultReportStale.selector);
        pool.depositETH{value: 1 ether}(address(this), address(0));

        // Deliver oracle report
        reportVaultValueChangeNoFees(ctx, 100_00);

        // Deposit again. Should pass
        pool.depositETH{value: 1 ether}(address(this), address(0));
        uint256 stv = pool.balanceOf(address(this));
        assertGt(stv, 0);
    }

    function test_withdrawals_requires_fresh_report() public {
        // Deposit first
        pool.depositETH{value: 1 ether}(address(this), address(0));
        uint256 stv = pool.balanceOf(address(this));
        assertGt(stv, 0);

        // Warp time to ensure oracle report stale
        _waitForStaleOracleReport();

        // Try to withdraw. Should revert due to stale oracle report
        vm.expectRevert(StvPool.VaultReportStale.selector);
        ctx.withdrawalQueue.requestWithdrawal(address(this), stv, 0);

        // Deliver oracle report
        reportVaultValueChangeNoFees(ctx, 100_00);

        // Withdraw again. Should pass
        ctx.withdrawalQueue.requestWithdrawal(address(this), stv, 0);
        assertEq(ctx.withdrawalQueue.unfinalizedRequestsNumber(), 1);
    }

    function test_withdrawals_finalization_requires_fresh_report() public {
        // Deposit first
        pool.depositETH{value: 1 ether}(address(this), address(0));
        uint256 stv = pool.balanceOf(address(this));
        assertGt(stv, 0);

        // Request withdrawal
        ctx.withdrawalQueue.requestWithdrawal(address(this), stv, 0);
        assertEq(ctx.withdrawalQueue.unfinalizedRequestsNumber(), 1);

        // Warp time to ensure oracle report stale
        _waitForStaleOracleReport();

        // Try to finalize withdrawal. Should revert due to stale oracle report
        vm.prank(requestFinalizer);
        vm.expectRevert(WithdrawalQueue.VaultReportStale.selector);
        ctx.withdrawalQueue.finalize(1, address(this));

        // Deliver oracle report
        reportVaultValueChangeNoFees(ctx, 100_00);

        // Finalize withdrawal again. Should pass
        vm.prank(requestFinalizer);
        ctx.withdrawalQueue.finalize(1, address(this));
        assertEq(ctx.withdrawalQueue.unfinalizedRequestsNumber(), 0);
    }

    function test_minting_requires_fresh_report() public {
        // Deposit first
        pool.depositETH{value: 1 ether}(address(this), address(0));
        uint256 stv = pool.balanceOf(address(this));
        assertGt(stv, 0);

        // Warp time to ensure oracle report stale
        _waitForStaleOracleReport();

        // Calc steth shares to mint
        uint256 stethSharesToMint = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        assertGt(stethSharesToMint, 0);

        // Try to mint stETH. Should revert due to stale oracle report
        vm.expectRevert(abi.encodeWithSelector(IVaultHub.VaultReportStale.selector, address(ctx.vault)));
        pool.mintStethShares(stethSharesToMint);

        // Try to mint wstETH. Should revert due to stale oracle report
        vm.expectRevert(abi.encodeWithSelector(IVaultHub.VaultReportStale.selector, address(ctx.vault)));
        pool.mintWsteth(stethSharesToMint);

        // Deliver oracle report
        reportVaultValueChangeNoFees(ctx, 100_00);

        // Mint stETH again. Should pass
        pool.mintStethShares(stethSharesToMint);
        assertEq(pool.mintedStethSharesOf(address(this)), stethSharesToMint);

        // Mint wstETH again. Should pass
        pool.mintWsteth(stethSharesToMint);
        assertEq(pool.mintedStethSharesOf(address(this)), stethSharesToMint * 2);
    }

    function test_force_rebalance_requires_fresh_report() public {
        // Deposit first
        pool.depositETH{value: 1 ether}(address(this), address(0));
        uint256 stv = pool.balanceOf(address(this));
        assertGt(stv, 0);

        // Calc max steth shares to mint
        uint256 maxStethSharesToMint = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertGt(maxStethSharesToMint, 0);

        // Mint steth shares
        pool.mintStethShares(maxStethSharesToMint);

        // Deliver oracle report with losses
        reportVaultValueChangeNoFees(ctx, 80_00); // 20% loss

        // Check user is unhealthy
        assertFalse(pool.isHealthyOf(address(this)));

        // Check rebalance preview shows need to rebalance
        (uint256 stethSharesToRebalance, uint256 stvToRebalance, bool isUndercollateralized) =
            pool.previewForceRebalance(address(this));

        assertGt(stethSharesToRebalance, 0);
        assertGt(stvToRebalance, 0);

        // Should be collateralized (assets > liability) for permisionless rebalance
        assertFalse(isUndercollateralized);

        // Warp time to ensure oracle report stale
        _waitForStaleOracleReport();

        // Try to rebalance. Should revert due to stale oracle report
        vm.expectRevert(StvPool.VaultReportStale.selector);
        pool.forceRebalance(address(this));

        // Deliver fresh oracle report
        reportVaultValueChangeNoFees(ctx, 100_00);

        // Rebalance again. Should pass
        uint256 stvBurned = pool.forceRebalance(address(this));
        assertGt(stvBurned, 0);
    }

    function test_force_rebalance_with_socialization_requires_fresh_report() public {
        // Deposit first
        pool.depositETH{value: 1 ether}(address(this), address(0));
        uint256 stv = pool.balanceOf(address(this));
        assertGt(stv, 0);

        // Deposit to another user to have socialization effect
        vm.prank(USER1);
        pool.depositETH{value: 10 ether}(USER1, address(0));

        // Calc max steth shares to mint
        uint256 maxStethSharesToMint = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertGt(maxStethSharesToMint, 0);

        // Mint steth shares
        pool.mintStethShares(maxStethSharesToMint);

        // Deliver oracle report with huge losses
        reportVaultValueChangeNoFees(ctx, 40_00); // 60% loss

        // Check user is unhealthy
        assertFalse(pool.isHealthyOf(address(this)));

        // Check rebalance preview shows undercollateralization
        (uint256 stethSharesToRebalance, uint256 stvToRebalance, bool isUndercollateralized) =
            pool.previewForceRebalance(address(this));

        assertGt(stethSharesToRebalance, 0);
        assertGt(stvToRebalance, 0);

        // Should be uncollateralized (assets < liability)
        assertTrue(isUndercollateralized);

        // Warp time to ensure oracle report stale
        _waitForStaleOracleReport();

        // Try to rebalance. Should revert due to stale oracle report
        vm.prank(lossSocializer);
        vm.expectRevert(StvPool.VaultReportStale.selector);
        pool.forceRebalanceAndSocializeLoss(address(this));

        // Deliver fresh oracle report
        reportVaultValueChangeNoFees(ctx, 100_00);

        // Check other user balance before socialization
        uint256 user1AssetsBefore = pool.assetsOf(USER1);

        // Rebalance again. Should pass
        vm.prank(lossSocializer);
        uint256 stvBurned = pool.forceRebalanceAndSocializeLoss(address(this));
        assertGt(stvBurned, 0);

        // Check other user balance decreased due to socialization
        uint256 user1AssetsAfter = pool.assetsOf(USER1);
        assertLt(user1AssetsAfter, user1AssetsBefore);
    }
}
