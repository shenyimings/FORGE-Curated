// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Internal imports
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {LeverageManagerTest} from "test/unit/LeverageManager/LeverageManager.t.sol";

contract ConvertSharesToCollateralTest is LeverageManagerTest {
    function setUp() public override {
        super.setUp();

        _createDummyLeverageToken();
    }

    function test_convertSharesToCollateral() public {
        uint256 shares = 1;
        uint256 totalSupply = 100;
        uint256 totalCollateral = 99;

        lendingAdapter.mockCollateral(totalCollateral);
        _mintShares(address(1), totalSupply);

        uint256 collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Floor);
        assertEq(collateral, 0);

        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(collateral, 1);
    }

    function testFuzz_convertSharesToCollateral(uint128 shares, uint128 totalSupply, uint128 totalCollateral) public {
        totalSupply = uint128(bound(totalSupply, 1, type(uint128).max));
        totalCollateral = uint128(bound(totalCollateral, 1, type(uint128).max));

        lendingAdapter.mockCollateral(totalCollateral);
        _mintShares(address(1), totalSupply);

        uint256 collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Floor);
        uint256 collateralExpected = Math.mulDiv(shares, totalCollateral, totalSupply, Math.Rounding.Floor);
        assertEq(collateral, collateralExpected);

        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Ceil);
        collateralExpected = Math.mulDiv(shares, totalCollateral, totalSupply, Math.Rounding.Ceil);
        assertEq(collateral, collateralExpected);
    }

    function testFuzz_convertSharesToCollateral_EmptyLeverageToken_CollateralAsset18Decimals(
        uint128 shares,
        uint128 nonZeroValue
    ) public {
        uint256 initialCollateralRatio = 2 * _BASE_RATIO();
        shares = uint128(bound(shares, 0, type(uint128).max / initialCollateralRatio));
        nonZeroValue = uint128(bound(nonZeroValue, 1, type(uint128).max));

        uint256 totalSupply = nonZeroValue;
        uint256 totalCollateral = 0;

        lendingAdapter.mockCollateral(totalCollateral);
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

        uint256 collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Floor);
        assertEq(collateral, 0);

        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(collateral, 0);

        totalCollateral = nonZeroValue;
        lendingAdapter.mockCollateral(totalCollateral);
        _burnShares(address(1), totalSupply); // Burn all shares

        uint256 expectedCollateralFloored =
            Math.mulDiv(shares, initialCollateralRatio, initialCollateralRatio - _BASE_RATIO(), Math.Rounding.Floor);
        uint256 expectedCollateralCeiled =
            Math.mulDiv(shares, initialCollateralRatio, initialCollateralRatio - _BASE_RATIO(), Math.Rounding.Ceil);

        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Floor);
        assertEq(collateral, expectedCollateralFloored);

        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(collateral, expectedCollateralCeiled);
    }

    function testFuzz_convertSharesToCollateral_EmptyLeverageToken_CollateralAssetLessThan18Decimals(
        uint128 shares,
        uint128 nonZeroValue
    ) public {
        uint256 initialCollateralRatio = 2 * _BASE_RATIO();
        shares = uint128(bound(shares, 0, type(uint128).max / initialCollateralRatio));
        nonZeroValue = uint128(bound(nonZeroValue, 1, type(uint128).max));

        uint256 collateralDecimals = 6;

        uint256 totalSupply = nonZeroValue;
        uint256 totalCollateral = 0;

        lendingAdapter.mockCollateral(totalCollateral);
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

        uint256 collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Floor);
        assertEq(collateral, 0);

        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(collateral, 0);

        totalCollateral = nonZeroValue;
        lendingAdapter.mockCollateral(totalCollateral);
        _burnShares(address(1), totalSupply); // Burn all shares

        uint256 scalingFactor = 10 ** (18 - collateralDecimals);
        uint256 expectedCollateralFloored = Math.mulDiv(
            shares,
            initialCollateralRatio,
            (initialCollateralRatio - _BASE_RATIO()) * scalingFactor,
            Math.Rounding.Floor
        );
        uint256 expectedCollateralCeiled = Math.mulDiv(
            shares, initialCollateralRatio, (initialCollateralRatio - _BASE_RATIO()) * scalingFactor, Math.Rounding.Ceil
        );

        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Floor);
        assertEq(collateral, expectedCollateralFloored);

        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(collateral, expectedCollateralCeiled);
    }

    function testFuzz_convertSharesToCollateral_EmptyLeverageToken_CollateralAssetMoreThan18Decimals(
        uint128 shares,
        uint128 nonZeroValue
    ) public {
        uint256 initialCollateralRatio = 2 * _BASE_RATIO();
        shares = uint128(bound(shares, 0, type(uint128).max / initialCollateralRatio));
        nonZeroValue = uint128(bound(nonZeroValue, 1, type(uint128).max));

        uint256 collateralDecimals = 27;

        uint256 totalSupply = nonZeroValue;
        uint256 totalCollateral = 0;

        lendingAdapter.mockCollateral(totalCollateral);
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

        uint256 collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Floor);
        assertEq(collateral, 0);

        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(collateral, 0);

        totalCollateral = nonZeroValue;
        lendingAdapter.mockCollateral(totalCollateral);
        _burnShares(address(1), totalSupply); // Burn all shares

        uint256 scalingFactor = 10 ** (collateralDecimals - 18);
        uint256 expectedCollateralFloored = Math.mulDiv(
            shares * scalingFactor,
            initialCollateralRatio,
            (initialCollateralRatio - _BASE_RATIO()),
            Math.Rounding.Floor
        );
        uint256 expectedCollateralCeiled = Math.mulDiv(
            shares * scalingFactor, initialCollateralRatio, (initialCollateralRatio - _BASE_RATIO()), Math.Rounding.Ceil
        );

        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Floor);
        assertEq(collateral, expectedCollateralFloored);

        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(collateral, expectedCollateralCeiled);
    }

    function test_convertSharesToCollateral_WithManagementFee() public {
        uint128 shares = 10;
        uint128 totalSupply = 100;
        uint128 totalCollateral = 99;

        uint256 managementFee = 0.5e4; // 50%
        _setManagementFee(feeManagerRole, leverageToken, managementFee);

        lendingAdapter.mockCollateral(totalCollateral);
        _mintShares(address(1), totalSupply);

        uint256 collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Floor);
        assertEq(collateral, 9);

        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(collateral, 10);

        // One year passes
        skip(SECONDS_ONE_YEAR);

        // Collateral should be less due to the management fee increasing the virtual total supply
        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Floor);
        assertEq(collateral, 6);

        collateral = leverageManager.convertSharesToCollateral(leverageToken, shares, Math.Rounding.Ceil);
        assertEq(collateral, 7);
    }
}
