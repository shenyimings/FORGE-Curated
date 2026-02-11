// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {LeverageManagerTest} from "test/unit/LeverageManager/LeverageManager.t.sol";

contract ConvertCollateralToSharesTest is LeverageManagerTest {
    function setUp() public override {
        super.setUp();

        _createDummyLeverageToken();
    }

    function test_convertCollateralToShares() public {
        uint256 collateral = 5;
        uint256 totalCollateral = 100;
        uint256 totalSupply = 50;

        lendingAdapter.mockCollateral(totalCollateral);
        _mintShares(address(1), totalSupply);

        uint256 shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Floor);
        assertEq(shares, 2);
        assertEq(shares, Math.mulDiv(collateral, totalSupply, totalCollateral, Math.Rounding.Floor));

        shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Ceil);
        assertEq(shares, 3);
        assertEq(shares, Math.mulDiv(collateral, totalSupply, totalCollateral, Math.Rounding.Ceil));
    }

    function test_convertCollateralToShares_ZeroTotalSupply_CollateralDecimalsEqualLeverageTokenDecimals() public {
        uint256 collateral = 5;
        uint256 totalCollateral = 100;
        uint256 totalSupply = 0;
        uint256 initialCollateralRatio = 2 * _BASE_RATIO();

        lendingAdapter.mockCollateral(totalCollateral);
        _mintShares(address(1), totalSupply);

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        uint256 shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Floor);
        assertEq(shares, 2); // Delta in decimals is 18 - 18 = 0, shares = 2 equity

        shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Ceil);
        assertEq(shares, 3); // Delta in decimals is 18 - 18 = 0, shares = 3 equity
    }

    function test_convertCollateralToShares_ZeroTotalSupply_CollateralDecimalsLtLeverageTokenDecimals() public {
        uint256 collateral = 5;
        uint256 totalCollateral = 100;
        uint256 totalSupply = 0;
        uint256 initialCollateralRatio = 2 * _BASE_RATIO();

        lendingAdapter.mockCollateral(totalCollateral);
        _mintShares(address(1), totalSupply);

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        collateralToken.mockSetDecimals(12);

        uint256 shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Ceil);
        assertEq(shares, 3e6);
        assertEq(shares, 3 * 1e6); // Delta in decimals is 18 - 12 = 6, shares = 3 equity * 1e6 scaling factor

        shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Floor);
        assertEq(shares, 2e6);
        assertEq(shares, 2 * 1e6); // Delta in decimals is 18 - 12 = 6, shares = 2 equity * 1e6 scaling factor
    }

    function test_convertCollateralToShares_ZeroTotalSupply_CollateralDecimalsGtLeverageTokenDecimals() public {
        uint256 collateral = 5e6;
        uint256 totalCollateral = 100;
        uint256 totalSupply = 0;
        uint256 initialCollateralRatio = 3 * _BASE_RATIO();

        lendingAdapter.mockCollateral(totalCollateral);
        _mintShares(address(1), totalSupply);

        collateralToken.mockSetDecimals(24);

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        uint256 shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Ceil);
        assertEq(shares, 3); // Delta in decimals is 24 - 18 = 6, shares = 3,333,333 equity / 1e6 scaling factor, rounded down

        shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Floor);
        assertEq(shares, 3); // Delta in decimals is 24 - 18 = 6, shares = 3,333,334 equity / 1e6 scaling factor, rounded down
    }

    function test_convertCollateralToShares_ZeroTotalCollateral() public {
        uint256 collateral = 5;
        uint256 totalCollateral = 0;
        uint256 totalSupply = 50;
        uint256 initialCollateralRatio = 2 * _BASE_RATIO();

        lendingAdapter.mockCollateral(totalCollateral);
        _mintShares(address(1), totalSupply);

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        collateralToken.mockSetDecimals(12);

        uint256 shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Ceil);
        assertEq(shares, 0);

        shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Floor);
        assertEq(shares, 0);
    }

    function testFuzz_convertCollateralToShares(
        uint256 collateral,
        uint256 totalCollateral,
        uint256 totalSupply,
        uint256 initialCollateralRatio
    ) public {
        totalSupply = bound(totalSupply, 0, type(uint256).max);
        collateral = totalSupply > 0
            ? bound(collateral, 0, totalSupply / type(uint256).max)
            : bound(collateral, 0, type(uint256).max / _BASE_RATIO());
        initialCollateralRatio = bound(initialCollateralRatio, _BASE_RATIO() + 1, type(uint256).max);

        lendingAdapter.mockCollateral(totalCollateral);
        _mintShares(address(1), totalSupply);

        vm.mockCall(
            address(rebalanceAdapter),
            abi.encodeWithSelector(IRebalanceAdapterBase.getLeverageTokenInitialCollateralRatio.selector),
            abi.encode(initialCollateralRatio)
        );

        if (totalSupply == 0) {
            uint256 shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Floor);
            uint256 debtInCollateralAsset =
                Math.mulDiv(collateral, _BASE_RATIO(), initialCollateralRatio, Math.Rounding.Ceil);
            uint256 equityInCollateralAsset = collateral - debtInCollateralAsset;
            assertEq(shares, equityInCollateralAsset);

            shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Ceil);
            debtInCollateralAsset = Math.mulDiv(collateral, _BASE_RATIO(), initialCollateralRatio, Math.Rounding.Floor);
            equityInCollateralAsset = collateral - debtInCollateralAsset;
            assertEq(shares, equityInCollateralAsset);
        } else if (totalCollateral == 0) {
            uint256 shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Floor);
            assertEq(shares, 0);

            shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Ceil);
            assertEq(shares, 0);
        } else {
            uint256 shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Floor);
            uint256 sharesExpected = Math.mulDiv(collateral, totalSupply, totalCollateral, Math.Rounding.Floor);
            assertEq(shares, sharesExpected);

            shares = leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Ceil);
            sharesExpected = Math.mulDiv(collateral, totalSupply, totalCollateral, Math.Rounding.Ceil);
            assertEq(shares, sharesExpected);
        }
    }
}
