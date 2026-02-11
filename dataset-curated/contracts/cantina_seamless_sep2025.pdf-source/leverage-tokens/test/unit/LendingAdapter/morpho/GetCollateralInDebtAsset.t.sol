// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IMorphoBase} from "@morpho-blue/interfaces/IMorpho.sol";
import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";
import {ORACLE_PRICE_SCALE} from "@morpho-blue/libraries/ConstantsLib.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {MorphoLendingAdapterTest} from "./MorphoLendingAdapter.t.sol";

contract GetCollateralInDebtAsset is MorphoLendingAdapterTest {
    function test_getCollateralInDebtAsset() public {
        uint256 collateral = 5e6;

        // Mocking call to Morpho made in MorphoStorageLib to get the position's borrow shares and collateral
        bytes32[] memory returnValue = new bytes32[](2);
        returnValue[0] = bytes32(uint256(collateral << 128));
        vm.mockCall(address(morpho), abi.encodeWithSelector(IMorphoBase.extSloads.selector), abi.encode(returnValue));

        // Mock the price of the collateral asset in the debt asset to be 2:1
        vm.mockCall(
            address(defaultMarketParams.oracle),
            abi.encodeWithSelector(IOracle.price.selector),
            abi.encode(ORACLE_PRICE_SCALE / 2)
        );

        assertEq(lendingAdapter.getCollateralInDebtAsset(), collateral / 2);
    }
}
