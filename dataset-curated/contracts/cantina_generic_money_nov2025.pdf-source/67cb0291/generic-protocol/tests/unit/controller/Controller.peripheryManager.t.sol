// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { PeripheryManager, ISwapper, IYieldDistributor } from "../../../src/controller/PeripheryManager.sol";

import { ControllerTest } from "./Controller.t.sol";

abstract contract Controller_PeripheryManager_Test is ControllerTest {
    address manager = makeAddr("manager");
    bytes32 managerRole;

    function setUp() public virtual override {
        super.setUp();

        managerRole = controller.PERIPHERY_MANAGER_ROLE();
        vm.prank(admin);
        controller.grantRole(managerRole, manager);
    }
}

contract Controller_PeripheryManager_SetSwapper_Test is Controller_PeripheryManager_Test {
    function testFuzz_shouldRevert_whenCallerNotManager(address caller) external {
        vm.assume(caller != manager);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        controller.setSwapper(swapper);
    }

    function testFuzz_shouldRevert_whenNewSwapperIsZero() external {
        vm.prank(manager);
        vm.expectRevert(PeripheryManager.Periphery_ZeroSwapper.selector);
        controller.setSwapper(ISwapper(address(0)));
    }

    function testFuzz_shouldUpdateSwapper(address newSwapper) external {
        vm.assume(newSwapper != address(0));

        vm.prank(manager);
        controller.setSwapper(ISwapper(newSwapper));

        assertEq(address(controller.swapper()), newSwapper);
    }

    function test_shouldEmit_SwapperUpdated() external {
        address newSwapper = makeAddr("newSwapper");

        vm.expectEmit();
        emit PeripheryManager.SwapperUpdated(address(swapper), newSwapper);

        vm.prank(manager);
        controller.setSwapper(ISwapper(newSwapper));
    }
}

contract Controller_PeripheryManager_SetYieldDistributor_Test is Controller_PeripheryManager_Test {
    function testFuzz_shouldRevert_whenCallerNotManager(address caller) external {
        vm.assume(caller != manager);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        controller.setYieldDistributor(yieldDistributor);
    }

    function testFuzz_shouldRevert_whenNewYieldDistributorIsZero() external {
        vm.prank(manager);
        vm.expectRevert(PeripheryManager.Periphery_ZeroYieldDistributor.selector);
        controller.setYieldDistributor(IYieldDistributor(address(0)));
    }

    function testFuzz_shouldUpdateYieldDistributor(address newYieldDistributor) external {
        vm.assume(newYieldDistributor != address(0));

        vm.prank(manager);
        controller.setYieldDistributor(IYieldDistributor(newYieldDistributor));

        assertEq(address(controller.yieldDistributor()), newYieldDistributor);
    }

    function test_shouldEmit_YieldDistributorUpdated() external {
        address newYieldDistributor = makeAddr("newYieldDistributor");

        vm.expectEmit();
        emit PeripheryManager.YieldDistributorUpdated(address(yieldDistributor), newYieldDistributor);

        vm.prank(manager);
        controller.setYieldDistributor(IYieldDistributor(newYieldDistributor));
    }
}
