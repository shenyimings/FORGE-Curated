// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IMorphoBase, Market} from "@morpho-blue/interfaces/IMorpho.sol";
import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";
import {ORACLE_PRICE_SCALE} from "@morpho-blue/libraries/ConstantsLib.sol";

// Internal imports
import {MorphoLendingAdapterTest} from "./MorphoLendingAdapter.t.sol";

contract GetEquityInDebtAsset is MorphoLendingAdapterTest {
    function test_getEquityInDebtAsset_CollateralIsGreaterThanDebt() public {
        uint128 collateral = 10e6;
        uint128 borrowShares = 5e6;

        // Mocking call to Morpho made in MorphoStorageLib to get the position's borrow shares and collateral
        bytes32[] memory returnValue = new bytes32[](2);
        returnValue[0] = bytes32((uint256(collateral) << 128) | uint256(borrowShares));
        vm.mockCall(address(morpho), abi.encodeWithSelector(IMorphoBase.extSloads.selector), abi.encode(returnValue));

        // Mocking call to Morpho made in MorphoBalancesLib to get the market's total borrow assets and shares
        Market memory market = Market({
            totalSupplyAssets: 0, // Doesn't matter for this test
            totalSupplyShares: 0, // Doesn't matter for this test
            totalBorrowAssets: 5e6,
            totalBorrowShares: borrowShares,
            lastUpdate: uint128(block.timestamp), // Set to the current block timestamp to reduce test complexity (used for accruing interest in MorphoBalancesLib)
            fee: 0 // Set to 0 to reduce test complexity (used for accruing interest in MorphoBalancesLib)
        });
        morpho.mockSetMarket(defaultMarketId, market);

        // Mock the price of the collateral asset in the debt asset to be 1:2
        vm.mockCall(
            address(defaultMarketParams.oracle),
            abi.encodeWithSelector(IOracle.price.selector),
            abi.encode(ORACLE_PRICE_SCALE * 2)
        );

        // Confirm that the collateral converted to debt assets is greater than the debt
        assertGt(lendingAdapter.getCollateralInDebtAsset(), lendingAdapter.getDebt());

        // Confirm that the equity in debt assets is the difference between the collateral converted to debt assets and the debt
        assertEq(
            lendingAdapter.getEquityInDebtAsset(), lendingAdapter.getCollateralInDebtAsset() - lendingAdapter.getDebt()
        );
    }

    function test_getEquityInDebtAsset_CollateralIsLessThanDebt() public {
        uint128 collateral = 5e6;
        uint128 borrowShares = 50e6;

        // Mocking call to Morpho made in MorphoStorageLib to get the position's borrow shares and collateral
        bytes32[] memory returnValue = new bytes32[](2);
        returnValue[0] = bytes32((uint256(collateral) << 128) | uint256(borrowShares));
        vm.mockCall(address(morpho), abi.encodeWithSelector(IMorphoBase.extSloads.selector), abi.encode(returnValue));

        // Mocking call to Morpho made in MorphoBalancesLib to get the market's total borrow assets and shares
        Market memory market = Market({
            totalSupplyAssets: 0, // Doesn't matter for this test
            totalSupplyShares: 0, // Doesn't matter for this test
            totalBorrowAssets: 100e6,
            totalBorrowShares: borrowShares,
            lastUpdate: uint128(block.timestamp), // Set to the current block timestamp to reduce test complexity (used for accruing interest in MorphoBalancesLib)
            fee: 0 // Set to 0 to reduce test complexity (used for accruing interest in MorphoBalancesLib)
        });
        morpho.mockSetMarket(defaultMarketId, market);

        // Mock the price of the collateral asset in the debt asset to be 1:1
        vm.mockCall(
            address(defaultMarketParams.oracle),
            abi.encodeWithSelector(IOracle.price.selector),
            abi.encode(ORACLE_PRICE_SCALE)
        );

        // Confirm that the collateral converted to debt assets is less than the debt
        assertLt(lendingAdapter.getCollateralInDebtAsset(), lendingAdapter.getDebt());

        // Confirm that the equity returned is 0
        assertEq(lendingAdapter.getEquityInDebtAsset(), 0);
    }

    function test_getEquityInDebtAsset_CollateralIsEqualToDebt() public {
        uint128 collateral = 5e6;
        uint128 borrowShares = 5e6;

        // Mocking call to Morpho made in MorphoStorageLib to get the position's borrow shares and collateral
        bytes32[] memory returnValue = new bytes32[](2);
        returnValue[0] = bytes32((uint256(collateral) << 128) | uint256(borrowShares));
        vm.mockCall(address(morpho), abi.encodeWithSelector(IMorphoBase.extSloads.selector), abi.encode(returnValue));

        // Mocking call to Morpho made in MorphoBalancesLib to get the market's total borrow assets and shares
        Market memory market = Market({
            totalSupplyAssets: 0, // Doesn't matter for this test
            totalSupplyShares: 0, // Doesn't matter for this test
            // Morpho's SharesMathLib uses virtual shares and assets offsets to prevent division by zero in the case of an empty market.
            //
            // The core calculation used is in SharesMathLib.toAssetsUp, to convert shares to assets:
            //     shares.mulDivUp(totalBorrowAssets + VIRTUAL_ASSETS, totalBorrowShares + VIRTUAL_SHARES),
            //     where VIRTUAL_ASSETS = 1 and VIRTUAL_SHARES = 1e6
            //
            // For this test, we want to ensure that the lendingAdapter's borrow shares converted to assets are equal to the lendingAdapter's
            // collateral converted to debt assets. To do so, we add (VIRTUAL_SHARES - VIRTUAL_ASSETS) amount of virtual assets to the total borrow assets so that
            // the conversion rate is 1:1. The result is:
            //     borrowShares.mulDivUp(totalBorrowAssets + VIRTUAL_ASSETS, totalBorrowShares + VIRTUAL_SHARES)
            //     = 5e6.mulDivUp((5e6 + (1e6 - 1)) + 1, 5e6 + 1e6 - 1)
            //     = 5e6.mulDivUp(6e6, 6e6)
            //     = 5e6
            totalBorrowAssets: uint128(borrowShares + MORPHO_VIRTUAL_SHARES - MORPHO_VIRTUAL_ASSETS),
            totalBorrowShares: borrowShares,
            lastUpdate: uint128(block.timestamp), // Set to the current block timestamp to reduce test complexity (used for accruing interest in MorphoBalancesLib)
            fee: 0 // Set to 0 to reduce test complexity (used for accruing interest in MorphoBalancesLib)
        });
        morpho.mockSetMarket(defaultMarketId, market);

        // Mock the price of the collateral asset in the debt asset to be 1:1
        vm.mockCall(
            address(defaultMarketParams.oracle),
            abi.encodeWithSelector(IOracle.price.selector),
            abi.encode(ORACLE_PRICE_SCALE)
        );

        // Confirm that the collateral converted to debt assets is equal to the debt
        assertEq(lendingAdapter.getCollateralInDebtAsset(), lendingAdapter.getDebt());

        // Confirm that the equity returned is 0
        assertEq(lendingAdapter.getEquityInDebtAsset(), 0);
    }
}
