// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PreLiquidationRebalanceAdapterTest} from "./PreLiquidationRebalanceAdapter.t.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";

contract IsStateAfterRebalanceValidTest is PreLiquidationRebalanceAdapterTest {
    function test_isStateAfterRebalanceValid_ValidState() public {
        // Mock liquidation penalty to 5% and equity 97.6
        _mockLiquidationPenaltyEquityAndDebt(0.05e18, 97.5e18, 0);

        // Max equity loss here should be 2.5%
        LeverageTokenState memory stateBefore =
            LeverageTokenState({collateralRatio: 0, collateralInDebtAsset: 0, debt: 100e18, equity: 100e18});

        assertEq(adapter.isStateAfterRebalanceValid(leverageToken, stateBefore), true);
    }

    function testFuzz_isStateAfterRebalanceValid_PreviousStateNotBelowThreshold(uint256 collateralRatio) public view {
        collateralRatio = bound(collateralRatio, 1.1e18 + 1, type(uint256).max);

        LeverageTokenState memory stateBefore =
            LeverageTokenState({collateralRatio: collateralRatio, collateralInDebtAsset: 0, debt: 0, equity: 0});

        assertEq(adapter.isStateAfterRebalanceValid(leverageToken, stateBefore), true);
    }

    function test_isStateAfterRebalanceValid_InvalidState() public {
        // Mock liquidation penalty to 5% and equity to 97.5 - 1wei
        _mockLiquidationPenaltyEquityAndDebt(0.05e18, 97.5e18 - 1, 0);

        LeverageTokenState memory stateBefore =
            LeverageTokenState({collateralRatio: 0, collateralInDebtAsset: 0, debt: 100e18, equity: 100e18});

        assertEq(adapter.isStateAfterRebalanceValid(leverageToken, stateBefore), false);
    }
}
