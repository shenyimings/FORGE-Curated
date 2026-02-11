// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {IMorpho, Id, MarketParams} from "@morpho-blue/interfaces/IMorpho.sol";

// Internal imports
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IMorphoLendingAdapter} from "src/interfaces/IMorphoLendingAdapter.sol";
import {IMorphoLendingAdapterFactory} from "src/interfaces/IMorphoLendingAdapterFactory.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {MorphoLendingAdapterFactory} from "src/lending/MorphoLendingAdapterFactory.sol";
import {MockMorpho} from "../../mock/MockMorpho.sol";
import {MockERC20} from "../../mock/MockERC20.sol";

contract MorphoLendingAdapterFactoryTest is Test {
    IMorphoLendingAdapter public lendingAdapterLogic;

    IMorphoLendingAdapterFactory public factory;

    ILeverageManager public leverageManager = ILeverageManager(makeAddr("leverageManager"));
    MockMorpho public morpho;

    MockERC20 public collateralToken = new MockERC20();
    MockERC20 public debtToken = new MockERC20();

    // Mocked Morpho protocol is setup with a market with id 1 and some default market params
    Id public defaultMarketId;
    MarketParams public defaultMarketParams = MarketParams({
        loanToken: address(debtToken),
        collateralToken: address(collateralToken),
        oracle: makeAddr("mockMorphoMarketOracle"), // doesn't matter for these tests as calls to morpho should be mocked
        irm: makeAddr("mockMorphoIRM"), // doesn't matter for these tests as calls to morpho should be mocked
        lltv: 1e18 // 100%, doesn't matter for these tests as calls to morpho should be mocked
    });

    function setUp() public virtual {
        morpho = new MockMorpho(defaultMarketId, defaultMarketParams);
        lendingAdapterLogic = new MorphoLendingAdapter(leverageManager, IMorpho(address(morpho)));
        factory = new MorphoLendingAdapterFactory(lendingAdapterLogic);
    }
}
