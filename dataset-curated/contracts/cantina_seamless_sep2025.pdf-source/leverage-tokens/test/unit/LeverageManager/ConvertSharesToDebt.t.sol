// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Internal imports
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {LeverageManagerTest} from "test/unit/LeverageManager/LeverageManager.t.sol";

contract ConvertSharesToDebtTest is LeverageManagerTest {
    function setUp() public override {
        super.setUp();

        _createDummyLeverageToken();
    }

    function test_convertSharesToDebt() public {
        uint256 shares = 1;
        uint256 totalSupply = 100;
        uint256 totalDebt = 99;

        lendingAdapter.mockDebt(totalDebt);
        _mintShares(address(1), totalSupply);

        uint256 debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Floor);
        assertEq(debt, 0);

        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(debt, 1);
    }

    function testFuzz_convertSharesToDebt(uint128 shares, uint128 totalSupply, uint128 totalDebt) public {
        totalSupply = uint128(bound(totalSupply, 1, type(uint128).max));
        totalDebt = uint128(bound(totalDebt, 1, type(uint128).max));

        lendingAdapter.mockDebt(totalDebt);
        _mintShares(address(1), totalSupply);

        uint256 debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Floor);
        uint256 debtExpected = Math.mulDiv(shares, totalDebt, totalSupply, Math.Rounding.Floor);
        assertEq(debt, debtExpected);

        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Ceil);
        debtExpected = Math.mulDiv(shares, totalDebt, totalSupply, Math.Rounding.Ceil);
        assertEq(debt, debtExpected);
    }

    function testFuzz_convertSharesToDebt_EmptyLeverageToken_CollateralAsset18Decimals(
        uint128 shares,
        uint128 nonZeroValue
    ) public {
        uint256 initialCollateralRatio = 2 * _BASE_RATIO();
        shares = uint128(bound(shares, 0, type(uint128).max / initialCollateralRatio));
        nonZeroValue = uint128(bound(nonZeroValue, 1, type(uint128).max));

        uint256 totalSupply = nonZeroValue;
        uint256 totalDebt = 0;

        lendingAdapter.mockDebt(totalDebt);
        _mintShares(address(1), totalSupply);

        vm.mockCall(
            address(lendingAdapter.getCollateralAsset()),
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(18)
        );

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        uint256 debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Floor);
        assertEq(debt, 0);

        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(debt, 0);

        totalDebt = nonZeroValue;
        lendingAdapter.mockDebt(totalDebt);
        _burnShares(address(1), totalSupply); // Burn all shares

        uint256 expectedDebtFloored =
            Math.mulDiv(shares, _BASE_RATIO(), initialCollateralRatio - _BASE_RATIO(), Math.Rounding.Floor);
        uint256 expectedDebtCeiled =
            Math.mulDiv(shares, _BASE_RATIO(), initialCollateralRatio - _BASE_RATIO(), Math.Rounding.Ceil);

        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Floor);
        assertEq(debt, expectedDebtFloored);

        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(debt, expectedDebtCeiled);
    }

    function testFuzz_convertSharesToDebt_EmptyLeverageToken_CollateralAssetLessThan18Decimals(
        uint128 shares,
        uint128 nonZeroValue
    ) public {
        uint256 initialCollateralRatio = 2 * _BASE_RATIO();
        shares = uint128(bound(shares, 0, type(uint128).max / initialCollateralRatio));
        nonZeroValue = uint128(bound(nonZeroValue, 1, type(uint128).max));

        uint256 totalSupply = nonZeroValue;
        uint256 totalDebt = 0;

        uint256 collateralDecimals = 6;

        lendingAdapter.mockDebt(totalDebt);
        _mintShares(address(1), totalSupply);

        vm.mockCall(
            address(lendingAdapter.getCollateralAsset()),
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(collateralDecimals)
        );

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        uint256 debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Floor);
        assertEq(debt, 0);

        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(debt, 0);

        totalDebt = nonZeroValue;
        lendingAdapter.mockDebt(totalDebt);
        _burnShares(address(1), totalSupply); // Burn all shares

        uint256 scalingFactor = 10 ** (18 - collateralDecimals);

        uint256 expectedDebtFloored = Math.mulDiv(
            shares, _BASE_RATIO(), (initialCollateralRatio - _BASE_RATIO()) * scalingFactor, Math.Rounding.Floor
        );
        uint256 expectedDebtCeiled = Math.mulDiv(
            shares, _BASE_RATIO(), (initialCollateralRatio - _BASE_RATIO()) * scalingFactor, Math.Rounding.Ceil
        );

        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Floor);
        assertEq(debt, expectedDebtFloored);

        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(debt, expectedDebtCeiled);
    }

    function testFuzz_convertSharesToDebt_EmptyLeverageToken_CollateralAssetMoreThan18Decimals(
        uint128 shares,
        uint128 nonZeroValue
    ) public {
        uint256 initialCollateralRatio = 2 * _BASE_RATIO();
        shares = uint128(bound(shares, 0, type(uint128).max / initialCollateralRatio));
        nonZeroValue = uint128(bound(nonZeroValue, 1, type(uint128).max));

        uint256 totalSupply = nonZeroValue;
        uint256 totalDebt = 0;

        uint256 collateralDecimals = 27;

        lendingAdapter.mockDebt(totalDebt);
        _mintShares(address(1), totalSupply);

        vm.mockCall(
            address(lendingAdapter.getCollateralAsset()),
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(collateralDecimals)
        );

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        uint256 debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Floor);
        assertEq(debt, 0);

        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(debt, 0);

        totalDebt = nonZeroValue;
        lendingAdapter.mockDebt(totalDebt);
        _burnShares(address(1), totalSupply); // Burn all shares

        uint256 scalingFactor = 10 ** (collateralDecimals - 18);

        uint256 expectedDebtFloored = Math.mulDiv(
            shares * scalingFactor, _BASE_RATIO(), (initialCollateralRatio - _BASE_RATIO()), Math.Rounding.Floor
        );
        uint256 expectedDebtCeiled = Math.mulDiv(
            shares * scalingFactor, _BASE_RATIO(), (initialCollateralRatio - _BASE_RATIO()), Math.Rounding.Ceil
        );

        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Floor);
        assertEq(debt, expectedDebtFloored);

        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(debt, expectedDebtCeiled);
    }

    function test_convertSharesToDebt_WithManagementFee() public {
        uint128 shares = 10;
        uint128 totalSupply = 100;
        uint128 totalDebt = 99;

        uint256 managementFee = 0.5e4; // 50%
        _setManagementFee(feeManagerRole, leverageToken, managementFee);

        lendingAdapter.mockDebt(totalDebt);
        _mintShares(address(1), totalSupply);

        uint256 debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Floor);
        assertEq(debt, 9);

        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(debt, 10);

        // One year passes
        skip(SECONDS_ONE_YEAR);

        // Debt should be less due to the management fee increasing the virtual total supply
        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Floor);
        assertEq(debt, 6);

        debt = leverageManager.convertSharesToDebt(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(debt, 7);
    }
}
