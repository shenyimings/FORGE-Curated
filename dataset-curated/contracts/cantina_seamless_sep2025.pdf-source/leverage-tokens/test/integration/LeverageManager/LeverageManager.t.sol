// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";

// Internal imports
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {LeverageManager} from "src/LeverageManager.sol";
import {BeaconProxyFactory} from "src/BeaconProxyFactory.sol";
import {LeverageToken} from "src/LeverageToken.sol";
import {LeverageManagerHarness} from "test/unit/harness/LeverageManagerHarness.t.sol";
import {MorphoLendingAdapterTest} from "../MorphoLendingAdapter.t.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {IntegrationTestBase} from "../IntegrationTestBase.t.sol";
import {LeverageTokenState, ActionData} from "src/types/DataTypes.sol";

contract LeverageManagerTest is IntegrationTestBase {
    function testFork_setUp() public view virtual override {
        assertEq(address(leverageManager.getLeverageTokenCollateralAsset(leverageToken)), address(WETH));
        assertEq(address(leverageManager.getLeverageTokenDebtAsset(leverageToken)), address(USDC));
    }

    function _deposit(address caller, uint256 collateralToDeposit, uint256 minShares)
        internal
        returns (ActionData memory)
    {
        deal(address(WETH), caller, collateralToDeposit);
        vm.startPrank(caller);
        WETH.approve(address(leverageManager), collateralToDeposit);
        ActionData memory depositData = leverageManager.deposit(leverageToken, collateralToDeposit, minShares);
        vm.stopPrank();

        return depositData;
    }

    function _mint(address caller, uint256 sharesToMint, uint256 maxCollateral) internal returns (ActionData memory) {
        deal(address(WETH), caller, maxCollateral);
        vm.startPrank(caller);
        WETH.approve(address(leverageManager), maxCollateral);
        ActionData memory mintData = leverageManager.mint(leverageToken, sharesToMint, maxCollateral);
        vm.stopPrank();

        return mintData;
    }

    function _redeem(address caller, uint256 shares, uint256 minCollateral, uint256 debtToRepay) internal {
        deal(address(USDC), caller, debtToRepay);
        vm.startPrank(caller);
        USDC.approve(address(leverageManager), debtToRepay);
        leverageManager.redeem(leverageToken, shares, minCollateral);
        vm.stopPrank();
    }

    function _withdraw(address caller, uint256 collateral, uint256 maxShares, uint256 debtToRepay) internal {
        deal(address(USDC), caller, debtToRepay);
        vm.startPrank(caller);
        USDC.approve(address(leverageManager), debtToRepay);
        leverageManager.withdraw(leverageToken, collateral, maxShares);
        vm.stopPrank();
    }

    function getLeverageTokenState() internal view returns (LeverageTokenState memory) {
        return LeverageManagerHarness(address(leverageManager)).getLeverageTokenState(leverageToken);
    }
}
