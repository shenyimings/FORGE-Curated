// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// Internal imports
import {BeaconProxyFactory} from "src/BeaconProxyFactory.sol";
import {LeverageManager} from "src/LeverageManager.sol";
import {LeverageRouter} from "src/periphery/LeverageRouter.sol";
import {LeverageToken} from "src/LeverageToken.sol";
import {SwapAdapter} from "src/periphery/SwapAdapter.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILeverageRouter} from "src/interfaces/periphery/ILeverageRouter.sol";
import {ISwapAdapter} from "src/interfaces/periphery/ISwapAdapter.sol";
import {IntegrationTestBase} from "../IntegrationTestBase.t.sol";

contract LeverageRouterTest is IntegrationTestBase {
    address public constant AERODROME_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address public constant AERODROME_SLIPSTREAM_ROUTER = 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5;
    address public constant AERODROME_POOL_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    address public constant UNISWAP_V2_ROUTER02 = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address public constant UNISWAP_SWAP_ROUTER02 = 0x2626664c2603336E57B271c5C0b26F421741e481;

    address public constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    address public constant cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    ILeverageRouter public leverageRouter;
    ISwapAdapter public swapAdapter;

    function setUp() public virtual override {
        super.setUp();

        swapAdapter = new SwapAdapter();
        leverageRouter = new LeverageRouter(leverageManager, MORPHO, swapAdapter);

        vm.label(address(leverageRouter), "leverageRouter");
        vm.label(address(swapAdapter), "swapAdapter");
    }

    function testFork_setUp() public view virtual override {
        assertEq(address(leverageManager.getLeverageTokenCollateralAsset(leverageToken)), address(WETH));
        assertEq(address(leverageManager.getLeverageTokenDebtAsset(leverageToken)), address(USDC));

        assertEq(address(leverageRouter.leverageManager()), address(leverageManager));
        assertEq(address(leverageRouter.morpho()), address(MORPHO));
        assertEq(address(leverageRouter.swapper()), address(swapAdapter));
    }

    function _dealAndDeposit(
        IERC20 collateralAsset,
        IERC20 debtAsset,
        uint256 dealAmount,
        uint256 equityInCollateralAsset,
        uint256 maxSwapCostInCollateralAsset,
        ISwapAdapter.SwapContext memory swapContext
    ) internal {
        deal(address(collateralAsset), user, dealAmount);

        vm.startPrank(user);
        collateralAsset.approve(address(leverageRouter), equityInCollateralAsset + maxSwapCostInCollateralAsset);
        leverageRouter.deposit(leverageToken, equityInCollateralAsset, 0, maxSwapCostInCollateralAsset, swapContext);
        vm.stopPrank();

        // No leftover assets in the LeverageRouter or the SwapAdapter
        assertEq(collateralAsset.balanceOf(address(leverageRouter)), 0);
        assertEq(collateralAsset.balanceOf(address(swapAdapter)), 0);
        assertEq(debtAsset.balanceOf(address(leverageRouter)), 0);
        assertEq(debtAsset.balanceOf(address(swapAdapter)), 0);
    }
}
