// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {Test} from "forge-std/Test.sol";
import {StvPool} from "src/StvPool.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";

contract TransferWithLiabilityTest is Test, SetupStvStETHPool {
    function setUp() public override {
        super.setUp();
        pool.depositETH{value: 20 ether}(address(this), address(0));
    }

    function test_TransferWithLiability_TransfersDebtAndStv() public {
        uint256 sharesToTransfer = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToTransfer);

        uint256 stvToTransfer = pool.balanceOf(address(this));

        vm.expectEmit(true, false, false, true);
        emit StvStETHPool.StethSharesBurned(address(this), sharesToTransfer);
        vm.expectEmit(true, false, false, true);
        emit StvStETHPool.StethSharesMinted(userAlice, sharesToTransfer);

        bool success = pool.transferWithLiability(userAlice, stvToTransfer, sharesToTransfer);
        assertTrue(success);

        assertEq(pool.mintedStethSharesOf(address(this)), 0);
        assertEq(pool.mintedStethSharesOf(userAlice), sharesToTransfer);
        assertEq(pool.balanceOf(address(this)), 0);
        assertEq(pool.balanceOf(userAlice), stvToTransfer);
    }

    function test_TransferWithLiability_RevertsWhenNoLiability() public {
        vm.expectRevert(StvStETHPool.ZeroArgument.selector);
        pool.transferWithLiability(userAlice, 100000, 0);
    }

    function test_TransferWithLiability_RevertsWhenStvInsufficient() public {
        uint256 sharesToTransfer = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToTransfer);

        uint256 minStv = pool.calcStvToLockForStethShares(sharesToTransfer);
        assertGt(minStv, 0);
        uint256 insufficientStv = minStv - 1;

        vm.expectRevert(StvStETHPool.InsufficientStv.selector);
        pool.transferWithLiability(userAlice, insufficientStv, sharesToTransfer);
    }

    function test_TransferWithLiability_RevertsWhenSharesExceedLiability() public {
        uint256 mintedShares = pool.remainingMintingCapacitySharesOf(address(this), 0) / 4;
        pool.mintStethShares(mintedShares);

        uint256 mintedRecorded = pool.mintedStethSharesOf(address(this));
        assertEq(mintedRecorded, mintedShares);

        uint256 stvBalance = pool.balanceOf(address(this));

        vm.expectRevert(StvStETHPool.InsufficientMintedShares.selector);
        pool.transferWithLiability(userAlice, stvBalance, mintedRecorded + 1);
    }

    function test_TransferWithLiability_RevertsWhenInsufficientStvButHasShares() public {
        uint256 sharesToTransfer = pool.remainingMintingCapacitySharesOf(address(this), 0) / 5;
        pool.mintStethShares(sharesToTransfer);

        vm.expectRevert(StvStETHPool.InsufficientStv.selector);
        pool.transferWithLiability(userAlice, 0, sharesToTransfer);
    }

    function test_TransferWithLiability_RevertsWhenToWithdrawalQueue() public {
        uint256 sharesToTransfer = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToTransfer);
        uint256 stvToTransfer = pool.balanceOf(address(this));

        vm.expectRevert(StvStETHPool.CannotTransferLiabilityToWithdrawalQueue.selector);
        pool.transferWithLiability(withdrawalQueue, stvToTransfer, sharesToTransfer);
    }

    function test_TransferWithLiability_RevertsWhenReportStale() public {
        uint256 sharesToTransfer = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToTransfer);
        uint256 stvToTransfer = pool.balanceOf(address(this));

        dashboard.VAULT_HUB().mock_setReportFreshness(dashboard.stakingVault(), false);

        vm.expectRevert(StvPool.VaultReportStale.selector);
        pool.transferWithLiability(userAlice, stvToTransfer, sharesToTransfer);
    }

    // transferFromWithLiabilityForWithdrawalQueue tests

    function test_TransferWithLiabilityForWQ_OnlyCallableByWQ() public {
        uint256 sharesToTransfer = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToTransfer);
        uint256 stvToTransfer = pool.balanceOf(address(this));

        vm.prank(userAlice);
        vm.expectRevert(StvPool.NotWithdrawalQueue.selector);
        pool.transferFromWithLiabilityForWithdrawalQueue(address(this), stvToTransfer, sharesToTransfer);
    }

    function test_TransferWithLiabilityForWQ_TransfersStv() public {
        uint256 sharesToTransfer = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToTransfer);
        uint256 stvBefore = pool.balanceOf(address(this));

        vm.prank(withdrawalQueue);
        pool.transferFromWithLiabilityForWithdrawalQueue(address(this), stvBefore, sharesToTransfer);

        assertEq(pool.balanceOf(address(this)), 0);
        assertEq(pool.balanceOf(withdrawalQueue), stvBefore);
    }

    function test_TransferWithLiabilityForWQ_TransfersLiability() public {
        uint256 sharesToTransfer = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToTransfer);
        uint256 stvToTransfer = pool.balanceOf(address(this));

        vm.prank(withdrawalQueue);
        pool.transferFromWithLiabilityForWithdrawalQueue(address(this), stvToTransfer, sharesToTransfer);

        assertEq(pool.mintedStethSharesOf(address(this)), 0);
        assertEq(pool.mintedStethSharesOf(withdrawalQueue), sharesToTransfer);
    }

    function test_TransferWithLiabilityForWQ_ChecksMinStv() public {
        uint256 sharesToTransfer = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToTransfer);
        uint256 minStv = pool.calcStvToLockForStethShares(sharesToTransfer);

        vm.prank(withdrawalQueue);
        pool.transferFromWithLiabilityForWithdrawalQueue(address(this), minStv, sharesToTransfer);

        assertEq(pool.balanceOf(withdrawalQueue), minStv);
    }

    function test_TransferWithLiabilityForWQ_RevertOn_InsufficientStv() public {
        uint256 sharesToTransfer = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToTransfer);
        uint256 minStv = pool.calcStvToLockForStethShares(sharesToTransfer);
        uint256 insufficientStv = minStv - 1;

        vm.prank(withdrawalQueue);
        vm.expectRevert(StvStETHPool.InsufficientStv.selector);
        pool.transferFromWithLiabilityForWithdrawalQueue(address(this), insufficientStv, sharesToTransfer);
    }

    // General transferWithLiability tests

    function test_TransferWithLiability_EmitsEvents() public {
        uint256 sharesToTransfer = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToTransfer);
        uint256 stvToTransfer = pool.balanceOf(address(this));

        vm.expectEmit(true, true, true, true);
        emit StvStETHPool.StethSharesBurned(address(this), sharesToTransfer);
        vm.expectEmit(true, true, true, true);
        emit StvStETHPool.StethSharesMinted(userAlice, sharesToTransfer);

        pool.transferWithLiability(userAlice, stvToTransfer, sharesToTransfer);
    }

    function test_TransferWithLiability_ExactMinStv_Success() public {
        uint256 sharesToTransfer = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToTransfer);
        uint256 minStv = pool.calcStvToLockForStethShares(sharesToTransfer);

        bool success = pool.transferWithLiability(userAlice, minStv, sharesToTransfer);

        assertTrue(success);
        assertEq(pool.balanceOf(userAlice), minStv);
        assertEq(pool.mintedStethSharesOf(userAlice), sharesToTransfer);
    }

    function test_TransferWithLiability_MoreThanMinStv_Success() public {
        uint256 sharesToTransfer = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToTransfer);
        uint256 minStv = pool.calcStvToLockForStethShares(sharesToTransfer);
        uint256 moreStv = minStv + 1 ether;

        bool success = pool.transferWithLiability(userAlice, moreStv, sharesToTransfer);

        assertTrue(success);
        assertEq(pool.balanceOf(userAlice), moreStv);
        assertEq(pool.mintedStethSharesOf(userAlice), sharesToTransfer);
    }
}
