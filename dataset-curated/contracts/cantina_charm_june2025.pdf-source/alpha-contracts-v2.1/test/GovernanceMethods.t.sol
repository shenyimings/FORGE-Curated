// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {VaultTestUtils} from "./VaultTestUtils.sol";

contract GovernanceMethodsTest is Test, VaultTestUtils {
    function setUp() public {
        vm.createSelectFork(vm.envString("ALCHEMY_RPC"), 17073835);
        deployFactory();
    }

    function test_vaultGovernanceMethods() public {
        depositInFactory();

        // check setting full range weight
        vm.startPrank(other);
        vm.expectRevert("manager");
        vault.setWideRangeWeight(100);
        vm.stopPrank();

        vm.prank(owner);
        vault.setWideRangeWeight(100);
        vm.assertEq(vault.wideRangeWeight(), 100);
        vm.stopPrank();

        // check setting max total supply
        vm.startPrank(other);
        vm.expectRevert("manager");
        vault.setMaxTotalSupply(100);
        vm.stopPrank();

        vm.prank(owner);
        vault.setMaxTotalSupply(100);
        vm.assertEq(vault.maxTotalSupply(), 100);

        // check emergency burn
        int24 baseLower = vault.baseLower();
        int24 baseUpper = vault.baseUpper();

        vm.startPrank(other);
        vm.expectRevert("manager");
        vault.emergencyBurn(baseLower, baseUpper, 1e4);
        vm.stopPrank();

        {
            uint256 balance0 = IERC20(USDC).balanceOf(address(vault));
            uint256 balance1 = IERC20(WETH).balanceOf(address(vault));
            (uint256 total0, uint256 total1) = vault.getTotalAmounts();

            vm.prank(owner);
            vault.emergencyBurn(baseLower, baseUpper, 1e10);

            uint256 balance0After = IERC20(USDC).balanceOf(address(vault));
            uint256 balance1After = IERC20(WETH).balanceOf(address(vault));
            (uint256 total0After, uint256 total1After) = vault.getTotalAmounts();

            vm.assertGt(balance0After, balance0);
            vm.assertGt(balance1After, balance1);

            vm.assertApproxEqAbs(total0After, total0, 100, "total0After != total0");
            vm.assertApproxEqAbs(total1After, total1, 100, "total1After != total1");
        }

        // check setting manager
        vm.startPrank(other);
        vm.expectRevert("manager");
        vault.setManager(other);
        vm.stopPrank();

        vm.startPrank(owner);
        vault.setManager(other);
        vm.assertEq(vault.pendingManager(), other);

        // check setting manager fee
        vm.startPrank(other);
        vm.expectRevert("manager");
        vault.setManagerFee(100);
        vm.stopPrank();

        vm.startPrank(owner);
        vault.setManagerFee(100);
        vm.assertEq(vault.pendingManagerFee(), 100);
        vm.assertEq(vault.managerFee(), 0);
        vault.rebalance();
        vm.assertEq(vault.managerFee(), 100);

        // check accepting manager
        vm.startPrank(owner);
        vm.expectRevert("pendingManager");
        vault.acceptManager();
        vm.stopPrank();

        vm.prank(other);
        vault.acceptManager();
        vm.assertEq(vault.manager(), other);
    }

    function test_removeManager() public {
        depositInFactory();
        vm.startPrank(owner);
        vault.setManager(address(0));

        vm.assertEq(vault.manager(), owner);
        vm.assertEq(vault.pendingManager(), address(0));

        vault.acceptManager();
        vm.assertEq(vault.manager(), address(0));
        vm.assertEq(vault.pendingManager(), address(0));
    }

    function test_collectProtocolFees() public {
        depositInFactory();

        uint256 accruedProtocolFees0 = vault.accruedProtocolFees0();
        uint256 accruedProtocolFees1 = vault.accruedProtocolFees1();

        vm.assertEq(accruedProtocolFees0, 0, "accruedProtocolFees0 != 0");
        vm.assertEq(accruedProtocolFees1, 0, "accruedProtocolFees1 != 0");

        swapForwardAndBack(false);
        swapForwardAndBack(true);
        vault.rebalance();

        accruedProtocolFees0 = vault.accruedProtocolFees0();
        accruedProtocolFees1 = vault.accruedProtocolFees1();

        vm.assertEq(vault.accruedProtocolFees0(), 30150);
        vm.assertEq(vault.accruedProtocolFees1(), 14263705659729);

        // should revert if not called governance
        vm.startPrank(other);
        vm.expectRevert("governance");
        vault.collectProtocol(other);
        vm.stopPrank();

        //should claim governance fees
        {
            uint256 balanceUSDCBefore = IERC20(USDC).balanceOf(owner);
            uint256 balanceWETHBefore = IERC20(WETH).balanceOf(owner);

            vm.prank(owner);
            vault.collectProtocol(owner);

            uint256 balanceUSDCAfter = IERC20(USDC).balanceOf(owner);
            uint256 balanceWETHAfter = IERC20(WETH).balanceOf(owner);

            vm.assertEq(balanceUSDCAfter - balanceUSDCBefore, accruedProtocolFees0);
            vm.assertEq(balanceWETHAfter - balanceWETHBefore, accruedProtocolFees1);
        }
    }

    function test_collectManagerFees() public {
        depositInFactory();

        vm.startPrank(owner);
        vault.setManagerFee(40000);
        vault.setProtocolFee(10000);
        vault.rebalance();
        vm.stopPrank();

        uint256 accruedManagerFees0 = vault.accruedManagerFees0();
        uint256 accruedManagerFees1 = vault.accruedManagerFees1();

        vm.assertEq(accruedManagerFees0, 0);
        vm.assertEq(accruedManagerFees1, 0);

        swapForwardAndBack(false);
        swapForwardAndBack(true);
        vault.rebalance();

        accruedManagerFees0 = vault.accruedManagerFees0();
        accruedManagerFees1 = vault.accruedManagerFees1();

        vm.assertEq(vault.accruedManagerFees0(), 40200);
        vm.assertEq(vault.accruedManagerFees1(), 19018274212068);

        // manager fees set be 1/4 of protocol fees
        vm.assertApproxEqAbs(vault.accruedManagerFees0(), vault.accruedProtocolFees0() * 4, 100);
        vm.assertApproxEqAbs(vault.accruedManagerFees1(), vault.accruedProtocolFees1() * 4, 100);

        // should revert if not called governance
        vm.startPrank(other);
        vm.expectRevert("manager");
        vault.collectManager(other);
        vm.stopPrank();

        // should claim governance fee
        {
            uint256 balanceUSDCBefore = IERC20(USDC).balanceOf(owner);
            uint256 balanceWETHBefore = IERC20(WETH).balanceOf(owner);

            vm.prank(owner);
            vault.collectManager(owner);

            uint256 balanceUSDCAfter = IERC20(USDC).balanceOf(owner);
            uint256 balanceWETHAfter = IERC20(WETH).balanceOf(owner);

            vm.assertEq(balanceUSDCAfter - balanceUSDCBefore, accruedManagerFees0);
            vm.assertEq(balanceWETHAfter - balanceWETHBefore, accruedManagerFees1);
        }
    }

    function test_strategyGovernanceMethods() public {
        depositInFactory();

        // check setting limit threshold
        vm.startPrank(other);
        vm.expectRevert("manager");
        vault.setBaseThreshold(100);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert("threshold must be multiple of tickSpacing");
        vault.setLimitThreshold(1001);

        vm.expectRevert("threshold must be > 0");
        vault.setLimitThreshold(0);

        vault.setLimitThreshold(4800);
        vm.assertEq(vault.limitThreshold(), 4800);

        vm.stopPrank();

        // check setting max twap deviation
        vm.startPrank(other);
        vm.expectRevert("manager");
        vault.setMaxTwapDeviation(100);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert("maxTwapDeviation must be >= 0");
        vault.setMaxTwapDeviation(-1);

        vault.setMaxTwapDeviation(100);
        vm.assertEq(vault.maxTwapDeviation(), 100);
        vm.stopPrank();

        // check setting twap duration
        vm.startPrank(other);
        vm.expectRevert("manager");
        vault.setTwapDuration(100);
        vm.stopPrank();

        vm.prank(owner);
        vault.setTwapDuration(100);
        vm.assertEq(vault.twapDuration(), 100);
    }

    function test_factoryGovernanceMethods() public {
        depositInFactory();

        // check setting protocol fee on vault directly by governance
        vm.startPrank(other);
        vm.expectRevert("governance");
        vault.setProtocolFee(100);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert("protocolFee must be <= 250000");
        vault.setProtocolFee(250001);
        vm.stopPrank();

        vm.assertEq(vault.pendingProtocolFee(), 0);

        vm.prank(owner);
        vault.setProtocolFee(1);
        vm.assertEq(vault.pendingProtocolFee(), 1);

        // Check fee change is only reflected in vault after a rebalance
        vm.assertNotEq(vault.protocolFee(), 0);
        vault.rebalance();
        vm.assertEq(vault.protocolFee(), 1);

        // Check setting gov
        vm.startPrank(other);
        vm.expectRevert("governance");
        vaultFactory.setGovernance(other);
        vm.stopPrank();

        vm.prank(owner);
        vaultFactory.setGovernance(other);
        vm.assertEq(vaultFactory.pendingGovernance(), other);
        vm.assertEq(vaultFactory.governance(), owner);

        // check accepting gov
        vm.startPrank(owner);
        vm.expectRevert("pendingGovernance");
        vaultFactory.acceptGovernance();
        vm.stopPrank();

        vm.prank(other);
        vaultFactory.acceptGovernance();
        vm.assertEq(vaultFactory.governance(), other);

        // Check only new gov can collect protocol fees
        vm.startPrank(owner);
        vm.expectRevert("governance");
        vault.collectProtocol(owner);
        vm.stopPrank();

        vm.prank(other);
        vault.collectProtocol(other);
    }
}
