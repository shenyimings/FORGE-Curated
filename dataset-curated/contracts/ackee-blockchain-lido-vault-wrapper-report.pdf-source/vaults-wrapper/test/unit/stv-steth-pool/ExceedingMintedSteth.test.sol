// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {Test} from "forge-std/Test.sol";

contract ExceedingMintedStethTest is Test, SetupStvStETHPool {
    uint8 supplyDecimals = 27;
    uint256 initialMintedStethShares = 1 * 10 ** 18;

    function setUp() public override {
        super.setUp();

        pool.depositETH{value: 3 ether}(address(this), address(0));
        pool.mintStethShares(initialMintedStethShares);
    }

    function test_InitialState_CorrectMintedStethShares() public view {
        assertEq(pool.totalMintedStethShares(), initialMintedStethShares);
        assertEq(pool.totalExceedingMintedStethShares(), 0);
        assertEq(pool.totalExceedingMintedSteth(), 0);
    }

    function test_Rebalance_IncreaseExceedingMintedSteth() public {
        uint256 sharesToRebalance = initialMintedStethShares;

        dashboard.rebalanceVaultWithShares(sharesToRebalance);
        assertEq(pool.totalExceedingMintedStethShares(), sharesToRebalance);
    }

    function test_ExceedingShares_PartialRebalance() public {
        uint256 partialShares = initialMintedStethShares / 2;

        dashboard.rebalanceVaultWithShares(partialShares);
        assertEq(pool.totalExceedingMintedStethShares(), partialShares);
    }

    function test_ExceedingShares_MultipleRebalances() public {
        uint256 firstRebalance = initialMintedStethShares / 3;
        uint256 secondRebalance = initialMintedStethShares / 3;

        dashboard.rebalanceVaultWithShares(firstRebalance);
        assertEq(pool.totalExceedingMintedStethShares(), firstRebalance);

        dashboard.rebalanceVaultWithShares(secondRebalance);
        assertEq(pool.totalExceedingMintedStethShares(), firstRebalance + secondRebalance);
    }

    function test_ExceedingShares_NeverExceedsTotalMinted() public {
        uint256 totalMinted = pool.totalMintedStethShares();

        dashboard.rebalanceVaultWithShares(totalMinted);
        assertLe(pool.totalExceedingMintedStethShares(), totalMinted);
    }

    function test_ExceedingSteth_ZeroInitially() public view {
        assertEq(pool.totalExceedingMintedSteth(), 0);
    }

    function test_ExceedingSteth_ConvertsFromShares() public {
        uint256 sharesToRebalance = initialMintedStethShares;

        dashboard.rebalanceVaultWithShares(sharesToRebalance);

        uint256 expectedSteth = steth.getPooledEthByShares(sharesToRebalance);
        assertEq(pool.totalExceedingMintedSteth(), expectedSteth);
    }

    function test_ExceedingSteth_AffectsTotalAssets() public {
        uint256 assetsBefore = pool.totalAssets();

        uint256 sharesToRebalance = initialMintedStethShares;
        dashboard.rebalanceVaultWithShares(sharesToRebalance);

        // Exceeding steth compensates for reduced vault balance
        assertEq(pool.totalAssets(), assetsBefore);
    }

    function test_TotalAssets_IncreasesWithExceeding() public {
        // Mint additional shares to create difference
        pool.depositETH{value: 1 ether}(address(this), address(0));
        pool.mintStethShares(initialMintedStethShares / 2);

        uint256 assetsBefore = pool.totalAssets();

        dashboard.rebalanceVaultWithShares(initialMintedStethShares / 2);

        // After rebalance, exceeding compensates vault balance reduction
        assertEq(pool.totalAssets(), assetsBefore);
    }

    // Fuzz test for mutually exclusive exceeding vs unassigned liability

    function testFuzz_ExceedingVsUnassigned(uint128 assets, uint128 transferredLiability, uint128 sharesToRebalance)
        public
    {
        if (assets > 0) {
            vm.deal(address(this), uint256(assets));
            pool.depositETH{value: uint256(assets)}(address(this), address(0));
        }

        uint256 maxSharesToMintOnPool = pool.remainingMintingCapacitySharesOf(address(this), 0);
        pool.mintStethShares(maxSharesToMintOnPool);

        vm.assume(sharesToRebalance <= pool.totalLiabilityShares());

        dashboard.rebalanceVaultWithShares(sharesToRebalance);
        dashboard.mock_increaseLiability(transferredLiability);

        uint256 exceeding = pool.totalExceedingMintedStethShares();
        uint256 unassigned = pool.totalUnassignedLiabilityShares();

        // Only one can be non-zero at a time
        assertTrue(
            (exceeding > 0 && unassigned == 0) || (exceeding == 0 && unassigned > 0)
                || (exceeding == 0 && unassigned == 0)
        );
    }
}
