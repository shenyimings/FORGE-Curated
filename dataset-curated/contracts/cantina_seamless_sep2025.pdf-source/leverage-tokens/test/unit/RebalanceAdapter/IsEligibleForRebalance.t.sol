// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {RebalanceAdapterTest} from "./RebalanceAdapter.t.sol";
import {CollateralRatiosRebalanceAdapterHarness} from "test/unit/harness/CollateralRatiosRebalanceAdapterHarness.t.sol";
import {PreLiquidationRebalanceAdapterHarness} from "test/unit/harness/PreLiquidationRebalanceAdapterHarness.t.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";

contract IsEligibleForRebalanceTest is RebalanceAdapterTest {
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

    function testFuzz_isEligibleForRebalance_ReturnsTheSameAsPreLiquidationRebalanceAdapter_IfDutchAuctionReturnsFalse(
        address caller,
        LeverageTokenState memory stateBefore,
        LeverageTokenState memory stateAfter
    ) public {
        vm.assume(caller != address(rebalanceAdapter));

        _mockLeverageTokenState(stateAfter);

        bool isEligible = rebalanceAdapter.isEligibleForRebalance(leverageToken, stateBefore, caller);
        bool expectedIsEligible =
            preLiquidationRebalanceAdapter.isEligibleForRebalance(leverageToken, stateBefore, caller);
        assertEq(isEligible, expectedIsEligible);
    }

    function testFuzz_isEligibleForRebalance_ReturnsSameAsCollateralRatiosRebalanceAdapter(
        LeverageTokenState memory stateBefore,
        LeverageTokenState memory stateAfter,
        uint256 totalSupplyBefore
    ) public {
        vm.assume(stateBefore.collateralInDebtAsset != 0);
        vm.assume(stateBefore.collateralRatio >= 1.3e8);

        _mockLeverageTokenState(stateAfter);
        vm.mockCall(
            address(leverageToken), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(totalSupplyBefore)
        );

        bool isEligible = rebalanceAdapter.isEligibleForRebalance(leverageToken, stateBefore, address(rebalanceAdapter));
        bool expectedIsEligible = collateralRatiosRebalanceAdapter.isEligibleForRebalance(
            leverageToken, stateBefore, address(rebalanceAdapter)
        );
        assertEq(isEligible, expectedIsEligible);
    }
}
