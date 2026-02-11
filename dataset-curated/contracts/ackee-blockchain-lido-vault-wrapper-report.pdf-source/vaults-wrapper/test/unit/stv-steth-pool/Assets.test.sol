// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {Test} from "forge-std/Test.sol";

contract AssetsTest is Test, SetupStvStETHPool {
    uint8 supplyDecimals = 27;

    function test_InitialState_CorrectAssets() public view {
        assertEq(pool.totalAssets(), INITIAL_DEPOSIT);
        assertEq(pool.totalNominalAssets(), INITIAL_DEPOSIT);

        assertEq(pool.nominalAssetsOf(address(pool)), INITIAL_DEPOSIT);
        assertEq(pool.assetsOf(address(pool)), INITIAL_DEPOSIT);
    }

    function test_Deposit_IncreasesAssets() public {
        uint256 ethToDeposit = 1 ether;
        uint256 assetsBefore = pool.totalAssets();

        vm.prank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));

        assertEq(pool.totalAssets(), assetsBefore + ethToDeposit);
    }

    function test_Deposit_IncreasesUserAssets() public {
        uint256 ethToDeposit = 1 ether;
        uint256 assetsBefore = pool.assetsOf(userAlice);

        vm.prank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));

        assertEq(pool.assetsOf(userAlice), assetsBefore + ethToDeposit);
    }

    function test_Rebalance_DoNotChangeUserAssets() public {
        pool.depositETH{value: 4 ether}(address(this), address(0));
        pool.mintStethShares(1 * 10 ** 18);

        uint256 assetsBefore = pool.assetsOf(address(this));

        dashboard.rebalanceVaultWithShares(1 * 10 ** 18);

        assertEq(pool.assetsOf(address(this)), assetsBefore);
        assertLt(pool.nominalAssetsOf(address(this)), assetsBefore);
    }
}
