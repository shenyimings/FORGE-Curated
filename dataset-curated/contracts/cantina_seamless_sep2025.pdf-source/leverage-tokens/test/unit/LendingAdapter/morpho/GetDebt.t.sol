// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IMorphoBase, Market} from "@morpho-blue/interfaces/IMorpho.sol";
import {SharesMathLib} from "@morpho-blue/libraries/SharesMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {MorphoLendingAdapterTest} from "./MorphoLendingAdapter.t.sol";

contract GetDebt is MorphoLendingAdapterTest {
    function test_getDebt() public {
        uint256 borrowShares = 10e6;

        // MorphoBalancesLib, used by MorphoLendingAdapter, calls Morpho.extSloads to get the lendingAdapter's amount of borrow shares
        uint256[] memory returnValue = new uint256[](1);
        returnValue[0] = borrowShares;
        vm.mockCall(address(morpho), abi.encodeWithSelector(IMorphoBase.extSloads.selector), abi.encode(returnValue));

        // Mocking call to Morpho made in MorphoBalancesLib to get the market's total borrow assets and shares, which is how MorphoBalancesLib
        // calculates the exchange rate between borrow shares and borrow assets
        Market memory market = Market({
            totalSupplyAssets: 0, // Doesn't matter for this test
            totalSupplyShares: 0, // Doesn't matter for this test
            totalBorrowAssets: 10e18,
            totalBorrowShares: 14e6,
            lastUpdate: uint128(block.timestamp), // Set to the current block timestamp to reduce test complexity (used for accruing interest in MorphoBalancesLib)
            fee: 0 // Set to 0 to reduce test complexity (used for accruing interest in MorphoBalancesLib)
        });
        morpho.mockSetMarket(defaultMarketId, market);

        assertEq(
            lendingAdapter.getDebt(),
            // getDebt() calls MorphoBalancesLib.expectedBorrowAssets, which uses SharesMathLib.toAssetsUp with the market's total borrow assets and shares, which are mocked above
            SharesMathLib.toAssetsUp(borrowShares, market.totalBorrowAssets, market.totalBorrowShares)
        );
    }
}
