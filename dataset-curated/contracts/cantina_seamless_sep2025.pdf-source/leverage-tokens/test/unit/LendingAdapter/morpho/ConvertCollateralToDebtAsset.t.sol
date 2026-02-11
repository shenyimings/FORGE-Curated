// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";
import {ORACLE_PRICE_SCALE} from "@morpho-blue/libraries/ConstantsLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {MorphoLendingAdapterTest} from "./MorphoLendingAdapter.t.sol";

contract ConvertCollateralToDebtAsset is MorphoLendingAdapterTest {
    function test_convertCollateralToDebtAsset_ReturnsDebtDecimalsLessThanCollateralDecimals() public {
        collateralToken.mockSetDecimals(18);
        debtToken.mockSetDecimals(6);

        uint256 collateral = 1e18;

        // Mock the price of the collateral asset in the debt asset to be 1 collateral = 2 debt.
        // 24 decimals of precision because IOracle.price() returns with `36 + loan token decimals - collateral token decimals` precision.
        uint256 price = 2e24;
        vm.mockCall(
            address(defaultMarketParams.oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(price)
        );

        assertEq(lendingAdapter.convertCollateralToDebtAsset(collateral), 2e6);
    }

    function test_convertCollateralToDebtAsset_ReturnsDebtDecimalsGreaterThanCollateralDecimals() public {
        collateralToken.mockSetDecimals(6);
        debtToken.mockSetDecimals(18);

        uint256 collateral = 1e6;

        // Mock the price of the collateral asset in the debt asset to be 1 collateral = 2 debt.
        // 48 decimals of precision because IOracle.price() returns with `36 + loan token decimals - collateral token decimals` precision.
        uint256 price = 2e48;
        vm.mockCall(
            address(defaultMarketParams.oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(price)
        );

        assertEq(lendingAdapter.convertCollateralToDebtAsset(collateral), 2e18);
    }

    function test_convertCollateralToDebtAsset_EqualDebtAndCollateralDecimals() public {
        collateralToken.mockSetDecimals(18);
        debtToken.mockSetDecimals(18);

        uint256 collateral = 1e18;
        // Mock the price of the collateral asset in the debt asset to be 1 collateral = 2 debt.
        // 36 decimals of precision because IOracle.price() returns with `36 + loan token decimals - collateral token decimals`.
        uint256 price = 2e36;
        vm.mockCall(
            address(defaultMarketParams.oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(price)
        );

        assertEq(lendingAdapter.convertCollateralToDebtAsset(collateral), 2e18);
    }

    /// @dev uint128 is used to avoid overflows in the test. Also, Morpho only supports up to type(uint128).max for debt and collateral
    function testFuzz_convertCollateralToDebtAsset_RoundsDown_EqualDebtAndCollateralDecimals(uint128 collateral)
        public
    {
        collateralToken.mockSetDecimals(18);
        debtToken.mockSetDecimals(18);

        // Mock the price of the collateral asset in the debt asset to be 1 less than 1:1 to simulate rounding down.
        // The oracle has 36 decimals of precision because it is scaled by `36 + loan token decimals - collateral token decimals`.
        uint256 price = ORACLE_PRICE_SCALE - 1;
        vm.mockCall(
            address(defaultMarketParams.oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(price)
        );

        assertEq(
            lendingAdapter.convertCollateralToDebtAsset(collateral),
            Math.mulDiv(collateral, price, ORACLE_PRICE_SCALE, Math.Rounding.Floor)
        );
    }

    /// @dev uint128 is used to avoid overflows in the test. Also, Morpho only supports up to type(uint128).max for debt and collateral
    function testFuzz_convertCollateralToDebtAsset_RoundsDown_CollateralDecimalsGreaterThanDebtDecimals(
        uint128 collateral
    ) public {
        uint8 collateralDecimals = 18;
        uint8 debtDecimals = 6;
        collateralToken.mockSetDecimals(collateralDecimals);
        debtToken.mockSetDecimals(debtDecimals);

        // Mock the price of the collateral asset in the debt asset to be 1 less than 1:1 to simulate rounding down.
        // The oracle has `36 + loan token decimals - collateral token decimals` decimals of precision (36 + 6 - 18 = 24).
        uint256 priceScale = 1e24;
        uint256 price = priceScale - 1;
        vm.mockCall(
            address(defaultMarketParams.oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(price)
        );

        uint256 collateralScalingFactor = 10 ** (collateralDecimals - debtDecimals);

        assertEq(
            lendingAdapter.convertCollateralToDebtAsset(collateral),
            Math.mulDiv(collateral, price, priceScale * collateralScalingFactor, Math.Rounding.Floor)
        );
    }

    /// @dev uint128 is used to avoid overflows in the test. Also, Morpho only supports up to type(uint128).max for debt and collateral
    function testFuzz_convertCollateralToDebtAsset_RoundsDown_DebtDecimalsGreaterThanCollateralDecimals(
        uint128 collateral
    ) public {
        uint8 collateralDecimals = 6;
        uint8 debtDecimals = 18;
        collateralToken.mockSetDecimals(collateralDecimals);
        debtToken.mockSetDecimals(debtDecimals);

        // Mock the price of the collateral asset in the debt asset to be 1 less than 1:1 to simulate rounding down.
        // The oracle has `36 + loan token decimals - collateral token decimals` decimals of precision (36 + 18 - 6 = 48).
        uint256 priceScale = 1e48;
        uint256 price = priceScale - 1;
        vm.mockCall(
            address(defaultMarketParams.oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(price)
        );

        uint256 collateralScalingFactor = 10 ** (debtDecimals - collateralDecimals);

        assertEq(
            lendingAdapter.convertCollateralToDebtAsset(collateral),
            Math.mulDiv(collateral * collateralScalingFactor, price, priceScale, Math.Rounding.Floor)
        );
    }
}
