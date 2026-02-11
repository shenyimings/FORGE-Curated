// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { BaseTest } from "test/utils/BaseTest.t.sol";

import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";

contract StrategyRegistryTest is BaseTest {
    StrategyRegistry public strategyRegistry;
    address public admin;
    address public assetRegistry;

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        vm.startPrank(admin);

        assetRegistry = createUser("assetRegistry");
        strategyRegistry = new StrategyRegistry(admin);
        vm.stopPrank();
    }

    function testFuzz_constructor(address admin_) public {
        StrategyRegistry strategyRegistry_ = new StrategyRegistry(admin_);
        assertTrue(
            strategyRegistry_.hasRole(strategyRegistry_.DEFAULT_ADMIN_ROLE(), admin_),
            "Admin should have default admin role"
        );
    }

    function testFuzz_grantRole_WeightStrategy(address strategy) public {
        vm.prank(admin);
        strategyRegistry.grantRole(_WEIGHT_STRATEGY_ROLE, strategy);
        assertTrue(strategyRegistry.hasRole(_WEIGHT_STRATEGY_ROLE, strategy));
    }

    function testFuzz_supportsBitFlag(uint256 bitFlag, string memory strategyName) public {
        address strategy = createUser(strategyName);
        testFuzz_grantRole_WeightStrategy(strategy);

        vm.expectCall(strategy, abi.encodeWithSelector(WeightStrategy.supportsBitFlag.selector, bitFlag));
        vm.mockCall(
            strategy, abi.encodeWithSelector(WeightStrategy.supportsBitFlag.selector, bitFlag), abi.encode(true)
        );
        strategyRegistry.supportsBitFlag(bitFlag, strategy);
    }

    function testFuzz_supportsBitFlag_StrategyNotSupported(uint256 bitFlag, address strategy) public {
        vm.expectRevert(StrategyRegistry.StrategyNotSupported.selector);
        strategyRegistry.supportsBitFlag(bitFlag, strategy);
    }
}
