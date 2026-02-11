// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { AdapterManager, IBridgeAdapter } from "../../../src/coordinator/BridgeCoordinator.sol";

import { BridgeCoordinatorTest } from "./BridgeCoordinator.t.sol";

abstract contract BridgeCoordinator_AdapterManager_Test is BridgeCoordinatorTest {
    address manager = makeAddr("manager");
    bytes32 managerRole;

    function setUp() public virtual override {
        super.setUp();

        managerRole = coordinator.ADAPTER_MANAGER_ROLE();
        vm.prank(admin);
        coordinator.grantRole(managerRole, manager);
    }
}

contract BridgeCoordinator_AdapterManager_SetIsLocalBridgeAdapter_Test is BridgeCoordinator_AdapterManager_Test {
    address newAdapter = makeAddr("newAdapter");

    function setUp() public override {
        super.setUp();

        vm.mockCall(
            newAdapter,
            abi.encodeWithSelector(IBridgeAdapter.bridgeCoordinator.selector),
            abi.encode(address(coordinator))
        );
        vm.mockCall(newAdapter, abi.encodeWithSelector(IBridgeAdapter.bridgeType.selector), abi.encode(bridgeType));
    }

    function test_shouldRevert_whenCallerNotManager() public {
        address caller = makeAddr("notManager");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.setIsLocalBridgeAdapter(bridgeType, IBridgeAdapter(newAdapter), true);
    }

    function testFuzz_shouldRevert_whenCoordinatorMismatch_whenAdding(address notCoordinator) public {
        vm.assume(notCoordinator != address(coordinator));

        vm.mockCall(
            newAdapter, abi.encodeWithSelector(IBridgeAdapter.bridgeCoordinator.selector), abi.encode(notCoordinator)
        );

        vm.expectRevert(AdapterManager.CoordinatorMismatch.selector);
        vm.prank(manager);
        coordinator.setIsLocalBridgeAdapter(bridgeType, IBridgeAdapter(newAdapter), true);
    }

    function testFuzz_shouldRevert_whenBridgeTypeMismatch_whenAdding(uint16 badBridgeType) public {
        vm.assume(badBridgeType != bridgeType);

        vm.mockCall(newAdapter, abi.encodeWithSelector(IBridgeAdapter.bridgeType.selector), abi.encode(badBridgeType));

        vm.expectRevert(AdapterManager.BridgeTypeMismatch.selector);
        vm.prank(manager);
        coordinator.setIsLocalBridgeAdapter(bridgeType, IBridgeAdapter(newAdapter), true);
    }

    function test_shouldRevert_whenOutboundAdapter_whenRemoving() public {
        coordinator.workaround_setOutboundLocalBridgeAdapter(bridgeType, newAdapter);

        vm.expectRevert(AdapterManager.IsOutboundAdapter.selector);
        vm.prank(manager);
        coordinator.setIsLocalBridgeAdapter(bridgeType, IBridgeAdapter(newAdapter), false);
    }

    function testFuzz_shouldSetNewAdapter(uint16 _bridgeType, address _newAdapter) public {
        vm.assume(_newAdapter != address(0));
        vm.assume(_newAdapter != VM_ADDRESS);

        vm.mockCall(
            _newAdapter,
            abi.encodeWithSelector(IBridgeAdapter.bridgeCoordinator.selector),
            abi.encode(address(coordinator))
        );
        vm.mockCall(_newAdapter, abi.encodeWithSelector(IBridgeAdapter.bridgeType.selector), abi.encode(_bridgeType));

        vm.expectEmit();
        emit AdapterManager.LocalBridgeAdapterUpdated(_bridgeType, _newAdapter, true);

        vm.prank(manager);
        coordinator.setIsLocalBridgeAdapter(_bridgeType, IBridgeAdapter(_newAdapter), true);

        assertTrue(coordinator.isLocalBridgeAdapter(_bridgeType, _newAdapter));

        vm.expectEmit();
        emit AdapterManager.LocalBridgeAdapterUpdated(_bridgeType, _newAdapter, false);

        vm.prank(manager);
        coordinator.setIsLocalBridgeAdapter(_bridgeType, IBridgeAdapter(_newAdapter), false);

        assertFalse(coordinator.isLocalBridgeAdapter(_bridgeType, _newAdapter));
    }
}

