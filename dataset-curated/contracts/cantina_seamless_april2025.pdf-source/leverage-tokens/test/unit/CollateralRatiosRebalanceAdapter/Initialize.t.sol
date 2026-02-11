// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";

// Dependency imports
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Internal imports
import {ICollateralRatiosRebalanceAdapter} from "src/interfaces/ICollateralRatiosRebalanceAdapter.sol";
import {CollateralRatiosRebalanceAdapterTest} from "./CollateralRatiosRebalanceAdapter.t.sol";
import {CollateralRatiosRebalanceAdapterHarness} from "test/unit/harness/CollateralRatiosRebalanceAdapterHarness.t.sol";
import {CollateralRatiosRebalanceAdapter} from "src/rebalance/CollateralRatiosRebalanceAdapter.sol";

contract InitializeTest is CollateralRatiosRebalanceAdapterTest {
    /// forge-config: default.fuzz.runs = 1
    function testFuzz_initialize(uint256 minCollateralRatio, uint256 targetCollateralRatio, uint256 maxCollateralRatio)
        public
    {
        vm.assume(minCollateralRatio <= targetCollateralRatio && targetCollateralRatio <= maxCollateralRatio);

        address rebalanceAdapterImplementation = address(new CollateralRatiosRebalanceAdapterHarness());
        address rebalanceAdapterProxy = UnsafeUpgrades.deployUUPSProxy(
            rebalanceAdapterImplementation,
            abi.encodeWithSelector(
                CollateralRatiosRebalanceAdapterHarness.initialize.selector,
                minCollateralRatio,
                targetCollateralRatio,
                maxCollateralRatio
            )
        );
        CollateralRatiosRebalanceAdapterHarness newModule =
            CollateralRatiosRebalanceAdapterHarness(rebalanceAdapterProxy);

        assertEq(newModule.getLeverageTokenMinCollateralRatio(), minCollateralRatio);
        assertEq(newModule.getLeverageTokenMaxCollateralRatio(), maxCollateralRatio);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_initialize_RevertIf_InvalidCollateralRatios(
        uint256 minCollateralRatio,
        uint256 targetCollateralRatio,
        uint256 maxCollateralRatio
    ) public {
        vm.assume(minCollateralRatio > targetCollateralRatio || targetCollateralRatio > maxCollateralRatio);

        address rebalanceAdapterImplementation = address(new CollateralRatiosRebalanceAdapterHarness());

        vm.expectRevert(ICollateralRatiosRebalanceAdapter.InvalidCollateralRatios.selector);
        UnsafeUpgrades.deployUUPSProxy(
            rebalanceAdapterImplementation,
            abi.encodeWithSelector(
                CollateralRatiosRebalanceAdapterHarness.initialize.selector,
                minCollateralRatio,
                targetCollateralRatio,
                maxCollateralRatio
            )
        );
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_initialize_RevertIf_AlreadyInitialized(
        uint256 minCollateralRatio,
        uint256 targetCollateralRatio,
        uint256 maxCollateralRatio
    ) public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        rebalanceAdapter.initialize(minCollateralRatio, targetCollateralRatio, maxCollateralRatio);
    }
}
