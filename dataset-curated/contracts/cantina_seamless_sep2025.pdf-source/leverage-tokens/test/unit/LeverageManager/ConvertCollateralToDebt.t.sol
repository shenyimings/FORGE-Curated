// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {LeverageManagerTest} from "test/unit/LeverageManager/LeverageManager.t.sol";

contract ConvertCollateralToDebtTest is LeverageManagerTest {
    function setUp() public override {
        super.setUp();

        _createDummyLeverageToken();
    }

    function test_convertCollateralToDebt() public {
        uint256 collateral = 5;
        uint256 totalCollateral = 100;
        uint256 totalDebt = 50;
        uint256 totalSupply = 100;

        lendingAdapter.mockCollateral(totalCollateral);
        lendingAdapter.mockDebt(totalDebt);
        _mintShares(address(1), totalSupply);

        uint256 debt = leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Floor);
        assertEq(debt, 2);
        assertEq(debt, Math.mulDiv(collateral, totalDebt, totalCollateral, Math.Rounding.Floor));

        debt = leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Ceil);
        assertEq(debt, 3);
        assertEq(debt, Math.mulDiv(collateral, totalDebt, totalCollateral, Math.Rounding.Ceil));
    }

    function test_convertCollateralToDebt_ZeroTotalDebt() public {
        uint256 collateral = 5;
        uint256 totalCollateral = 100;
        uint256 totalDebt = 0;
        uint256 initialCollateralRatio = 2 * _BASE_RATIO();
        uint256 totalSupply = 100;

        lendingAdapter.mockCollateral(totalCollateral);
        lendingAdapter.mockDebt(totalDebt);
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8); // 1 collateral = 2 debt
        _mintShares(address(1), totalSupply);

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        uint256 debt = leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Floor);
        assertEq(debt, 0);

        debt = leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Ceil);
        assertEq(debt, 0);
    }

    function test_convertCollateralToDebt_ZeroCollateral() public {
        uint256 collateral = 5;
        uint256 totalCollateral = 0;
        uint256 totalDebt = 50;
        uint256 initialCollateralRatio = 2 * _BASE_RATIO();
        uint256 totalSupply = 100;

        lendingAdapter.mockCollateral(totalCollateral);
        lendingAdapter.mockDebt(totalDebt);
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8); // 1 collateral = 2 debt
        _mintShares(address(1), totalSupply);

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        uint256 debt = leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Floor);
        assertEq(debt, 0);

        debt = leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Ceil);
        assertEq(debt, 0);
    }

    function testFuzz_convertCollateralToDebt_ZeroTotalCollateral_ZeroTotalDebt(uint256 collateral) public {
        collateral = bound(collateral, 0, type(uint256).max / _BASE_RATIO() / 2);
        uint256 initialCollateralRatio = 2 * _BASE_RATIO();
        uint256 totalSupply = 100;

        lendingAdapter.mockCollateral(0);
        lendingAdapter.mockDebt(0);
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8); // 1 collateral = 2 debt
        _mintShares(address(1), totalSupply);

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        uint256 debt = leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Floor);
        uint256 debtExpected = Math.mulDiv(collateral, _BASE_RATIO(), initialCollateralRatio, Math.Rounding.Floor) * 2;
        assertEq(debt, debtExpected);

        debt = leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Ceil);
        debtExpected = Math.mulDiv(collateral, _BASE_RATIO(), initialCollateralRatio, Math.Rounding.Ceil) * 2;
        assertEq(debt, debtExpected);
    }

    function testFuzz_convertCollateralToDebt(
        uint256 collateral,
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 totalSupply,
        uint256 initialCollateralRatio
    ) public {
        totalDebt = bound(totalDebt, 0, type(uint256).max);
        collateral = totalDebt > 0
            ? bound(collateral, 0, totalDebt / type(uint256).max)
            : bound(collateral, 0, type(uint256).max / _BASE_RATIO());
        initialCollateralRatio = bound(initialCollateralRatio, _BASE_RATIO(), type(uint256).max);

        lendingAdapter.mockCollateral(totalCollateral);
        lendingAdapter.mockDebt(totalDebt);
        _mintShares(address(1), totalSupply);

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        uint256 debt = leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Floor);
        if (totalCollateral == 0 && totalDebt == 0) {
            uint256 debtExpected = Math.mulDiv(collateral, _BASE_RATIO(), initialCollateralRatio, Math.Rounding.Floor);
            assertEq(debt, debtExpected);

            debt = leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Ceil);
            debtExpected = Math.mulDiv(collateral, _BASE_RATIO(), initialCollateralRatio, Math.Rounding.Ceil);
            assertEq(debt, debtExpected);
        } else if (totalCollateral == 0) {
            assertEq(debt, 0);

            debt = leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Ceil);
            assertEq(debt, 0);
        } else {
            uint256 debtExpected = Math.mulDiv(collateral, totalDebt, totalCollateral, Math.Rounding.Floor);
            assertEq(debt, debtExpected);

            debt = leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Ceil);
            debtExpected = Math.mulDiv(collateral, totalDebt, totalCollateral, Math.Rounding.Ceil);
            assertEq(debt, debtExpected);
        }
    }
}
