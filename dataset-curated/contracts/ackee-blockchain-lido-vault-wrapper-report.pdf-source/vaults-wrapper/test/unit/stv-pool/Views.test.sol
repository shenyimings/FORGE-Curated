// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvPool} from "./SetupStvPool.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Test} from "forge-std/Test.sol";

contract ViewsTest is Test, SetupStvPool {
    using SafeCast for uint256;

    function setUp() public override {
        super.setUp();

        // Setup: deposit some ETH for users
        vm.prank(userAlice);
        pool.depositETH{value: 5 ether}(userAlice, address(0));

        vm.prank(userBob);
        pool.depositETH{value: 10 ether}(userBob, address(0));
    }

    // totalAssets and totalNominalAssets

    function test_TotalAssets_AfterDeposit_Increases() public {
        uint256 totalBefore = pool.totalAssets();

        pool.depositETH{value: 1 ether}(address(this), address(0));

        assertEq(pool.totalAssets(), totalBefore + 1 ether);
    }

    function test_TotalAssets_AfterRewards_Increases() public {
        uint256 totalBefore = pool.totalAssets();
        uint256 rewards = 2 ether;

        dashboard.mock_simulateRewards(rewards.toInt256());

        assertEq(pool.totalAssets(), totalBefore + rewards);
    }

    function test_TotalAssets_WithUnassignedLiability_Decreases() public {
        uint256 totalBefore = pool.totalAssets();
        uint256 liabilityShares = 1000;
        uint256 stethAmount = steth.getPooledEthBySharesRoundUp(liabilityShares);

        dashboard.mock_increaseLiability(liabilityShares);

        assertEq(pool.totalAssets(), totalBefore - stethAmount);
    }

    function test_NominalAssetsOf_DifferentUsers_ProportionalToBalance() public view {
        uint256 aliceBalance = pool.balanceOf(userAlice);
        uint256 bobBalance = pool.balanceOf(userBob);
        uint256 aliceAssets = pool.nominalAssetsOf(userAlice);
        uint256 bobAssets = pool.nominalAssetsOf(userBob);

        // Bob has 2x balance of Alice
        assertEq(bobBalance, aliceBalance * 2);
        // Bob should have 2x assets of Alice
        assertEq(bobAssets, aliceAssets * 2);
    }

    // assetsOf and nominalAssetsOf

    function test_AssetsOf_MatchesNominalAssets_WhenNoLiability() public view {
        // No liability added, so assets should match nominal assets
        assertEq(pool.assetsOf(userAlice), pool.nominalAssetsOf(userAlice));
        assertEq(pool.assetsOf(userBob), pool.nominalAssetsOf(userBob));
    }

    function test_AssetsOf_MultipleUsers_SumEqualsTotal() public view {
        uint256 poolAssets = pool.assetsOf(address(pool));
        uint256 aliceAssets = pool.assetsOf(userAlice);
        uint256 bobAssets = pool.assetsOf(userBob);
        uint256 totalAssets = pool.totalAssets();

        assertEq(poolAssets + aliceAssets + bobAssets, totalAssets);
    }

    // totalLiabilityShares

    function test_TotalLiabilityShares_InitiallyZero() public view {
        assertEq(pool.totalLiabilityShares(), 0);
    }

    function test_TotalLiabilityShares_AfterLiabilityIncrease() public {
        uint256 liabilityShares = 5000;

        dashboard.mock_increaseLiability(liabilityShares);

        assertEq(pool.totalLiabilityShares(), liabilityShares);
    }
}
