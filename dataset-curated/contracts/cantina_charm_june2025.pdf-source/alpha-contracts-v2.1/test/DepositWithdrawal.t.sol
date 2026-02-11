// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {VaultTestUtils} from "./VaultTestUtils.sol";

contract DepositWithdrawalTest is Test, VaultTestUtils {
    function setUp() public {
        vm.createSelectFork(vm.envString("ALCHEMY_RPC"), 17073835);
        prepareTokens();
        deployFactory();
    }

    function test_initialDeposit() public {
        depositInFactory();
        assertEq(vault.wideRangeWeight(), 0);

        vm.startPrank(owner);
        vault.setWideRangeWeight(50000);
        assertEq(vault.wideRangeWeight(), 50000);
        vault.rebalance();

        swapForwardAndBack(false);
        swapForwardAndBack(true);
        vault.rebalance();
    }

    function testFuzz_depositsShares(uint128 amount0Desired, uint128 amount1Desired) public {
        vm.assume(amount0Desired > 1e3 || amount1Desired > 1e3);
        vm.assume(amount0Desired < type(uint128).max - 1 && amount1Desired < type(uint128).max - 1);

        deal(WETH, initialDepositor, type(uint128).max);
        deal(USDC, initialDepositor, type(uint128).max);

        vm.startPrank(initialDepositor);

        IERC20(WETH).approve(address(vault), type(uint256).max);
        IERC20(USDC).approve(address(vault), type(uint256).max);

        uint256 balanceWETH = IERC20(WETH).balanceOf(initialDepositor);
        uint256 balanceUSDC = IERC20(USDC).balanceOf(initialDepositor);

        (uint256 shares,,) = vault.deposit(amount0Desired, amount1Desired, 0, 0, initialDepositor);

        assertGt(vault.balanceOf(initialDepositor), 0);
        assertEq(balanceUSDC - IERC20(USDC).balanceOf(initialDepositor), amount0Desired);
        assertEq(balanceWETH - IERC20(WETH).balanceOf(initialDepositor), amount1Desired);

        // now claim it back
        vault.withdraw(shares, 0, 0, initialDepositor);
    }

    function testFuzz_depositsShares_WithPriorSwap(
        uint64 firstDepositAmount0,
        uint64 firstDepositAmount1,
        uint64 amount0Desired,
        uint64 amount1Desired,
        uint64 swapAmount,
        bool swapDirection
    ) public {
        vm.assume(amount0Desired > 1e3 && amount1Desired > 1e3);
        vm.assume(firstDepositAmount0 > 1e3 && firstDepositAmount1 > 1e3);
        vm.assume(swapAmount > 1e3 && swapAmount < 1e18); // reasonable swap bound

        depositAndRebalance(initialDepositor, firstDepositAmount1, firstDepositAmount0);

        // Perform random swap to change the pool price
        if (swapDirection) {
            swapToken(USDC, WETH, swapAmount, owner);
        } else {
            swapToken(WETH, USDC, swapAmount, owner);
        }

        vm.warp(block.timestamp + 100);

        // Attempt deposit after price change
        uint256 shares = depositAndRebalance(initialDepositor, amount0Desired, amount1Desired);

        // now claim it back
        vm.startPrank(initialDepositor);
        vault.withdraw(shares, 0, 0, initialDepositor);

        vm.stopPrank();
    }

    function test_depositChecks() public {
        vm.startPrank(owner);
        vm.expectRevert(bytes("amount0Desired or amount1Desired"));
        vault.deposit(0, 0, 0, 0, owner);

        vm.expectRevert(bytes("to"));
        vault.deposit(1e8, 1e8, 0, 0, address(0));

        vm.expectRevert(bytes("to"));
        vault.deposit(1e8, 1e8, 0, 0, address(vault));

        vm.expectRevert(bytes("amount0Min"));
        vault.deposit(1e8, 0, 2e8, 0, owner);

        vm.expectRevert(bytes("amount1Min"));
        vault.deposit(0, 1e8, 0, 2e8, owner);

        vm.expectRevert(bytes("maxTotalSupply"));
        vault.deposit(1e8, type(uint128).max, 0, 0, owner);
    }

    function test_depositAndWithdraw() public {
        depositInFactory();

        uint256 vaultTokenBalance = vault.balanceOf(initialDepositor);
        uint256 beforeTotalSupply = vault.totalSupply();

        uint256 wethUserBalanceBefore = IERC20(WETH).balanceOf(initialDepositor);
        uint256 usdcUserBalanceBefore = IERC20(USDC).balanceOf(initialDepositor);

        (uint256 total0, uint256 total1) = vault.getTotalAmounts();

        vm.startPrank(initialDepositor);
        vault.withdraw(vaultTokenBalance, 0, 0, initialDepositor);
        vm.stopPrank();

        vm.assertEq(vault.balanceOf(initialDepositor), 0);
        vm.assertEq(vault.totalSupply(), 1000);

        vm.assertApproxEqAbs(
            IERC20(USDC).balanceOf(initialDepositor),
            total0 * (beforeTotalSupply - 1e3) / beforeTotalSupply + usdcUserBalanceBefore,
            1e3
        );
        vm.assertApproxEqAbs(
            IERC20(WETH).balanceOf(initialDepositor),
            total1 * (beforeTotalSupply - 1e3) / beforeTotalSupply + wethUserBalanceBefore,
            1e3
        );
    }

    function test_withdrawChecks() public {
        depositInFactory();
        vm.startPrank(initialDepositor);

        vm.expectRevert(bytes("shares"));
        vault.withdraw(0, 0, 0, initialDepositor);

        vm.expectRevert(bytes("amount0Min"));
        vault.withdraw(1e8, 1e10, 0, initialDepositor);

        vm.expectRevert(bytes("amount1Min"));
        vault.withdraw(1e8, 0, 1e10, initialDepositor);

        vm.expectRevert(bytes("to"));
        vault.withdraw(1e8, 1e8, 0, address(0));

        vm.expectRevert(bytes("to"));
        vault.withdraw(1e8, 1e8, 0, address(vault));
    }

    function test_depositDelegate() public {
        depositInFactory();

        address delegate = address(0x123);
        address nonDelegate = address(0x456);

        // Give both accounts some tokens
        deal(WETH, delegate, 1e18);
        deal(USDC, delegate, 1e8);
        deal(WETH, nonDelegate, 1e18);
        deal(USDC, nonDelegate, 1e8);

        // Set deposit delegate
        vm.startPrank(owner);
        vault.setDepositDelegate(delegate);
        vm.stopPrank();

        // Try to deposit from non-delegate address - should revert
        vm.startPrank(nonDelegate);
        IERC20(WETH).approve(address(vault), type(uint256).max);
        IERC20(USDC).approve(address(vault), type(uint256).max);

        vm.expectRevert(bytes("depositDelegate"));
        vault.deposit(1e6, 1e15, 0, 0, nonDelegate);
        vm.stopPrank();

        // Try to deposit from delegate address - should succeed
        vm.startPrank(delegate);
        IERC20(WETH).approve(address(vault), type(uint256).max);
        IERC20(USDC).approve(address(vault), type(uint256).max);

        (uint256 shares,,) = vault.deposit(1e6, 1e15, 0, 0, delegate);
        assertGt(shares, 0);
        assertGt(vault.balanceOf(delegate), 0);
        vm.stopPrank();

        // Clear deposit delegate and verify anyone can deposit again
        vm.startPrank(owner);
        vault.setDepositDelegate(address(0));
        vm.stopPrank();

        vm.startPrank(nonDelegate);
        (uint256 shares2,,) = vault.deposit(1e6, 1e15, 0, 0, nonDelegate);
        assertGt(shares2, 0);
        assertGt(vault.balanceOf(nonDelegate), 0);
    }
}
