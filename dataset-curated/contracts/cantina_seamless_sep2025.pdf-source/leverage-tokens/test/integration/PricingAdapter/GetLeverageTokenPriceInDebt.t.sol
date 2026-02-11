// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {PricingAdapterTest} from "./PricingAdapter.t.sol";

contract GetLeverageTokenPriceInDebtTest is PricingAdapterTest {
    function testFork_getLeverageTokenPriceInDebt() public {
        uint256 equityInCollateralAsset = 1e18;
        uint256 collateralToAdd = 2 * equityInCollateralAsset;

        _mint(user, equityInCollateralAsset, collateralToAdd);

        uint256 result = pricingAdapter.getLeverageTokenPriceInDebt(leverageToken);
        assertEq(result, 3392292471);
        assertEq(result, leverageManager.getLeverageTokenLendingAdapter(leverageToken).getEquityInDebtAsset());
    }

    function testFork_getLeverageTokenPriceInDebt_noShares() public view {
        uint256 result = pricingAdapter.getLeverageTokenPriceInDebt(leverageToken);
        assertEq(result, 0);
    }
}
