// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvPool} from "./SetupStvPool.sol";
import {Test} from "forge-std/Test.sol";
import {StvPool} from "src/StvPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract UnassignedLiabilityTest is Test, SetupStvPool {
    function test_InitialState_UnassignedLiabilityIsZero() public view {
        assertEq(pool.totalUnassignedLiabilityShares(), 0);
    }

    // unassigned liability tests

    function test_TotalUnassignedLiabilityShares() public {
        uint256 liabilityShares = 100;
        dashboard.mock_increaseLiability(liabilityShares);
        assertEq(pool.totalUnassignedLiabilityShares(), liabilityShares);
    }

    function test_TotalUnassignedLiabilitySteth() public {
        uint256 liabilityShares = 1000;
        uint256 stethRoundedUp = steth.getPooledEthBySharesRoundUp(liabilityShares);
        dashboard.mock_increaseLiability(liabilityShares);
        assertEq(pool.totalUnassignedLiabilitySteth(), stethRoundedUp);
    }

    function test_UnassignedLiabilityDecreasesTotalAssets() public {
        uint256 totalAssetsBefore = pool.totalAssets();
        uint256 liabilityShares = 1000;
        uint256 stethRoundedUp = steth.getPooledEthBySharesRoundUp(liabilityShares);
        dashboard.mock_increaseLiability(liabilityShares);

        assertEq(pool.totalAssets(), totalAssetsBefore - stethRoundedUp);
    }

    function test_AssetsOf_DecreasesWithUnassignedLiability() public {
        vm.prank(userAlice);
        pool.depositETH{value: 5 ether}(userAlice, address(0));

        uint256 assetsBefore = pool.assetsOf(userAlice);
        assertGt(assetsBefore, 0);

        uint256 liabilityShares = steth.getSharesByPooledEth(pool.totalAssets() / 2);
        dashboard.mock_increaseLiability(liabilityShares);

        uint256 assetsAfter = pool.assetsOf(userAlice);
        assertLt(assetsAfter, assetsBefore);
    }

    function test_AssetsOf_MultipleUsers_DecreaseWithUnassignedLiability() public {
        vm.prank(userAlice);
        pool.depositETH{value: 3 ether}(userAlice, address(0));

        vm.prank(userBob);
        pool.depositETH{value: 6 ether}(userBob, address(0));

        uint256 aliceAssetsBefore = pool.assetsOf(userAlice);
        uint256 bobAssetsBefore = pool.assetsOf(userBob);

        uint256 liabilityShares = steth.getSharesByPooledEth(pool.totalAssets() / 3);
        dashboard.mock_increaseLiability(liabilityShares);

        assertLt(pool.assetsOf(userAlice), aliceAssetsBefore);
        assertLt(pool.assetsOf(userBob), bobAssetsBefore);
    }

    function test_AssetsOf_DecreasesProportionallyToUnassignedLiability() public {
        vm.prank(userAlice);
        pool.depositETH{value: 2 ether}(userAlice, address(0));

        vm.prank(userBob);
        pool.depositETH{value: 8 ether}(userBob, address(0));

        uint256 userBalance = pool.balanceOf(userAlice);
        uint256 totalSupply = pool.totalSupply();
        uint256 assetsBefore = pool.assetsOf(userAlice);

        uint256 unassignedEth = pool.totalAssets() / 4;
        uint256 liabilityShares = steth.getSharesByPooledEth(unassignedEth);
        uint256 unassignedEthRounded = steth.getPooledEthBySharesRoundUp(liabilityShares);
        dashboard.mock_increaseLiability(liabilityShares);

        uint256 expectedReduction =
            Math.mulDiv(unassignedEthRounded, userBalance, totalSupply, Math.Rounding.Floor);

        assertEq(pool.assetsOf(userAlice), assetsBefore - expectedReduction);
    }

    // unavailable user operations tests

    function test_RevertOnDeposits() public {
        dashboard.mock_increaseLiability(100);

        vm.prank(userAlice);
        vm.expectRevert(StvPool.UnassignedLiabilityOnVault.selector);
        pool.depositETH{value: 1 ether}(userAlice, address(0));
    }

    function test_RevertOnTransfers() public {
        vm.prank(userAlice);
        pool.depositETH{value: 1 ether}(userAlice, address(0));

        dashboard.mock_increaseLiability(100);

        vm.prank(userAlice);
        vm.expectRevert(StvPool.UnassignedLiabilityOnVault.selector);
        /// No return since it reverts
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        pool.transfer(userBob, 1);
    }

    // unavailable node operator operations tests

    function test_TODO_RevertsOnWithdrawalsFinalization() public {
        // TODO: implement blocking finalization of withdrawals
    }

    // available user operations tests

    function test_DoNotRevertOnApprove() public {
        vm.prank(userAlice);
        pool.depositETH{value: 1 ether}(userAlice, address(0));

        dashboard.mock_increaseLiability(100);

        vm.prank(userAlice);
        pool.approve(userBob, 1);
        assertEq(pool.allowance(userAlice, userBob), 1);
    }
}
