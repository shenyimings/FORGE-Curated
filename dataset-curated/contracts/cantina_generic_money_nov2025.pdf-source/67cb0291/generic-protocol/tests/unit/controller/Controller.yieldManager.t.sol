// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { YieldManager } from "../../../src/controller/YieldManager.sol";
import { IERC20Mintable } from "../../../src/interfaces/IERC20Mintable.sol";

import { ControllerTest } from "./Controller.t.sol";
import { ReentrancySpy } from "../../helper/ReentrancySpy.sol";

abstract contract Controller_YieldManager_Test is ControllerTest {
    address manager = makeAddr("manager");
    bytes32 managerRole;

    function setUp() public virtual override {
        super.setUp();

        managerRole = controller.YIELD_MANAGER_ROLE();
        vm.prank(admin);
        controller.grantRole(managerRole, manager);
    }
}

contract Controller_YieldManager_DistributeYield_Test is Controller_YieldManager_Test {
    function setUp() public virtual override {
        super.setUp();

        // Yield is 10e18
        _mockVault(makeAddr("vault1"), makeAddr("asset1"), 100e18, makeAddr("feed1"), 1.1e8, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));
    }

    function testFuzz_shouldRevert_whenCallerNotManager(address caller) public {
        vm.assume(caller != manager);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        controller.distributeYield();
    }

    function testFuzz_shouldRevert_whenRedemptionPriceNotOne(uint256 totalShares) public {
        totalShares = bound(totalShares, 110e18 + 1, type(uint256).max);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(totalShares));

        vm.expectRevert(abi.encodeWithSelector(YieldManager.Yield_DistributionPaused.selector));
        vm.prank(manager);
        controller.distributeYield();
    }

    function test_shouldRevert_whenSafetyBufferExceedsYield() public {
        controller.workaround_setSafetyBufferYieldDeduction(11e18);

        vm.expectRevert(abi.encodeWithSelector(YieldManager.Yield_ExcessiveSafetyBuffer.selector));
        vm.prank(manager);
        controller.distributeYield();
    }

    function test_shouldKeepSafetyBufferYieldDeductionUndistributed() public {
        controller.workaround_setSafetyBufferYieldDeduction(1e18);

        vm.prank(manager);
        uint256 yield = controller.distributeYield();

        assertEq(yield, 10e18 - 1e18);
    }

    function test_shouldDistributeYield() public {
        vm.expectCall(
            address(share),
            abi.encodeWithSelector(IERC20Mintable.mint.selector, address(yieldDistributor), 10e18) // full yield
        );

        vm.prank(manager);
        uint256 yield = controller.distributeYield();

        assertEq(yield, 10e18);
    }

    function test_shouldEmit_YieldDistributed() public {
        vm.expectEmit();
        emit YieldManager.YieldDistributed(address(yieldDistributor), 10e18);

        vm.prank(manager);
        controller.distributeYield();
    }

    function testFuzz_shouldDistributeYield(uint256 safetyBufferYieldDeduction) public {
        safetyBufferYieldDeduction = bound(safetyBufferYieldDeduction, 0, 3e18);

        controller.workaround_setSafetyBufferYieldDeduction(safetyBufferYieldDeduction);
        uint256 expectedYield = 10e18 - safetyBufferYieldDeduction;

        vm.prank(manager);
        uint256 _yield = controller.distributeYield();

        assertEq(_yield, expectedYield);
    }

    function test_shouldRevert_whenReentrant() public {
        ReentrancySpy spy = new ReentrancySpy();

        vm.mockFunction(address(share), address(spy), abi.encodeWithSelector(ReentrancySpy.reenter.selector));
        vm.mockFunction(address(share), address(spy), abi.encodeWithSelector(IERC20Mintable.mint.selector));
        ReentrancySpy(address(share))
            .reenter(address(controller), abi.encodeWithSelector(YieldManager.distributeYield.selector, 0));

        vm.expectRevert(ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector);
        vm.prank(manager);
        controller.distributeYield();
    }
}
