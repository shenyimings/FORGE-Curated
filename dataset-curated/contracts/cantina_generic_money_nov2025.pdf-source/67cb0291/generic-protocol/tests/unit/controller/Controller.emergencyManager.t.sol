// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { EmergencyManager } from "../../../src/controller/EmergencyManager.sol";

import { ControllerTest } from "./Controller.t.sol";

abstract contract Controller_EmergencyManager_Test is ControllerTest {
    address manager = makeAddr("manager");
    bytes32 managerRole;

    function setUp() public virtual override {
        super.setUp();

        managerRole = controller.EMERGENCY_MANAGER_ROLE();
        vm.prank(admin);
        controller.grantRole(managerRole, manager);
    }
}

contract Controller_EmergencyManager_Pause_Test is Controller_EmergencyManager_Test {
    function test_shouldRevert_whenCallerNotManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, makeAddr("notManager"), managerRole
            )
        );
        vm.prank(makeAddr("notManager"));
        controller.pause();
    }

    function test_shouldRevert_whenPaused() public {
        controller.workaround_setPaused(true);

        vm.expectRevert(EmergencyManager.EmergencyManager_AlreadyPaused.selector);
        vm.prank(manager);
        controller.pause();
    }

    function test_shouldPauseController() public {
        assertFalse(controller.paused());

        vm.prank(manager);
        controller.pause();

        assertTrue(controller.paused());
    }

    function test_shouldEmit_Paused() public {
        vm.expectEmit();
        emit EmergencyManager.Paused();

        vm.prank(manager);
        controller.pause();
    }
}

contract Controller_EmergencyManager_Unpause_Test is Controller_EmergencyManager_Test {
    function test_shouldRevert_whenCallerNotManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, makeAddr("notManager"), managerRole
            )
        );
        vm.prank(makeAddr("notManager"));
        controller.unpause();
    }

    function test_shouldRevert_whenNotPaused() public {
        controller.workaround_setPaused(false);

        vm.expectRevert(EmergencyManager.EmergencyManager_NotPaused.selector);
        vm.prank(manager);
        controller.unpause();
    }

    function test_shouldUnpauseController() public {
        controller.workaround_setPaused(true);

        assertTrue(controller.paused());

        vm.prank(manager);
        controller.unpause();

        assertFalse(controller.paused());
    }

    function test_shouldEmit_Unpaused() public {
        controller.workaround_setPaused(true);

        vm.expectEmit();
        emit EmergencyManager.Unpaused();

        vm.prank(manager);
        controller.unpause();
    }
}

contract Controller_EmergencyManager_AllowSkipNextRebalanceSafetyBufferCheck_Test is Controller_EmergencyManager_Test {
    function test_shouldRevert_whenCallerNotManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, makeAddr("notManager"), managerRole
            )
        );
        vm.prank(makeAddr("notManager"));
        controller.allowSkipNextRebalanceSafetyBufferCheck();
    }

    function test_shouldRevert_whenNextRebalanceSafetyBufferCheckAlreadyAllowed() public {
        controller.workaround_setSkipNextRebalanceSafetyBufferCheck(true);

        vm.expectRevert(EmergencyManager.EmergencyManager_AlreadyAllowedToSkipNextRebalanceSafetyBufferCheck.selector);
        vm.prank(manager);
        controller.allowSkipNextRebalanceSafetyBufferCheck();
    }

    function test_shouldAllowSkipNextRebalanceSafetyBufferCheck() public {
        assertFalse(controller.skipNextRebalanceSafetyBufferCheck());

        vm.prank(manager);
        controller.allowSkipNextRebalanceSafetyBufferCheck();

        assertTrue(controller.skipNextRebalanceSafetyBufferCheck());
    }

    function test_shouldEmit_SkipNextRebalanceSafetyBufferCheckAllowed() public {
        vm.expectEmit();
        emit EmergencyManager.SkipNextRebalanceSafetyBufferCheckAllowed();

        vm.prank(manager);
        controller.allowSkipNextRebalanceSafetyBufferCheck();
    }
}
