// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";

import {RebalanceAdapterTest} from "./RebalanceAdapter.t.sol";
import {CollateralRatiosRebalanceAdapterHarness} from "test/unit/harness/CollateralRatiosRebalanceAdapterHarness.t.sol";
import {PreLiquidationRebalanceAdapterHarness} from "test/unit/harness/PreLiquidationRebalanceAdapterHarness.t.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";
import {IPreLiquidationLendingAdapter} from "src/interfaces/IPreLiquidationLendingAdapter.sol";

contract IsStateAfterRebalanceValidTest is RebalanceAdapterTest {
    CollateralRatiosRebalanceAdapterHarness public collateralRatiosRebalanceAdapter;
    PreLiquidationRebalanceAdapterHarness public preLiquidationRebalanceAdapter;

    function setUp() public override {
        super.setUp();

        CollateralRatiosRebalanceAdapterHarness collateralRatiosRebalanceAdapterHarness =
            new CollateralRatiosRebalanceAdapterHarness();
        address collateralRatiosRebalanceAdapterProxy = UnsafeUpgrades.deployUUPSProxy(
            address(collateralRatiosRebalanceAdapterHarness),
            abi.encodeWithSelector(
                CollateralRatiosRebalanceAdapterHarness.initialize.selector,
                minCollateralRatio,
                targetCollateralRatio,
                maxCollateralRatio
            )
        );

        PreLiquidationRebalanceAdapterHarness preLiquidationRebalanceAdapterHarness =
            new PreLiquidationRebalanceAdapterHarness();
        address preLiquidationRebalanceAdapterProxy = UnsafeUpgrades.deployUUPSProxy(
            address(preLiquidationRebalanceAdapterHarness),
            abi.encodeWithSelector(
                PreLiquidationRebalanceAdapterHarness.initialize.selector, collateralRatioThreshold, rebalanceReward
            )
        );

        collateralRatiosRebalanceAdapter =
            CollateralRatiosRebalanceAdapterHarness(collateralRatiosRebalanceAdapterProxy);
        preLiquidationRebalanceAdapter = PreLiquidationRebalanceAdapterHarness(preLiquidationRebalanceAdapterProxy);

        preLiquidationRebalanceAdapter.setLeverageManager(leverageManager);
        collateralRatiosRebalanceAdapter.mock_setLeverageManager(leverageManager);
    }

    function test_isStateAfterRebalanceValid_ReturnsTrue_PreLiquidationRebalanceAdapter() public {
        address lendingAdapter = makeAddr("lendingAdapter");

        vm.mockCall(
            address(leverageManager),
            abi.encodeWithSelector(ILeverageManager.getLeverageTokenLendingAdapter.selector, leverageToken),
            abi.encode(lendingAdapter)
        );
        vm.mockCall(
            address(lendingAdapter),
            abi.encodeWithSelector(IPreLiquidationLendingAdapter.getLiquidationPenalty.selector),
            abi.encode(0.05e18)
        );

        LeverageTokenState memory stateBefore =
            LeverageTokenState({debt: 200e18, equity: 100e18, collateralInDebtAsset: 0, collateralRatio: 1.3e8 - 1});
        LeverageTokenState memory stateAfter =
            LeverageTokenState({debt: 100e18, equity: 98e18, collateralInDebtAsset: 0, collateralRatio: 1.3e8});

        _mockLeverageTokenState(stateAfter);

        bool isValid = rebalanceAdapter.isStateAfterRebalanceValid(leverageToken, stateBefore);
        assertEq(isValid, true);
    }
}
