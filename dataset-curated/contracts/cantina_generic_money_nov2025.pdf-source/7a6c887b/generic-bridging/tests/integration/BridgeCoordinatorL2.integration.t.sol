// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BridgeCoordinatorL2, BridgeCoordinator } from "../../src/BridgeCoordinatorL2.sol";
import { BridgeMessageCoordinator, BridgeMessage } from "../../src/coordinator/BridgeMessageCoordinator.sol";

import { MockBridgeAdapter } from "../helper/MockBridgeAdapter.sol";
import { MockERC20 } from "../helper/MockERC20.sol";
import { MockWhitelabeledUnit } from "../helper/MockWhitelabeledUnit.sol";

abstract contract BridgeCoordinatorL2IntegrationTest is Test {
    BridgeCoordinatorL2 coordinator;
    MockERC20 unit;
    MockWhitelabeledUnit gusd;

    MockBridgeAdapter localAdapter;
    bytes32 remoteAdapter = keccak256("remote adapter");

    address controller = makeAddr("controller");
    address user = makeAddr("user");
    bytes32 remoteUser = keccak256("remote user");
    address relayer = makeAddr("relayer");
    uint256 chainId = 42;
    uint16 bridgeType = 1;
    bytes32 destWhitelabel = keccak256("destWhitelabel");
    bytes32 messageId = keccak256("messageId");

    function setUp() public virtual {
        coordinator = BridgeCoordinatorL2(
            address(new TransparentUpgradeableProxy(address(new BridgeCoordinatorL2()), address(this), ""))
        );
        unit = new MockERC20(18);
        gusd = new MockWhitelabeledUnit(address(unit));
        coordinator.initialize(address(unit), address(this));

        coordinator.grantRole(coordinator.ADAPTER_MANAGER_ROLE(), address(this));

        localAdapter = new MockBridgeAdapter(bridgeType, address(coordinator));

        deal(address(unit), user, 1_000_000e18, true);
        vm.startPrank(user);
        unit.approve(address(gusd), type(uint256).max);
        gusd.wrap(user, 1_000_000e18);
        gusd.approve(address(coordinator), type(uint256).max);
        vm.stopPrank();

        deal(user, 10 ether);
        deal(relayer, 10 ether);

        vm.label(address(coordinator), "BridgeCoordinatorL2");
        vm.label(address(controller), "Controller");
        vm.label(address(unit), "unit");
        vm.label(address(gusd), "GUSD");
    }
}

