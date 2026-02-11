// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {ExternalAction} from "src/types/DataTypes.sol";
import {PreviewActionTest} from "../LeverageManager/PreviewAction.t.sol";

contract ComputeCollateralAndDebtForActionTest is PreviewActionTest {
    function test_computeCollateralAndDebtForAction_Deposit() public {
        uint256 equityInCollateralAsset = 80 ether;
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 20 ether, sharesTotalSupply: 80 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        (uint256 computedCollateral, uint256 computedDebt) = leverageManager.exposed_computeCollateralAndDebtForAction(
            leverageToken, equityInCollateralAsset, ExternalAction.Deposit
        );

        assertEq(computedCollateral, 100 ether);
        assertEq(computedDebt, 20 ether);
    }

    function test_computeCollateralAndDebtForAction_Withdraw() public {
        uint256 equityInCollateralAsset = 80 ether;
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 20 ether, sharesTotalSupply: 80 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        (uint256 computedCollateral, uint256 computedDebt) = leverageManager.exposed_computeCollateralAndDebtForAction(
            leverageToken, equityInCollateralAsset, ExternalAction.Withdraw
        );

        assertEq(computedCollateral, 100 ether);
        assertEq(computedDebt, 20 ether);
    }

    function test_computeCollateralAndDebtForAction_Deposit_TotalSupplyZero() public {
        uint256 equityInCollateralAsset = 100 ether;
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 20 ether, sharesTotalSupply: 0 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        (uint256 computedCollateral, uint256 computedDebt) = leverageManager.exposed_computeCollateralAndDebtForAction(
            leverageToken, equityInCollateralAsset, ExternalAction.Deposit
        );

        // Follows 2x target ratio, not the current ratio
        assertEq(computedCollateral, 200 ether);
        assertEq(computedDebt, 100 ether);
    }

    function test_computeCollateralAndDebtForAction_Withdraw_TotalSupplyZero() public {
        uint256 equityInCollateralAsset = 20 ether;
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 20 ether, sharesTotalSupply: 0 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        (uint256 computedCollateral, uint256 computedDebt) = leverageManager.exposed_computeCollateralAndDebtForAction(
            leverageToken, equityInCollateralAsset, ExternalAction.Withdraw
        );

        // Follows 2x target ratio, not the current ratio
        assertEq(computedCollateral, 40 ether);
        assertEq(computedDebt, 20 ether);
    }

    function test_computeCollateralAndDebtForAction_Deposit_DebtZero() public {
        uint256 equityInCollateralAsset = 100 ether;
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 0 ether, sharesTotalSupply: 20 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        (uint256 computedCollateral, uint256 computedDebt) = leverageManager.exposed_computeCollateralAndDebtForAction(
            leverageToken, equityInCollateralAsset, ExternalAction.Deposit
        );

        assertEq(computedCollateral, 200 ether);
        assertEq(computedDebt, 100 ether);
    }
}
