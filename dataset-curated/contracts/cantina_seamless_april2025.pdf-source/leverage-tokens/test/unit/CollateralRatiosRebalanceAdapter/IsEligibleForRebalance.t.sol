// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {CollateralRatiosRebalanceAdapterTest} from "./CollateralRatiosRebalanceAdapter.t.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";

contract IsEligibleForRebalanceTest is CollateralRatiosRebalanceAdapterTest {
    function test_isEligibleForRebalance_WhenCollateralRatioTooLow() public view {
        LeverageTokenState memory state =
            LeverageTokenState({collateralInDebtAsset: 100 ether, debt: 100 ether, equity: 0, collateralRatio: 1e18});

        bool isEligible = rebalanceAdapter.isEligibleForRebalance(leverageToken, state, address(this));
        assertTrue(isEligible);
    }

    function test_isEligibleForRebalance_WhenCollateralRatioTooHigh() public view {
        LeverageTokenState memory state = LeverageTokenState({
            collateralInDebtAsset: 300 ether,
            debt: 100 ether,
            equity: 200 ether,
            collateralRatio: 3e18
        });

        bool isEligible = rebalanceAdapter.isEligibleForRebalance(leverageToken, state, address(this));
        assertTrue(isEligible);
    }

    function test_isEligibleForRebalance_WhenCollateralRatioInRange() public view {
        LeverageTokenState memory state = LeverageTokenState({
            collateralInDebtAsset: 200 ether,
            debt: 100 ether,
            equity: 100 ether,
            collateralRatio: 2e18
        });

        bool isEligible = rebalanceAdapter.isEligibleForRebalance(leverageToken, state, address(this));
        assertFalse(isEligible);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_isEligibleForRebalance(uint256 collateralRatio) public view {
        uint256 minRatio = rebalanceAdapter.getLeverageTokenMinCollateralRatio();
        uint256 maxRatio = rebalanceAdapter.getLeverageTokenMaxCollateralRatio();

        LeverageTokenState memory state = LeverageTokenState({
            collateralInDebtAsset: 100 ether,
            debt: 100 ether,
            equity: 0,
            collateralRatio: collateralRatio
        });

        bool isEligible = rebalanceAdapter.isEligibleForRebalance(leverageToken, state, address(this));
        bool shouldBeEligible = collateralRatio < minRatio || collateralRatio > maxRatio;

        assertEq(isEligible, shouldBeEligible);
    }
}