contract BridgeCoordinatorL2_Bridge_IntegrationTest is BridgeCoordinatorL2IntegrationTest {
    function test_bridge_outbound() public {
        // Fail to bridge when no adapters are set
        vm.expectRevert(BridgeCoordinator.NoOutboundLocalBridgeAdapter.selector);
        vm.prank(user);
        coordinator.bridge{ value: 1 ether }(
            bridgeType, chainId, user, remoteUser, address(gusd), destWhitelabel, 100e18, "bridge data"
        );

        // Setup local adapter
        coordinator.setIsLocalBridgeAdapter(bridgeType, localAdapter, true);
        coordinator.setOutboundLocalBridgeAdapter(bridgeType, localAdapter);
        assertFalse(coordinator.supportsBridgeTypeFor(bridgeType, chainId));

        // Fail to bridge when no remote adapter is set
        vm.expectRevert(BridgeCoordinator.NoOutboundRemoteBridgeAdapter.selector);
        vm.prank(user);
        coordinator.bridge{ value: 1 ether }(
            bridgeType, chainId, user, remoteUser, address(gusd), destWhitelabel, 100e18, "bridge data"
        );

        // Setup remote adapter
        coordinator.setIsRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter, true);
        coordinator.setOutboundRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter);
        assertTrue(coordinator.supportsBridgeTypeFor(bridgeType, chainId));

        // Bridge successfully
        uint256 preTotalSupply = unit.totalSupply();
        assertEq(unit.totalSupply(), preTotalSupply);
        assertEq(gusd.totalSupply(), preTotalSupply);
        assertEq(gusd.balanceOf(user), preTotalSupply);

        localAdapter.returnMessageId(messageId);
        vm.prank(user);
        bytes32 msgId = coordinator.bridge{ value: 1 ether }(
            bridgeType, chainId, user, remoteUser, address(gusd), destWhitelabel, 100e18, "bridge data"
        );

        assertEq(unit.totalSupply(), preTotalSupply - 100e18);
        assertEq(gusd.totalSupply(), preTotalSupply - 100e18);
        assertEq(gusd.balanceOf(user), preTotalSupply - 100e18);

        assertEq(msgId, messageId);
        bytes memory expectedMessage = coordinator.encodeBridgeMessage(
            BridgeMessage({
                sender: coordinator.encodeOmnichainAddress(user),
                recipient: remoteUser,
                sourceWhitelabel: coordinator.encodeOmnichainAddress(address(gusd)),
                destinationWhitelabel: destWhitelabel,
                amount: 100e18
            })
        );
        (
            uint256 chainId_,
            bytes32 remoteAdapter_,
            bytes memory message,
            address refundAddress,
            bytes memory bridgeParams
        ) = localAdapter.lastBridgeCall();
        assertEq(chainId_, chainId, "chain id mismatch");
        assertEq(remoteAdapter_, remoteAdapter, "remote adapter mismatch");
        assertEq(message, expectedMessage, "message mismatch");
        assertEq(refundAddress, user, "refund address mismatch");
        assertEq(bridgeParams, "bridge data", "bridge params mismatch");
    }

    function test_bridge_inbound() public {
        address receiver = makeAddr("receiver");
        bytes memory messageData = coordinator.encodeBridgeMessage(
            BridgeMessage({
                sender: remoteUser,
                recipient: coordinator.encodeOmnichainAddress(receiver),
                sourceWhitelabel: coordinator.encodeOmnichainAddress(address(0)),
                destinationWhitelabel: coordinator.encodeOmnichainAddress(address(gusd)),
                amount: 100e18
            })
        );

        // Fail to settle when no adapters are set
        vm.expectRevert(BridgeCoordinator.OnlyLocalAdapter.selector);
        vm.prank(address(localAdapter));
        coordinator.settleInboundMessage(bridgeType, chainId, remoteUser, messageData, messageId);

        // Setup adapters
        coordinator.setIsLocalBridgeAdapter(bridgeType, localAdapter, true);
        coordinator.setOutboundLocalBridgeAdapter(bridgeType, localAdapter);
        coordinator.setIsRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter, true);
        coordinator.setOutboundRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter);

        // Settle successfully
        uint256 preTotalSupply = unit.totalSupply();
        assertEq(unit.totalSupply(), preTotalSupply);
        assertEq(gusd.totalSupply(), preTotalSupply);
        assertEq(gusd.balanceOf(receiver), 0);

        vm.prank(address(localAdapter));
        coordinator.settleInboundMessage(bridgeType, chainId, remoteAdapter, messageData, messageId);

        assertEq(unit.totalSupply(), preTotalSupply + 100e18);
        assertEq(gusd.totalSupply(), preTotalSupply + 100e18);
        assertEq(gusd.balanceOf(receiver), 100e18);

        // Fail to settle and store failed message execution for rollback test
        gusd.setRevertNextCall(true);

        vm.prank(address(localAdapter));
        coordinator.settleInboundMessage(bridgeType, chainId, remoteAdapter, messageData, messageId);

        assertEq(gusd.balanceOf(receiver), 100e18); // still only 100e18
        assertNotEq(coordinator.failedMessageExecutions(messageId), bytes32(0), "failed message execution not stored");
    }

    function test_bridge_rollback() public {
        BridgeMessage memory message = BridgeMessage({
            sender: remoteUser,
            recipient: coordinator.encodeOmnichainAddress(user),
            sourceWhitelabel: coordinator.encodeOmnichainAddress(address(gusd)),
            destinationWhitelabel: coordinator.encodeOmnichainAddress(address(gusd)),
            amount: 100e18
        });
        bytes memory messageData = coordinator.encodeBridgeMessage(message);

        // Setup adapters
        coordinator.setIsLocalBridgeAdapter(bridgeType, localAdapter, true);
        coordinator.setOutboundLocalBridgeAdapter(bridgeType, localAdapter);
        coordinator.setIsRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter, true);
        coordinator.setOutboundRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter);

        // Fail to settle and store failed message execution for rollback test
        gusd.setRevertNextCall(true);

        vm.prank(address(localAdapter));
        coordinator.settleInboundMessage(bridgeType, chainId, remoteAdapter, messageData, messageId);

        bytes32 failedMessageExecution = coordinator.failedMessageExecutions(messageId);
        assertNotEq(failedMessageExecution, bytes32(0), "failed message execution not stored");

        // Fail to rollback with invalid data
        message.amount = 1000e18; // different amount
        bytes memory invalidFailedMessageData = coordinator.encodeBridgeMessage(message);
        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidFailedMessageData.selector);
        vm.prank(relayer);
        coordinator.rollback{ value: 1 ether }(bridgeType, chainId, invalidFailedMessageData, messageId, "bridge data");

        // Setup different bridge type
        uint16 bridgeType2 = bridgeType + 1;
        MockBridgeAdapter localAdapter2 = new MockBridgeAdapter(bridgeType2, address(coordinator));
        coordinator.setIsLocalBridgeAdapter(bridgeType2, localAdapter2, true);
        coordinator.setOutboundLocalBridgeAdapter(bridgeType2, localAdapter2);
        coordinator.setIsRemoteBridgeAdapter(bridgeType2, chainId, remoteAdapter, true);
        coordinator.setOutboundRemoteBridgeAdapter(bridgeType2, chainId, remoteAdapter);
        assertTrue(coordinator.supportsBridgeTypeFor(bridgeType2, chainId));

        // Rollback successfully via different bridge type
        bytes32 rollbackMessageId = keccak256("rollbackMessageId");
        localAdapter2.returnMessageId(rollbackMessageId);
        vm.prank(relayer);
        bytes32 rollbackMsgId = coordinator.rollback{ value: 1 ether }(
            bridgeType2, chainId, messageData, messageId, "rollback bridge data"
        );

        assertEq(rollbackMsgId, rollbackMessageId);
        assertEq(coordinator.failedMessageExecutions(messageId), bytes32(0), "failed message execution not deleted");
        BridgeMessage memory expectedRollbackMessage = BridgeMessage({
            sender: bytes32(0),
            recipient: remoteUser,
            sourceWhitelabel: coordinator.encodeOmnichainAddress(address(gusd)),
            destinationWhitelabel: coordinator.encodeOmnichainAddress(address(gusd)),
            amount: 100e18
        });
        bytes memory expectedRollbackMessageData = coordinator.encodeBridgeMessage(expectedRollbackMessage);
        (
            uint256 chainId_,
            bytes32 remoteAdapter_,
            bytes memory rollbackMessageData,
            address refundAddress,
            bytes memory bridgeParams
        ) = localAdapter2.lastBridgeCall();
        assertEq(chainId_, chainId, "chain id mismatch");
        assertEq(remoteAdapter_, remoteAdapter, "remote adapter mismatch");
        assertEq(rollbackMessageData, expectedRollbackMessageData, "message mismatch");
        assertEq(refundAddress, relayer, "refund address mismatch");
        assertEq(bridgeParams, "rollback bridge data", "bridge params mismatch");
    }
}
