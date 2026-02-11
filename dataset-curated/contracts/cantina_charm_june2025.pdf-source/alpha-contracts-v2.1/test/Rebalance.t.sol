// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import {VaultTestUtils} from "./VaultTestUtils.sol";

contract RebalanceTest is Test, VaultTestUtils {
    function setUp() public {
        vm.createSelectFork(vm.envString("ALCHEMY_RPC"), 17073835);
        prepareTokens();
        deployManagerStore();
        deployFactory();
    }

    function test_shouldGainProfitAfterRebalance() public {
        depositInFactory();

        (uint256 total0, uint256 total1) = vault.getTotalAmounts();

        swapForwardAndBack(false);
        swapForwardAndBack(true);

        (uint256 total0After, uint256 total1After) = vault.getTotalAmounts();

        vm.assertApproxEqAbs(total0After, total0, 1e5);
        vm.assertApproxEqAbs(total1After, total1, 1e13);

        vm.prank(other);
        vault.deposit(10, 10, 1, 1, other);

        (uint256 totalAfterPoke0, uint256 totalAfterPoke1) = vault.getTotalAmounts();

        vm.assertGt(totalAfterPoke0 * 1_000_000 / total0, 1_000_001);
        vm.assertGt(totalAfterPoke1 * 1_000_000 / total1, 1_000_001);
    }

    function test_managerFeeIsAppliedOnlyToTheNextRebalance() public {
        depositInFactory();

        // init fees amount is empty
        vm.assertEq(vault.accruedManagerFees0(), 0);
        vm.assertEq(vault.accruedManagerFees1(), 0);
        vm.assertEq(vault.accruedProtocolFees0(), 0);
        vm.assertEq(vault.accruedProtocolFees1(), 0);

        swapForwardAndBack(false);
        swapForwardAndBack(true);
        vault.rebalance();

        // management fees not set yet but protocol fees were mined
        vm.assertEq(vault.accruedManagerFees0(), 0);
        vm.assertEq(vault.accruedManagerFees1(), 0);
        vm.assertEq(vault.accruedProtocolFees0(), 30150);
        vm.assertEq(vault.accruedProtocolFees1(), 14263705659729);

        // setting and checking management fee
        vm.assertEq(vault.pendingManagerFee(), 0);
        vm.assertEq(vault.managerFee(), 0);

        vm.prank(owner);
        vault.setManagerFee(12000);

        vm.assertEq(vault.pendingManagerFee(), 12000);
        vm.assertEq(vault.managerFee(), 0);

        swapForwardAndBack(false);
        swapForwardAndBack(true);
        vault.rebalance();

        //management fee is set as active after rebalance but will be appllied only on next rebalance
        vm.assertEq(vault.pendingManagerFee(), 12000);
        vm.assertEq(vault.managerFee(), 12000);

        vm.assertEq(vault.accruedManagerFees0(), 0);
        vm.assertEq(vault.accruedManagerFees1(), 0);

        vm.assertEq(vault.accruedProtocolFees0(), 60301);
        vm.assertEq(vault.accruedProtocolFees1(), 28528072482918);

        swapForwardAndBack(false);
        swapForwardAndBack(true);
        vault.rebalance();

        // management fee was set as active on previous rebalance ,so we should be able to see generated fees
        vm.assertEq(vault.accruedManagerFees0(), 12061);
        vm.assertEq(vault.accruedManagerFees1(), 5706011207141);
        vm.assertEq(vault.accruedProtocolFees0(), 90454);
        vm.assertEq(vault.accruedProtocolFees1(), 42793100500772);
    }

    function test_checkOnlyDelegatorAndManagerCanRebalance() public {
        depositInFactory();

        // anyone can rebalance
        vault.rebalance();
        vm.prank(owner);
        vault.rebalance();
        vm.prank(other);
        vault.rebalance();

        // only delegator and manager can rebalance
        vm.prank(owner);
        vault.setRebalanceDelegate(other);

        vm.expectRevert("rebalanceDelegate");
        vault.rebalance();

        vm.prank(owner);
        vault.rebalance();

        vm.prank(other);
        vault.rebalance();

        // only owner can rabanance
        vm.prank(owner);
        vault.setRebalanceDelegate(owner);

        vm.expectRevert("rebalanceDelegate");
        vault.rebalance();

        vm.startPrank(other);
        vm.expectRevert("rebalanceDelegate");
        vault.rebalance();
        vm.stopPrank();
    }

    function test_checkEnoughTimeHasPassed() public {
        depositInFactory();

        vm.prank(owner);
        vault.setPeriod(100);

        vm.expectRevert(bytes("PE"));
        vault.rebalance();

        vm.warp(block.timestamp + 1000);
        vault.rebalance();
    }

    function test_checkPriceHasMovedEnough() public {
        depositInFactory();

        vm.prank(owner);
        vault.setMinTickMove(1);

        vm.expectRevert(bytes("TM"));
        vault.rebalance();

        // should not fail if price moved enough
        swapToken(WETH, USDC, 200 ether, other);
        vault.rebalance();
    }

    function test_checkPriceNearTwap() public {
        depositInFactory();

        //shold rebalance if price is near twap
        vm.prank(owner);
        vault.setMaxTwapDeviation(10);

        swapForwardAndBack(false);
        vault.rebalance();

        // should not rebalance if price is not near twap
        swapToken(WETH, USDC, 200 ether, other);

        vm.expectRevert(bytes("TP"));
        vault.rebalance();

        // should rebalance if time passes
        vm.warp(block.timestamp + 1000);
        swapForwardAndBack(false);
        vault.rebalance();
    }

    function test_verifyWideBecomesLimit() public {
        depositInFactory();

        // Get pool parameters
        int24 tickSpacing = vault.tickSpacing();
        int24 maxTick = vault.maxTick();

        assertEq(vault.wideThreshold(), 72000);
        assertNotEq(vault.wideUpper(), maxTick);
        assertNotEq(vault.wideLower(), -maxTick);

        assertEq(maxTick, TickMath.MAX_TICK / tickSpacing * tickSpacing);

        vm.startPrank(owner);
        // Set larger than normal thresholds to test _verifyTick functionality
        vault.setWideThreshold(maxTick * 2);
        vault.rebalance();
        vm.stopPrank();

        assertEq(vault.wideUpper(), maxTick);
        assertEq(vault.wideLower(), -maxTick);
    }
}
