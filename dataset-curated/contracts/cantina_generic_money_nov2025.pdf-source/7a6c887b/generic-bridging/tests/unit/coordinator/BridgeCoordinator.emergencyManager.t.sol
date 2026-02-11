// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { BridgeCoordinatorTest } from "./BridgeCoordinator.t.sol";

abstract contract BridgeCoordinator_EmergencyManager_Test is BridgeCoordinatorTest {
    address manager = makeAddr("manager");
    bytes32 managerRole;

    function setUp() public virtual override {
        super.setUp();

        managerRole = coordinator.EMERGENCY_MANAGER_ROLE();
        vm.prank(admin);
        coordinator.grantRole(managerRole, manager);
    }
}

contract BridgeCoordinator_EmergencyManager_ForceRemoveLocalBridgeAdapter_Test is
    BridgeCoordinator_EmergencyManager_Test
{
    function test_shouldRevert_whenCallerNotEmergencyRole() public {
        address caller = makeAddr("notEmergency");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.forceRemoveLocalBridgeAdapter(bridgeType, localAdapter);
    }

    function test_shouldRemoveLocalAdapter_whenOutbound() public {
        assertEq(address(coordinator.outboundLocalBridgeAdapter(bridgeType)), localAdapter);
        assertTrue(coordinator.isLocalBridgeAdapter(bridgeType, localAdapter));

        vm.prank(manager);
        coordinator.forceRemoveLocalBridgeAdapter(bridgeType, localAdapter);

        assertEq(address(coordinator.outboundLocalBridgeAdapter(bridgeType)), address(0));
        assertFalse(coordinator.isLocalBridgeAdapter(bridgeType, localAdapter));
    }

    function test_shouldRemoveLocalAdapter_whenNotOutbound() public {
        address outbound = makeAddr("outboundLocalAdapter");
        coordinator.workaround_setOutboundLocalBridgeAdapter(bridgeType, outbound);

        assertEq(address(coordinator.outboundLocalBridgeAdapter(bridgeType)), outbound);
        assertTrue(coordinator.isLocalBridgeAdapter(bridgeType, localAdapter));

        vm.prank(manager);
        coordinator.forceRemoveLocalBridgeAdapter(bridgeType, localAdapter);

        assertEq(address(coordinator.outboundLocalBridgeAdapter(bridgeType)), outbound);
        assertFalse(coordinator.isLocalBridgeAdapter(bridgeType, localAdapter));
    }
}

contract BridgeCoordinator_EmergencyManager_ForceRemoveRemoteBridgeAdapter_Test is
    BridgeCoordinator_EmergencyManager_Test
{
    function test_shouldRevert_whenCallerNotEmergencyRole() public {
        address caller = makeAddr("notEmergency");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.forceRemoveRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter);
    }

    function test_shouldRemoveRemoteAdapter_whenOutbound() public {
        assertEq(coordinator.outboundRemoteBridgeAdapter(bridgeType, remoteChainId), remoteAdapter);
        assertTrue(coordinator.isRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter));

        vm.prank(manager);
        coordinator.forceRemoveRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter);

        assertEq(coordinator.outboundRemoteBridgeAdapter(bridgeType, remoteChainId), bytes32(0));
        assertFalse(coordinator.isRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter));
    }

    function test_shouldRemoveRemoteAdapter_whenNotOutbound() public {
        bytes32 outbound = bytes32(uint256(uint160(makeAddr("outboundRemoteAdapter"))));
        coordinator.workaround_setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, outbound);

        assertEq(coordinator.outboundRemoteBridgeAdapter(bridgeType, remoteChainId), outbound);
        assertTrue(coordinator.isRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter));

        vm.prank(manager);
        coordinator.forceRemoveRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter);

        assertEq(coordinator.outboundRemoteBridgeAdapter(bridgeType, remoteChainId), outbound);
        assertFalse(coordinator.isRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter));
    }
}
