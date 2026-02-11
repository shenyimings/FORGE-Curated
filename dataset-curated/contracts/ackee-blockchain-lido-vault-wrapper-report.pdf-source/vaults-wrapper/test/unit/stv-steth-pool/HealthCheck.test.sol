// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Test} from "forge-std/Test.sol";

contract HealthCheckTest is Test, SetupStvStETHPool {
    using SafeCast for uint256;

    uint256 ethToDeposit = 10 ether;

    function setUp() public override {
        super.setUp();
        pool.depositETH{value: ethToDeposit}(address(this), address(0));
    }

    // isHealthyOf tests

    function test_IsHealthy_TrueWithNoMinting() public view {
        assertEq(pool.mintedStethSharesOf(address(this)), 0);
        assertTrue(pool.isHealthyOf(address(this)));
    }

    function test_IsHealthy_TrueWithinThreshold() public {
        // Mint some shares but not enough to breach threshold
        uint256 capacity = pool.remainingMintingCapacitySharesOf(address(this), 0);
        uint256 sharesToMint = capacity / 2;

        pool.mintStethShares(sharesToMint);

        assertTrue(pool.isHealthyOf(address(this)));
    }

    function test_IsHealthy_FalseWhenThresholdBreached() public {
        // Mint max capacity
        uint256 capacity = pool.remainingMintingCapacitySharesOf(address(this), 0);
        pool.mintStethShares(capacity);

        // Simulate loss to breach threshold
        uint256 lossToBreachThreshold = _calcLossToBreachThreshold(address(this));
        dashboard.mock_simulateRewards(-1 * lossToBreachThreshold.toInt256());

        assertFalse(pool.isHealthyOf(address(this)));
    }

    function test_IsHealthy_AfterRewards_Improves() public {
        // Mint max capacity
        uint256 capacity = pool.remainingMintingCapacitySharesOf(address(this), 0);
        pool.mintStethShares(capacity);

        // Simulate loss to breach threshold
        uint256 lossToBreachThreshold = _calcLossToBreachThreshold(address(this));
        dashboard.mock_simulateRewards(-lossToBreachThreshold.toInt256());
        assertFalse(pool.isHealthyOf(address(this)));

        // New rewards restore health
        dashboard.mock_simulateRewards(lossToBreachThreshold.toInt256());

        assertTrue(pool.isHealthyOf(address(this)));
    }

    function test_IsHealthy_EdgeCase_ExactlyAtThreshold() public {
        // Mint max capacity
        uint256 capacity = pool.remainingMintingCapacitySharesOf(address(this), 0);
        pool.mintStethShares(capacity);

        // Simulate loss exactly at threshold (just before breach)
        uint256 lossToBreachThreshold = _calcLossToBreachThreshold(address(this));
        dashboard.mock_simulateRewards(-(lossToBreachThreshold - 1).toInt256());

        assertTrue(pool.isHealthyOf(address(this)));

        // One more wei of loss breaches
        dashboard.mock_simulateRewards(-1);

        assertFalse(pool.isHealthyOf(address(this)));
    }

    // Helper functions

    function _calcLossToBreachThreshold(address _account) internal view returns (uint256 lossToBreachThreshold) {
        uint256 mintedSteth = steth.getPooledEthByShares(pool.mintedStethSharesOf(_account));
        uint256 assets = pool.assetsOf(_account);
        uint256 threshold = pool.poolForcedRebalanceThresholdBP();

        // liability / (assets - x) = (1 - threshold)
        // x = assets - liability / (1 - threshold)
        lossToBreachThreshold =
            assets - (mintedSteth * pool.TOTAL_BASIS_POINTS()) / (pool.TOTAL_BASIS_POINTS() - threshold);

        // scale loss to user's share of the pool
        lossToBreachThreshold = (lossToBreachThreshold * pool.totalAssets()) / assets;
    }
}
