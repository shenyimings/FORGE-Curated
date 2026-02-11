// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {LeverageManagerTest} from "test/unit/LeverageManager/LeverageManager.t.sol";

contract ConvertDebtToCollateralTest is LeverageManagerTest {
    function setUp() public override {
        super.setUp();

        _createDummyLeverageToken();
    }

    function test_convertDebtToCollateral() public {
        uint256 debt = 3;
        uint256 totalDebt = 101;
        uint256 totalCollateral = 400;
        uint256 totalSupply = 100;

        lendingAdapter.mockCollateral(totalCollateral);
        lendingAdapter.mockDebt(totalDebt);
        _mintShares(address(1), totalSupply);

        uint256 collateral = leverageManager.convertDebtToCollateral(leverageToken, debt, Math.Rounding.Floor);
        assertEq(collateral, 11);
        assertEq(collateral, Math.mulDiv(debt, totalCollateral, totalDebt, Math.Rounding.Floor));

        collateral = leverageManager.convertDebtToCollateral(leverageToken, debt, Math.Rounding.Ceil);
        assertEq(collateral, 12);
        assertEq(collateral, Math.mulDiv(debt, totalCollateral, totalDebt, Math.Rounding.Ceil));
    }

    function test_convertDebtToCollateral_ZeroTotalDebt() public {
        uint256 debt = 3;
        uint256 totalDebt = 0;
        uint256 totalCollateral = 100;
        uint256 initialCollateralRatio = 2.1e18;

        lendingAdapter.mockCollateral(totalCollateral);
        lendingAdapter.mockDebt(totalDebt);
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(0.5e8); // 2 collateral = 1 debt

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        uint256 collateral = leverageManager.convertDebtToCollateral(leverageToken, debt, Math.Rounding.Floor);
        assertEq(collateral, 0);

        collateral = leverageManager.convertDebtToCollateral(leverageToken, debt, Math.Rounding.Ceil);
        assertEq(collateral, 0);
    }

    function test_convertDebtToCollateral_ZeroTotalCollateral() public {
        uint256 debt = 3;
        uint256 totalDebt = 100;
        uint256 totalCollateral = 0;
        uint256 initialCollateralRatio = 2.1e18;

        lendingAdapter.mockCollateral(totalCollateral);
        lendingAdapter.mockDebt(totalDebt);
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(0.5e8); // 2 collateral = 1 debt

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        uint256 collateral = leverageManager.convertDebtToCollateral(leverageToken, debt, Math.Rounding.Floor);
        assertEq(collateral, 0);

        collateral = leverageManager.convertDebtToCollateral(leverageToken, debt, Math.Rounding.Ceil);
        assertEq(collateral, 0);
    }

    function testFuzz_convertDebtToCollateral_ZeroTotalDebt_ZeroTotalCollateral(uint256 debt) public {
        uint256 initialCollateralRatio = 2.1e18;

        lendingAdapter.mockCollateral(0);
        lendingAdapter.mockDebt(0);
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(0.5e8); // 2 collateral = 1 debt

        debt = bound(debt, 0, type(uint256).max / initialCollateralRatio / 2);

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        uint256 collateral = leverageManager.convertDebtToCollateral(leverageToken, debt, Math.Rounding.Floor);
        uint256 collateralExpected = Math.mulDiv(debt, initialCollateralRatio, _BASE_RATIO(), Math.Rounding.Floor) * 2;
        assertEq(collateral, collateralExpected);

        collateral = leverageManager.convertDebtToCollateral(leverageToken, debt, Math.Rounding.Ceil);
        collateralExpected = Math.mulDiv(debt, initialCollateralRatio, _BASE_RATIO(), Math.Rounding.Ceil) * 2;
        assertEq(collateral, collateralExpected);
    }

    function testFuzz_convertDebtToCollateral(
        uint256 debt,
        uint256 totalDebt,
        uint256 totalCollateral,
        uint256 totalSupply,
        uint256 initialCollateralRatio
    ) public {
        initialCollateralRatio = bound(initialCollateralRatio, _BASE_RATIO(), type(uint256).max);
        totalCollateral = bound(totalCollateral, 0, type(uint256).max);
        debt = totalCollateral > 0
            ? bound(debt, 0, totalCollateral / type(uint256).max)
            : bound(debt, 0, type(uint256).max / initialCollateralRatio);

        lendingAdapter.mockCollateral(totalCollateral);
        lendingAdapter.mockDebt(totalDebt);
        _mintShares(address(1), totalSupply);

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        uint256 collateral = leverageManager.convertDebtToCollateral(leverageToken, debt, Math.Rounding.Floor);
        if (totalCollateral == 0 && totalDebt == 0) {
            uint256 collateralExpected = Math.mulDiv(debt, initialCollateralRatio, _BASE_RATIO(), Math.Rounding.Floor);
            assertEq(collateral, collateralExpected);

            collateral = leverageManager.convertDebtToCollateral(leverageToken, debt, Math.Rounding.Ceil);
            collateralExpected = Math.mulDiv(debt, initialCollateralRatio, _BASE_RATIO(), Math.Rounding.Ceil);
            assertEq(collateral, collateralExpected);
        } else if (totalDebt == 0) {
            assertEq(collateral, 0);

            collateral = leverageManager.convertDebtToCollateral(leverageToken, debt, Math.Rounding.Ceil);
            assertEq(collateral, 0);
        } else {
            uint256 collateralExpected = Math.mulDiv(debt, totalCollateral, totalDebt, Math.Rounding.Floor);
            assertEq(collateral, collateralExpected);

            collateral = leverageManager.convertDebtToCollateral(leverageToken, debt, Math.Rounding.Ceil);
            collateralExpected = Math.mulDiv(debt, totalCollateral, totalDebt, Math.Rounding.Ceil);
            assertEq(collateral, collateralExpected);
        }
    }
}
