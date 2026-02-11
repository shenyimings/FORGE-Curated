// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvPool} from "./SetupStvPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";

contract ConversionTest is Test, SetupStvPool {
    function test_InitialDeployment_ExchangeRateIsOne() public view {
        uint256 assets = 1 ether;
        uint256 expectedStv = 10 ** pool.decimals();

        assertEq(pool.previewDeposit(assets), expectedStv);
        assertEq(pool.previewWithdraw(assets), expectedStv);
        assertEq(pool.previewRedeem(expectedStv), assets);
    }

    function test_PreviewDeposit_WhenAssetsZero() public {
        dashboard.mock_simulateRewards(-1 ether);

        assertEq(pool.totalAssets(), 0);
        assertGt(pool.totalSupply(), 0);

        // When totalAssets is zero, deposits yield zero STV
        assertEq(pool.previewDeposit(1 ether), 0);
    }

    function test_PreviewWithdraw_WhenAssetsZero() public {
        dashboard.mock_simulateRewards(-1 ether);

        assertEq(pool.totalAssets(), 0);
        assertGt(pool.totalSupply(), 0);

        assertEq(pool.previewWithdraw(1 ether), 0);
    }

    function test_PreviewRedeem_WhenAssetsZero() public {
        dashboard.mock_simulateRewards(-1 ether);

        assertEq(pool.totalAssets(), 0);
        assertGt(pool.totalSupply(), 0);

        assertEq(pool.previewRedeem(10 ** pool.decimals()), 0);
    }

    function test_Conversion_RateAboveOne() public {
        pool.depositETH{value: 1 ether}(address(this), address(0));

        dashboard.mock_simulateRewards(1 ether);

        assertEq(pool.totalAssets(), 3 ether);
        assertEq(pool.totalSupply(), 2 * 10 ** pool.decimals());

        uint256 assets = 1 ether;
        uint256 expectedStv = assets * (2 * 10 ** pool.decimals()) / 3 ether;
        assertEq(pool.previewDeposit(assets), expectedStv);

        uint256 stv = 10 ** pool.decimals();
        uint256 expectedAssets = stv * 3 ether / (2 * 10 ** pool.decimals());
        assertEq(pool.previewRedeem(stv), expectedAssets);
    }

    function test_Conversion_RateBelowOne() public {
        pool.depositETH{value: 2 ether}(address(this), address(0));

        dashboard.mock_simulateRewards(-1 ether);

        assertEq(pool.totalAssets(), 2 ether);
        assertEq(pool.totalSupply(), 3 * 10 ** pool.decimals());

        uint256 assets = 1 ether;
        uint256 expectedStv = assets * (3 * 10 ** pool.decimals()) / 2 ether;
        assertEq(pool.previewDeposit(assets), expectedStv);

        uint256 stv = 1 * 10 ** pool.decimals();
        uint256 expectedAssets = stv * 2 ether / (3 * 10 ** pool.decimals());
        assertEq(pool.previewRedeem(stv), expectedAssets);
    }

    function test_ExchangeRate_AfterMultipleDeposits() public {
        vm.prank(userAlice);
        pool.depositETH{value: 1 ether}(userAlice, address(0));

        vm.prank(userBob);
        pool.depositETH{value: 2 ether}(userBob, address(0));

        assertEq(pool.totalAssets(), 4 ether);
        assertEq(pool.totalSupply(), 4 * 10 ** 27);

        assertEq(pool.previewDeposit(1 ether), 1 * 10 ** 27);
        assertEq(pool.previewRedeem(1 * 10 ** 27), 1 ether);
    }

    function test_ExchangeRate_WithSmallRewards() public {
        pool.depositETH{value: 1 ether}(address(this), address(0));

        dashboard.mock_simulateRewards(1 wei);

        uint256 expectedStv = Math.mulDiv(1 ether, pool.totalSupply(), pool.totalAssets(), Math.Rounding.Floor);
        assertEq(pool.previewDeposit(1 ether), expectedStv);
    }

    function test_ExchangeRate_WithLargeRewards() public {
        pool.depositETH{value: 1 ether}(address(this), address(0));

        dashboard.mock_simulateRewards(100 ether);

        assertEq(pool.totalAssets(), 102 ether);
        assertEq(pool.totalSupply(), 2 * 10 ** 27);

        uint256 expectedStv = Math.mulDiv(1 ether, 2 * 10 ** 27, 102 ether, Math.Rounding.Floor);
        assertEq(pool.previewDeposit(1 ether), expectedStv);
    }

    // Fuzz tests for rounding behavior

    function testFuzz_DepositRounding_RoundsDownForUser(uint96 amount, int64 rewards, uint96 assets) public {
        vm.assume(amount > 0);
        vm.assume(int256(pool.totalAssets()) + rewards >= 0);

        vm.deal(address(this), amount);
        pool.depositETH{value: amount}(address(this), address(0));

        dashboard.mock_simulateRewards(rewards);

        uint256 stv = pool.previewDeposit(assets);
        uint256 actualAssets = stv * pool.totalAssets() / pool.totalSupply();
        assertLe(actualAssets, assets);
    }

    function testFuzz_WithdrawRounding_RoundsUpForProtocol(uint96 amount, int64 rewards, uint96 assets) public {
        vm.assume(amount > 0);
        vm.assume(int256(pool.totalAssets()) + rewards >= 0);

        vm.deal(address(this), amount);
        pool.depositETH{value: amount}(address(this), address(0));

        dashboard.mock_simulateRewards(rewards);

        uint256 stv = pool.previewWithdraw(assets);
        uint256 actualAssets = stv * pool.totalAssets() / pool.totalSupply();
        assertGe(actualAssets, assets);
    }

    function testFuzz_RedeemRounding_RoundsDownForUser(uint96 amount, int64 rewards, uint96 stv) public {
        vm.assume(amount > 0);
        vm.assume(int256(pool.totalAssets()) + rewards >= 0);

        vm.deal(address(this), amount);
        pool.depositETH{value: amount}(address(this), address(0));

        dashboard.mock_simulateRewards(rewards);

        uint256 assets = pool.previewRedeem(stv);
        uint256 actualStv = assets * pool.totalSupply() / pool.totalAssets();
        assertLe(actualStv, stv);
    }

    function testFuzz_DepositWithdraw_Consistency(uint96 amount, uint96 assets) public {
        vm.assume(amount > 0);

        vm.deal(address(this), amount);
        pool.depositETH{value: amount}(address(this), address(0));

        uint256 stvForDeposit = pool.previewDeposit(assets);
        uint256 stvForWithdraw = pool.previewWithdraw(assets);

        assertGe(stvForWithdraw, stvForDeposit);
    }
}
