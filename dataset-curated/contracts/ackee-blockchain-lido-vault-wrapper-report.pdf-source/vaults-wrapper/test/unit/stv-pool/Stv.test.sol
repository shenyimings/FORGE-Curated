// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvPool} from "./SetupStvPool.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Test} from "forge-std/Test.sol";

contract StvTest is Test, SetupStvPool {
    using SafeCast for uint256;

    uint8 supplyDecimals = 27;

    function test_InitialState_CorrectSupplyAndAssets() public view {
        assertEq(pool.totalAssets(), INITIAL_DEPOSIT);
        assertEq(pool.totalSupply(), 10 ** supplyDecimals);

        assertEq(pool.nominalAssetsOf(address(pool)), INITIAL_DEPOSIT);
        assertEq(pool.balanceOf(address(pool)), 10 ** supplyDecimals);
    }

    // deposit tests

    function test_Deposit_IncreasesTotalSupply() public {
        uint256 ethToDeposit = 1 ether;
        uint256 supplyBefore = pool.totalSupply();

        vm.prank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));

        assertEq(pool.totalSupply(), supplyBefore + 10 ** supplyDecimals);
    }

    function test_Deposit_IncreasesTotalAssets() public {
        uint256 ethToDeposit = 1 ether;
        uint256 assetsBefore = pool.totalAssets();

        vm.prank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));

        assertEq(pool.totalAssets(), assetsBefore + ethToDeposit);
    }

    function test_Deposit_IncreasesUserBalance() public {
        uint256 ethToDeposit = 1 ether;
        uint256 userBalanceBefore = pool.balanceOf(userAlice);

        vm.prank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));

        assertEq(pool.balanceOf(userAlice), userBalanceBefore + 10 ** supplyDecimals);
    }

    function test_Deposit_IncreasesUserAssets() public {
        uint256 ethToDeposit = 1 ether;

        vm.prank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));

        uint256 aliceBalanceE27 = pool.balanceOf(address(pool));

        assertEq(aliceBalanceE27, 10 ** supplyDecimals);
        assertEq(pool.previewRedeem(aliceBalanceE27), ethToDeposit);
    }

    // rewards

    function test_Rewards_IncreasesTotalAssets() public {
        uint256 rewards = 1 ether;
        uint256 totalAssetsBefore = pool.totalAssets();
        dashboard.mock_simulateRewards(rewards.toInt256());

        assertEq(pool.totalAssets(), totalAssetsBefore + rewards);
    }

    function test_Rewards_DistributedAmongUsers() public {
        pool.depositETH{value: 1 ether}(userAlice, address(0));
        pool.depositETH{value: 2 ether}(userBob, address(0));

        uint256 rewards = 333;
        dashboard.mock_simulateRewards(rewards.toInt256());

        assertEq(pool.nominalAssetsOf(address(pool)), 1 ether + (rewards / 4));
        assertEq(pool.nominalAssetsOf(userAlice), 1 ether + (rewards / 4));
        assertEq(pool.nominalAssetsOf(userBob), 2 ether + (rewards / 2));
    }
}
