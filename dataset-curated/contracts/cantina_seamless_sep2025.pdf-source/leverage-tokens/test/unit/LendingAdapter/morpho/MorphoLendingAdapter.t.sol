// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {Id, MarketParams, IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IMorphoLendingAdapter} from "src/interfaces/IMorphoLendingAdapter.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockMorpho} from "../../mock/MockMorpho.sol";

contract MorphoLendingAdapterTest is Test {
    /// @dev Virtual shares used by Morpho for exchange rate computations. See Morpho's SharesMathLib for more details
    uint256 internal constant MORPHO_VIRTUAL_SHARES = 1e6;

    /// @dev Virtual assets used by Morpho for exchange rate computations. See Morpho's SharesMathLib for more details
    uint256 internal constant MORPHO_VIRTUAL_ASSETS = 1;

    address public authorizedCreator = makeAddr("authorizedCreator");

    MockMorpho public morpho;
    IMorphoLendingAdapter public lendingAdapter;

    MockERC20 public collateralToken = new MockERC20();
    MockERC20 public debtToken = new MockERC20();

    // Mocked ILeverageManager contract
    ILeverageManager public leverageManager = ILeverageManager(makeAddr("leverageManager"));

    // Mocked Morpho protocol is setup with a market with id 1 and some default market params
    Id public defaultMarketId;
    MarketParams public defaultMarketParams = MarketParams({
        loanToken: address(debtToken),
        collateralToken: address(collateralToken),
        oracle: makeAddr("mockMorphoMarketOracle"), // doesn't matter for these tests as calls to morpho should be mocked
        irm: makeAddr("mockMorphoIRM"), // doesn't matter for these tests as calls to morpho should be mocked
        lltv: 1e18 // 100%, doesn't matter for these tests as calls to morpho should be mocked
    });

    function setUp() public {
        defaultMarketId = MarketParamsLib.id(defaultMarketParams);

        morpho = new MockMorpho(defaultMarketId, defaultMarketParams);
        lendingAdapter = new MorphoLendingAdapter(leverageManager, IMorpho(address(morpho)));
        MorphoLendingAdapter(address(lendingAdapter)).initialize(defaultMarketId, authorizedCreator);

        vm.label(address(lendingAdapter), "lendingAdapter");
        vm.label(address(morpho), "morpho");
        vm.label(address(leverageManager), "leverageManager");
        vm.label(address(collateralToken), "collateralToken");
        vm.label(address(debtToken), "debtToken");
        vm.label(authorizedCreator, "authorizedCreator");
    }

    function test_setUp() public view {
        assertEq(address(lendingAdapter.leverageManager()), address(leverageManager));
        assertEq(address(lendingAdapter.morpho()), address(morpho));
        assertEq(address(lendingAdapter.getCollateralAsset()), address(collateralToken));
        assertEq(address(lendingAdapter.getDebtAsset()), address(debtToken));
        assertEq(lendingAdapter.authorizedCreator(), authorizedCreator);
    }
}
