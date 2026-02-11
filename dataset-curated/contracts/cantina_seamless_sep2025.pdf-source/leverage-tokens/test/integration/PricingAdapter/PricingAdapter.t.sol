// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {IAggregatorV2V3Interface} from "src/interfaces/periphery/IAggregatorV2V3Interface.sol";
import {IPricingAdapter} from "src/interfaces/periphery/IPricingAdapter.sol";
import {PricingAdapter} from "src/periphery/PricingAdapter.sol";
import {LeverageManagerTest} from "../LeverageManager/LeverageManager.t.sol";

contract PricingAdapterTest is LeverageManagerTest {
    IPricingAdapter public pricingAdapter;

    IAggregatorV2V3Interface public constant WETH_USD_ORACLE =
        IAggregatorV2V3Interface(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70);
    IAggregatorV2V3Interface public constant USDC_USD_ORACLE =
        IAggregatorV2V3Interface(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B);

    function setUp() public virtual override {
        super.setUp();

        pricingAdapter = new PricingAdapter(leverageManager);
    }

    function testFork_setUp() public view virtual override {
        assertEq(address(pricingAdapter.leverageManager()), address(leverageManager));
    }
}
