// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {PricingAdapterTest} from "./PricingAdapter.t.sol";

contract GetLeverageTokenPriceInCollateralTest is PricingAdapterTest {
    function testFork_getLeverageTokenPriceInCollateral() public {
        uint256 equityInCollateralAsset = 1e18;
        uint256 collateralToAdd = 2 * equityInCollateralAsset;

        _mint(user, equityInCollateralAsset, collateralToAdd);

        uint256 result = pricingAdapter.getLeverageTokenPriceInCollateral(leverageToken);
        assertEq(result, 999999999879562786);
        assertEq(result, leverageManager.getLeverageTokenLendingAdapter(leverageToken).getEquityInCollateralAsset());
    }

    function testFork_getLeverageTokenPriceInCollateral_noShares() public view {
        uint256 result = pricingAdapter.getLeverageTokenPriceInCollateral(leverageToken);
        assertEq(result, 0);
    }
}
