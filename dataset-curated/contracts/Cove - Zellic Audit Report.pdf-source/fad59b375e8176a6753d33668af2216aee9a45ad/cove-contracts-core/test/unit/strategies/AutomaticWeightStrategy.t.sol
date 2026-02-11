// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { BaseTest } from "test/utils/BaseTest.t.sol";

import { AutomaticWeightStrategy } from "src/strategies/AutomaticWeightStrategy.sol";

contract AutomaticWeightStrategyTest is BaseTest {
    AutomaticWeightStrategy public automaticWeightStrategy;
    address public admin;

    function setUp() public override {
        super.setUp();
        admin = createUser("admin");
        vm.prank(admin);
        automaticWeightStrategy = new AutomaticWeightStrategy(admin);
    }

    function testFuzz_constructor(address admin_) public {
        AutomaticWeightStrategy automaticWeightStrategy_ = new AutomaticWeightStrategy(admin_);
        assertTrue(
            automaticWeightStrategy_.hasRole(automaticWeightStrategy_.DEFAULT_ADMIN_ROLE(), admin_),
            "Admin should have default admin role"
        );
    }

    // TODO: Implement tests for the following functions
    // function getTargetWeights(uint256 bitFlag) public view override returns (uint256[] memory) { }
    // function supportsBitFlag(uint256 bitFlag) public view override returns (bool) { }
    function testFuzz_getTargetWeights(uint256 bitFlag) public {
        uint64[] memory targetWeights = automaticWeightStrategy.getTargetWeights(bitFlag);
        assertTrue(targetWeights.length == 0, "Not implemented");
    }

    function testFuzz_supportsBitFlag(uint256 bitFlag) public {
        assertTrue(!automaticWeightStrategy.supportsBitFlag(bitFlag), "Not implemented");
    }
}