contract BridgeCoordinator_AdapterManager_SetIsRemoteBridgeAdapter_Test is BridgeCoordinator_AdapterManager_Test {
    bytes32 newAdapter = bytes32(uint256(uint160(makeAddr("newAdapter"))));

    function test_shouldRevert_whenCallerNotManager() public {
        address caller = makeAddr("notManager");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.setIsRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter, true);
    }

    function test_shouldRevert_whenOutboundAdapter_whenRemoving() public {
        coordinator.workaround_setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter);

        vm.expectRevert(AdapterManager.IsOutboundAdapter.selector);
        vm.prank(manager);
        coordinator.setIsRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter, false);
    }

    function testFuzz_shouldSetNewAdapter_whenAdding(
        uint16 _bridgeType,
        uint256 _chainId,
        address _newAdapter
    )
        public
    {
        vm.assume(_newAdapter != address(0));
        newAdapter = bytes32(uint256(uint160(_newAdapter)));

        vm.expectEmit();
        emit AdapterManager.RemoteBridgeAdapterUpdated(_bridgeType, _chainId, newAdapter, true);

        vm.prank(manager);
        coordinator.setIsRemoteBridgeAdapter(_bridgeType, _chainId, newAdapter, true);

        assertTrue(coordinator.isRemoteBridgeAdapter(_bridgeType, _chainId, newAdapter));

        vm.expectEmit();
        emit AdapterManager.RemoteBridgeAdapterUpdated(_bridgeType, _chainId, newAdapter, false);

        vm.prank(manager);
        coordinator.setIsRemoteBridgeAdapter(_bridgeType, _chainId, newAdapter, false);

        assertFalse(coordinator.isRemoteBridgeAdapter(_bridgeType, _chainId, newAdapter));
    }
}

contract BridgeCoordinator_AdapterManager_SetOutboundLocalBridgeAdapter_Test is BridgeCoordinator_AdapterManager_Test {
    address newAdapter = makeAddr("newAdapter");

    function setUp() public override {
        super.setUp();

        coordinator.workaround_setIsLocalBridgeAdapter(bridgeType, newAdapter, true);
    }

    function test_shouldRevert_whenCallerNotManager() public {
        address caller = makeAddr("notManager");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.setOutboundLocalBridgeAdapter(bridgeType, IBridgeAdapter(newAdapter));
    }

    function test_shouldRevert_whenNotAdapter() public {
        coordinator.workaround_setIsLocalBridgeAdapter(bridgeType, newAdapter, false);

        vm.expectRevert(AdapterManager.IsNotAdapter.selector);
        vm.prank(manager);
        coordinator.setOutboundLocalBridgeAdapter(bridgeType, IBridgeAdapter(newAdapter));
    }

    function test_shouldSetAdapter() public {
        assertEq(address(coordinator.outboundLocalBridgeAdapter(bridgeType)), localAdapter);

        vm.expectEmit();
        emit AdapterManager.LocalOutboundBridgeAdapterUpdated(bridgeType, newAdapter);

        vm.prank(manager);
        coordinator.setOutboundLocalBridgeAdapter(bridgeType, IBridgeAdapter(newAdapter));

        assertEq(address(coordinator.outboundLocalBridgeAdapter(bridgeType)), newAdapter);
    }

    function test_shouldRemoveAdapter() public {
        assertEq(address(coordinator.outboundLocalBridgeAdapter(bridgeType)), localAdapter);

        vm.expectEmit();
        emit AdapterManager.LocalOutboundBridgeAdapterUpdated(bridgeType, address(0));

        vm.prank(manager);
        coordinator.setOutboundLocalBridgeAdapter(bridgeType, IBridgeAdapter(address(0)));

        assertEq(address(coordinator.outboundLocalBridgeAdapter(bridgeType)), address(0));
    }
}

contract BridgeCoordinator_AdapterManager_SetOutboundRemoteBridgeAdapter_Test is BridgeCoordinator_AdapterManager_Test {
    bytes32 newAdapter = bytes32(uint256(uint160(makeAddr("newAdapter"))));

    function setUp() public override {
        super.setUp();

        coordinator.workaround_setIsRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter, true);
    }

    function test_shouldRevert_whenCallerNotManager() public {
        address caller = makeAddr("notManager");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter);
    }

    function test_shouldRevert_whenNotAdapter() public {
        coordinator.workaround_setIsRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter, false);

        vm.expectRevert(AdapterManager.IsNotAdapter.selector);
        vm.prank(manager);
        coordinator.setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter);
    }

    function test_shouldSwapAdapters() public {
        assertEq(coordinator.outboundRemoteBridgeAdapter(bridgeType, remoteChainId), remoteAdapter);

        vm.expectEmit();
        emit AdapterManager.RemoteOutboundBridgeAdapterUpdated(bridgeType, remoteChainId, newAdapter);

        vm.prank(manager);
        coordinator.setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter);

        assertEq(coordinator.outboundRemoteBridgeAdapter(bridgeType, remoteChainId), newAdapter);
    }

    function test_shouldRemoveAdapter() public {
        assertEq(coordinator.outboundRemoteBridgeAdapter(bridgeType, remoteChainId), remoteAdapter);

        vm.expectEmit();
        emit AdapterManager.RemoteOutboundBridgeAdapterUpdated(bridgeType, remoteChainId, bytes32(0));

        vm.prank(manager);
        coordinator.setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, bytes32(0));

        assertEq(coordinator.outboundRemoteBridgeAdapter(bridgeType, remoteChainId), bytes32(0));
    }
}
