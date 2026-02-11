// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {PreLiquidationRebalanceAdapterTest} from "./PreLiquidationRebalanceAdapter.t.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";

contract IsEligibleForRebalanceTest is PreLiquidationRebalanceAdapterTest {
    function test_isEligibleForRebalance_CollateralRatioAboveThreshold() public view {
        LeverageTokenState memory state =
            LeverageTokenState({collateralRatio: 1.14e18, collateralInDebtAsset: 0, debt: 0, equity: 0});

        bool isEligible = adapter.isEligibleForRebalance(leverageToken, state, address(0));

        assertEq(isEligible, false);
    }

    function test_isEligibleForRebalance_CollateralRatioBelowThreshold() public view {
        LeverageTokenState memory state =
            LeverageTokenState({collateralRatio: 1.3e8 - 1, collateralInDebtAsset: 0, debt: 0, equity: 0});

        bool isEligible = adapter.isEligibleForRebalance(leverageToken, state, address(0));

        assertEq(isEligible, true);
    }
}
