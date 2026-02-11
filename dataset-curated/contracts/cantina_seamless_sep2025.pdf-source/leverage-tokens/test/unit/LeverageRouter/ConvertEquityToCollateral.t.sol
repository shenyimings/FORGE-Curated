// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {LeverageTokenState} from "src/types/DataTypes.sol";
import {LeverageRouterTest} from "./LeverageRouter.t.sol";
import {MockLeverageManager} from "../mock/MockLeverageManager.sol";

contract ConvertEquityToCollateralTest is LeverageRouterTest {
    function test_convertEquityToCollatereal_ZeroCollateralZeroDebt() public {
        uint256 initialCollateralRatio = 1.5e18; // 1.5 CR, 3x leverage
        uint256 equityInCollateralAsset = 1 ether;

        lendingAdapter.mockCollateral(0);
        lendingAdapter.mockDebt(0);
        leverageManager.setLeverageTokenInitialCollateralRatio(leverageToken, initialCollateralRatio);

        uint256 expectedCollateral = 3e18; // 3x leverage

        assertEq(leverageRouter.convertEquityToCollateral(leverageToken, equityInCollateralAsset), expectedCollateral);
    }

    function testFuzz_convertEquityToCollateral_ZeroCollateralZeroDebt(
        uint256 equityInCollateralAsset,
        uint256 initialCollateralRatio
    ) public {
        initialCollateralRatio = bound(initialCollateralRatio, leverageManager.BASE_RATIO() + 1, type(uint256).max);
        equityInCollateralAsset = bound(equityInCollateralAsset, 0, type(uint256).max / initialCollateralRatio);

        lendingAdapter.mockCollateral(0);
        lendingAdapter.mockDebt(0);
        leverageManager.setLeverageTokenInitialCollateralRatio(leverageToken, initialCollateralRatio);

        uint256 expectedCollateral = Math.mulDiv(
            equityInCollateralAsset,
            initialCollateralRatio,
            initialCollateralRatio - leverageManager.BASE_RATIO(),
            Math.Rounding.Ceil
        );
        assertEq(leverageRouter.convertEquityToCollateral(leverageToken, equityInCollateralAsset), expectedCollateral);
    }

    function testFuzz_convertEquityToCollateral_NonZeroCollateralOrNonZeroDebt_MaxCollateralRatio(
        uint256 equityInCollateralAsset,
        uint256 collateral
    ) public {
        collateral = bound(collateral, 1, type(uint256).max);

        lendingAdapter.mockCollateral(collateral);

        // Only the collateral ratio returned by LeverageManager.getLeverageTokenState() is relevant for this test
        leverageManager.setLeverageTokenState(
            leverageToken,
            LeverageTokenState({collateralRatio: type(uint256).max, debt: 0, equity: 0, collateralInDebtAsset: 0})
        );

        assertEq(
            leverageRouter.convertEquityToCollateral(leverageToken, equityInCollateralAsset), equityInCollateralAsset
        );
    }

    function test_convertEquityToCollateral_NonZeroCollateralOrNonZeroDebt_NonMaxCollateralRatio() public {
        uint256 collateral = 1.5 ether;
        uint256 debt = 1 ether;
        uint256 collateralRatio = 1.5e18; // 1.5 CR, 3x leverage
        uint256 equityInCollateralAsset = 1 ether;

        lendingAdapter.mockCollateral(collateral);
        lendingAdapter.mockDebt(debt);

        leverageManager.setLeverageTokenState(
            leverageToken,
            LeverageTokenState({
                collateralRatio: collateralRatio,
                debt: debt,
                equity: 0, // Doesnt matter for this test
                collateralInDebtAsset: collateral
            })
        );

        uint256 expectedCollateral = 3 * equityInCollateralAsset; // 3x leverage

        assertEq(leverageRouter.convertEquityToCollateral(leverageToken, equityInCollateralAsset), expectedCollateral);

        // Set debt to 0
        leverageManager.setLeverageTokenState(
            leverageToken,
            LeverageTokenState({
                collateralRatio: collateralRatio,
                debt: 0,
                equity: 0, // Doesnt matter for this test
                collateralInDebtAsset: collateral
            })
        );
        assertEq(leverageRouter.convertEquityToCollateral(leverageToken, equityInCollateralAsset), expectedCollateral);

        // Set collateral to 0
        leverageManager.setLeverageTokenState(
            leverageToken,
            LeverageTokenState({
                collateralRatio: collateralRatio,
                debt: debt,
                equity: 0, // Doesnt matter for this test
                collateralInDebtAsset: collateral
            })
        );
        assertEq(leverageRouter.convertEquityToCollateral(leverageToken, equityInCollateralAsset), expectedCollateral);
    }

    function testFuzz_convertEquityToCollateral_NonZeroCollateralOrNonZeroDebt_NonMaxCollateralRatio(
        uint256 equityInCollateralAsset,
        uint256 collateral,
        uint256 debt,
        uint256 collateralRatio
    ) public {
        collateral = bound(collateral, 0, type(uint256).max);
        debt = bound(debt, 0, type(uint256).max);
        vm.assume(debt > 0 || collateral > 0);

        collateralRatio = bound(collateralRatio, leverageManager.BASE_RATIO() + 1, type(uint256).max - 1);
        equityInCollateralAsset = bound(equityInCollateralAsset, 0, type(uint256).max / collateralRatio);

        lendingAdapter.mockCollateral(collateral);
        lendingAdapter.mockDebt(debt);

        // Only the collateral ratio returned by LeverageManager.getLeverageTokenState() is relevant for this test
        leverageManager.setLeverageTokenState(
            leverageToken,
            LeverageTokenState({collateralRatio: collateralRatio, debt: debt, equity: 0, collateralInDebtAsset: 0})
        );

        uint256 expectedCollateral = Math.mulDiv(
            equityInCollateralAsset, collateralRatio, collateralRatio - leverageManager.BASE_RATIO(), Math.Rounding.Ceil
        );

        assertEq(leverageRouter.convertEquityToCollateral(leverageToken, equityInCollateralAsset), expectedCollateral);
    }
}
