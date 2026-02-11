// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {LeverageRouter} from "src/periphery/LeverageRouter.sol";
import {ILeverageRouter} from "src/interfaces/periphery/ILeverageRouter.sol";
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

    function setUp() public virtual override {
        super.setUp();

        leverageRouter = new LeverageRouter(leverageManager, MORPHO);

        vm.label(address(leverageRouter), "leverageRouter");
    }

    function testFork_setUp() public view virtual override {
        assertEq(address(leverageManager.getLeverageTokenCollateralAsset(leverageToken)), address(WETH));
        assertEq(address(leverageManager.getLeverageTokenDebtAsset(leverageToken)), address(USDC));

        assertEq(address(leverageRouter.leverageManager()), address(leverageManager));
        assertEq(address(leverageRouter.morpho()), address(MORPHO));
    }

    function _dealAndDeposit(
        IERC20 collateralAsset,
        IERC20 debtAsset,
        uint256 dealAmount,
        uint256 collateralFromSender,
        uint256 flashLoanAmount,
        uint256 minShares,
        ILeverageRouter.Call[] memory calls
    ) internal {
        deal(address(collateralAsset), user, dealAmount);

        vm.startPrank(user);
        collateralAsset.approve(address(leverageRouter), collateralFromSender);
        leverageRouter.deposit(leverageToken, collateralFromSender, flashLoanAmount, minShares, calls);
        vm.stopPrank();

        // No leftover assets in the LeverageRouter
        assertEq(collateralAsset.balanceOf(address(leverageRouter)), 0, "no collateral left in LeverageRouter");
        assertEq(debtAsset.balanceOf(address(leverageRouter)), 0, "no debt left in LeverageRouter");
    }

    function _deployLeverageRouterIntegrationTestContracts() internal {
        _deployIntegrationTestContracts();

        leverageRouter = new LeverageRouter(leverageManager, MORPHO);

        vm.label(address(leverageRouter), "leverageRouter");
    }
}
