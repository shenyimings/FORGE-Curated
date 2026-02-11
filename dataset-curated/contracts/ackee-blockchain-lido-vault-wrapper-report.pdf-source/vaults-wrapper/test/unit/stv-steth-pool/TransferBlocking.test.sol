// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";

contract TransferBlockingTest is Test, SetupStvStETHPool {
    uint256 ethToDeposit = 10 ether;

    function setUp() public override {
        super.setUp();
        pool.depositETH{value: ethToDeposit}(address(this), address(0));
    }

    // Basic transfer tests without debt

    function test_Transfer_AllowedWithoutDebt() public {
        uint256 balance = pool.balanceOf(address(this));
        uint256 transferAmount = balance / 2;

        assertTrue(pool.transfer(userAlice, transferAmount));

        assertEq(pool.balanceOf(userAlice), transferAmount);
        assertEq(pool.balanceOf(address(this)), balance - transferAmount);
    }

    function test_Transfer_ZeroAmountAlwaysAllowed() public {
        // Zero transfer should work without any minting
        assertTrue(pool.transfer(userAlice, 0));
        assertEq(pool.balanceOf(userAlice), 0);

        // Zero transfer should also work with maximum debt
        uint256 mintCapacity = pool.remainingMintingCapacitySharesOf(address(this), 0);
        pool.mintStethShares(mintCapacity);

        assertTrue(pool.transfer(userAlice, 0));
        assertEq(pool.balanceOf(userAlice), 0);
    }

    // Test minting creates restrictions

    function test_MintingCreatesDebt() public {
        uint256 sharesToMint = pool.remainingMintingCapacitySharesOf(address(this), 0) / 4;
        pool.mintStethShares(sharesToMint);
        assertEq(pool.mintedStethSharesOf(address(this)), sharesToMint);
    }

    // Core transfer blocking tests

    function test_Transfer_BlockedWhenInsufficientBalanceAfterMinting() public {
        uint256 sharesToMint = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToMint);

        uint256 balance = pool.balanceOf(address(this));
        uint256 requiredLocked = pool.calcStvToLockForStethShares(sharesToMint);
        uint256 excessiveTransfer = balance - requiredLocked + 1;

        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        pool.transfer(userAlice, excessiveTransfer);
    }

    function test_Transfer_AllowedWhenWithinAvailableBalance() public {
        uint256 sharesToMint = pool.remainingMintingCapacitySharesOf(address(this), 0) / 4;
        pool.mintStethShares(sharesToMint);

        uint256 balance = pool.balanceOf(address(this));
        uint256 requiredLocked = pool.calcStvToLockForStethShares(sharesToMint);
        uint256 safeTransfer = balance - requiredLocked;

        assertTrue(pool.transfer(userAlice, safeTransfer));

        assertEq(pool.balanceOf(address(this)), requiredLocked);
    }

    // TransferFrom tests

    function test_TransferFrom_BlockedWhenInsufficientBalance() public {
        uint256 sharesToMint = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToMint);

        uint256 balance = pool.balanceOf(address(this));
        uint256 requiredLocked = pool.calcStvToLockForStethShares(sharesToMint);
        uint256 excessiveTransfer = balance - requiredLocked + 1;

        pool.approve(userAlice, excessiveTransfer);

        vm.prank(userAlice);
        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        pool.transferFrom(address(this), userBob, excessiveTransfer);
    }

    function test_TransferFrom_AllowedWhenWithinBalance() public {
        uint256 sharesToMint = pool.remainingMintingCapacitySharesOf(address(this), 0) / 2;
        pool.mintStethShares(sharesToMint);

        uint256 balance = pool.balanceOf(address(this));
        uint256 requiredLocked = pool.calcStvToLockForStethShares(sharesToMint);
        uint256 safeTransfer = balance - requiredLocked;

        pool.approve(userAlice, safeTransfer);

        vm.prank(userAlice);
        assertTrue(pool.transferFrom(address(this), userBob, safeTransfer));

        assertEq(pool.balanceOf(address(this)), requiredLocked);
    }

    // Different users with different debt levels

    function test_Transfer_IndependentRestrictionsForDifferentUsers() public {
        // Alice deposits and mints (creates debt)
        vm.prank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));

        uint256 aliceMintCapacity = pool.remainingMintingCapacitySharesOf(userAlice, 0);
        vm.prank(userAlice);
        pool.mintStethShares(aliceMintCapacity / 2);

        // Bob deposits but doesn't mint (no debt)
        vm.prank(userBob);
        pool.depositETH{value: ethToDeposit}(userBob, address(0));

        uint256 bobBalance = pool.balanceOf(userBob);

        // Bob should be able to transfer his entire balance (no restrictions)
        vm.prank(userBob);
        assertTrue(pool.transfer(userAlice, bobBalance));

        assertEq(pool.balanceOf(userBob), 0);

        // Alice should have restrictions due to her debt
        uint256 aliceBalance = pool.balanceOf(userAlice);
        uint256 aliceRequiredLocked = pool.calcStvToLockForStethShares(pool.mintedStethSharesOf(userAlice));

        uint256 maxSafeTransfer = aliceBalance - aliceRequiredLocked;
        uint256 excessiveTransfer = maxSafeTransfer + 1;

        vm.prank(userAlice);
        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        pool.transfer(userBob, excessiveTransfer);
    }

    // Receiving transfers should not be affected by debt

    function test_Transfer_ReceivingNotAffectedByDebt() public {
        // Alice has maximum debt
        vm.prank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));

        uint256 aliceMintCapacity = pool.remainingMintingCapacitySharesOf(userAlice, 0);
        vm.prank(userAlice);
        pool.mintStethShares(aliceMintCapacity);

        // This contract transfers to Alice (Alice is receiving, not sending)
        uint256 transferAmount = pool.balanceOf(address(this)) / 4;
        uint256 aliceBalanceBefore = pool.balanceOf(userAlice);

        assertTrue(pool.transfer(userAlice, transferAmount));

        // Alice should receive the transfer despite having debt
        assertEq(pool.balanceOf(userAlice), aliceBalanceBefore + transferAmount);
    }

    // Debt changes affect transfer restrictions

    function test_Transfer_RestrictionUpdatesAfterAdditionalMinting() public {
        uint256 mintCapacity = pool.remainingMintingCapacitySharesOf(address(this), 0);
        uint256 firstMint = mintCapacity / 4;

        // First mint
        pool.mintStethShares(firstMint);

        uint256 balance = pool.balanceOf(address(this));
        uint256 initialRequiredLocked = pool.calcStvToLockForStethShares(firstMint);
        uint256 initialMaxTransfer = balance > initialRequiredLocked ? balance - initialRequiredLocked : 0;

        // Mint more shares to increase debt
        uint256 additionalMint = mintCapacity / 4;
        pool.mintStethShares(additionalMint);

        // Now the previous safe transfer amount should be blocked due to increased debt
        vm.expectRevert(StvStETHPool.InsufficientReservedBalance.selector);
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        pool.transfer(userAlice, initialMaxTransfer);
    }

    function test_Transfer_RestrictionReleasesAfterBurning() public {
        uint256 mintCapacity = pool.remainingMintingCapacitySharesOf(address(this), 0);
        uint256 sharesToMint = mintCapacity / 2;

        pool.mintStethShares(sharesToMint);

        uint256 initialRequiredLocked = pool.calcStvToLockForStethShares(sharesToMint);

        // Burn half the shares
        vm.deal(address(this), 100 ether);
        steth.submit{value: 10 ether}(address(this));
        steth.approve(address(pool), type(uint256).max);

        uint256 sharesToBurn = sharesToMint / 2;
        pool.burnStethShares(sharesToBurn);

        uint256 newRequiredLocked = pool.calcStvToLockForStethShares(sharesToMint - sharesToBurn);

        // Should require less locked amount now
        assertLt(newRequiredLocked, initialRequiredLocked);

        // Should be able to transfer more now
        uint256 currentBalance = pool.balanceOf(address(this));
        uint256 newMaxTransfer = currentBalance - newRequiredLocked - 100;
        assertTrue(pool.transfer(userAlice, newMaxTransfer));
        // This should succeed without revert
    }

    // Edge cases

    function test_Transfer_CorrectCalculationOfRequiredLocked() public {
        uint256 mintCapacity = pool.remainingMintingCapacitySharesOf(address(this), 0);
        uint256 sharesToMint = mintCapacity / 3;

        pool.mintStethShares(sharesToMint);

        // Verify our helper function matches the contract's internal logic
        uint256 requiredLocked = pool.calcStvToLockForStethShares(sharesToMint);
        uint256 balance = pool.balanceOf(address(this));

        // Should be able to transfer exactly (balance - requiredLocked)
        uint256 maxTransfer = balance - requiredLocked;
        assertTrue(pool.transfer(userAlice, maxTransfer));

        // Should have exactly requiredLocked left
        assertEq(pool.balanceOf(address(this)), requiredLocked);
    }

    // Reserve ratio verification

    function test_Transfer_ReserveRatioImpactOnCalculations() public view {
        uint256 testShares = 1 ether;
        uint256 reserveRatio = pool.poolReserveRatioBP();
        uint256 totalBasisPoints = pool.TOTAL_BASIS_POINTS();

        // Verify reserve ratio is configured correctly
        assertGt(reserveRatio, 0);
        assertLt(reserveRatio, totalBasisPoints);

        // Verify calculation logic
        uint256 stethAmount = steth.getPooledEthBySharesRoundUp(testShares);
        uint256 expectedAssetsToLock =
            Math.mulDiv(stethAmount, totalBasisPoints, totalBasisPoints - reserveRatio, Math.Rounding.Ceil);
        uint256 calculatedAssetsToLock = pool.calcAssetsToLockForStethShares(testShares);

        assertEq(calculatedAssetsToLock, expectedAssetsToLock);
    }
}
