// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";

// Internal imports
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IPreLiquidationLendingAdapter} from "src/interfaces/IPreLiquidationLendingAdapter.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {PreLiquidationRebalanceAdapter} from "src/rebalance/PreLiquidationRebalanceAdapter.sol";
import {PreLiquidationRebalanceAdapterHarness} from "../harness/PreLiquidationRebalanceAdapterHarness.t.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";

contract PreLiquidationRebalanceAdapterTest is Test {
    address public leverageManager = makeAddr("leverageManager");
    ILendingAdapter public lendingAdapter = ILendingAdapter(makeAddr("lendingAdapter"));
    ILeverageToken public leverageToken = ILeverageToken(makeAddr("leverageToken"));
    PreLiquidationRebalanceAdapterHarness public adapter;

    function setUp() public {
        // Deploy the adapter implementation
        address adapterImplementation = address(new PreLiquidationRebalanceAdapterHarness());

        // Deploy the adapter proxy with health factor threshold 1.1 and rebalance reward 50%
        address adapterProxy = UnsafeUpgrades.deployUUPSProxy(
            adapterImplementation,
            abi.encodeWithSelector(PreLiquidationRebalanceAdapterHarness.initialize.selector, 1.1e18, 50_00)
        );

        // Initialize the adapter
        adapter = PreLiquidationRebalanceAdapterHarness(adapterProxy);

        // Set the leverage manager
        adapter.setLeverageManager(ILeverageManager(leverageManager));

        vm.mockCall(
            address(leverageManager),
            abi.encodeWithSelector(ILeverageManager.getLeverageTokenLendingAdapter.selector, leverageToken),
            abi.encode(lendingAdapter)
        );
    }

    function test_setUp() public view {
        assertEq(adapter.getCollateralRatioThreshold(), 1.1e18);
        assertEq(adapter.getRebalanceReward(), 50_00);
        assertEq(address(adapter.getLeverageManager()), leverageManager);

        bytes32 expectedSlot = keccak256(
            abi.encode(uint256(keccak256("seamless.contracts.storage.PreLiquidationRebalanceAdapter")) - 1)
        ) & ~bytes32(uint256(0xff));
        assertEq(adapter.exposed_getPreLiquidationRebalanceAdapterStorageSlot(), expectedSlot);
    }

    function _mockLiquidationPenaltyEquityAndDebt(uint256 liquidationPenalty, uint256 equity, uint256 debt) internal {
        vm.mockCall(
            address(lendingAdapter),
            abi.encodeWithSelector(IPreLiquidationLendingAdapter.getLiquidationPenalty.selector),
            abi.encode(liquidationPenalty)
        );

        LeverageTokenState memory stateBefore =
            LeverageTokenState({collateralRatio: 0, collateralInDebtAsset: 0, debt: debt, equity: equity});

        vm.mockCall(
            address(leverageManager),
            abi.encodeWithSelector(ILeverageManager.getLeverageTokenState.selector, leverageToken),
            abi.encode(stateBefore)
        );
    }
}
