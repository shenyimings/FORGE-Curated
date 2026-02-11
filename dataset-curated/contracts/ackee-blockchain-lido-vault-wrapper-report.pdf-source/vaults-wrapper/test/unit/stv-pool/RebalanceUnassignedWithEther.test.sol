// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {SetupStvPool} from "./SetupStvPool.sol";
import {StvPool} from "src/StvPool.sol";

contract RebalanceUnassignedWithEtherTest is Test, SetupStvPool {
    function test_DecreasesUnassignedLiability() public {
        uint256 liabilityToTransfer = 100;
        uint256 ethToRebalance = 15;

        dashboard.mock_increaseLiability(liabilityToTransfer);
        pool.rebalanceUnassignedLiabilityWithEther{value: ethToRebalance}();

        uint256 expectedLiabilityDecrease = steth.getSharesByPooledEth(ethToRebalance);
        assertEq(pool.totalUnassignedLiabilityShares(), liabilityToTransfer - expectedLiabilityDecrease);
    }

    function test_DecreasesTotalValue() public {
        uint256 totalAssetsBefore = pool.totalAssets();

        dashboard.mock_increaseLiability(100);
        pool.rebalanceUnassignedLiabilityWithEther{value: 50}();

        assertLt(pool.totalAssets(), totalAssetsBefore);
    }

    function test_RevertIfMoreThanUnassignedLiability() public {
        uint256 liabilityToTransfer = 100;
        dashboard.mock_increaseLiability(liabilityToTransfer);

        uint256 liabilityInEth = steth.getPooledEthBySharesRoundUp(liabilityToTransfer);

        vm.expectRevert(StvPool.NotEnoughToRebalance.selector);
        // 2 wei extra to account for rounding errors
        pool.rebalanceUnassignedLiabilityWithEther{value: liabilityInEth + 2}();
    }

    function test_RevertIfZeroShares() public {
        dashboard.mock_increaseLiability(100);

        vm.expectRevert(StvPool.NotEnoughToRebalance.selector);
        pool.rebalanceUnassignedLiabilityWithEther{value: 0}();
    }
}
