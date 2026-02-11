// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BridgeCoordinatorL1, BridgeCoordinator } from "../../src/BridgeCoordinatorL1.sol";
import { PredepositCoordinator } from "../../src/coordinator/PredepositCoordinator.sol";
import { BridgeMessageCoordinator, BridgeMessage } from "../../src/coordinator/BridgeMessageCoordinator.sol";

import { MockBridgeAdapter } from "../helper/MockBridgeAdapter.sol";
import { MockERC20 } from "../helper/MockERC20.sol";
import { MockWhitelabeledUnit } from "../helper/MockWhitelabeledUnit.sol";

abstract contract BridgeCoordinatorL1IntegrationTest is Test {
    BridgeCoordinatorL1 coordinator;
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
    address srcWhitelabel = address(0);
    bytes32 destWhitelabel = keccak256("destWhitelabel");
    bytes32 messageId = keccak256("messageId");

    function setUp() public virtual {
        coordinator = BridgeCoordinatorL1(
            address(new TransparentUpgradeableProxy(address(new BridgeCoordinatorL1()), address(this), ""))
        );
        unit = new MockERC20(18);
        gusd = new MockWhitelabeledUnit(address(unit));
        coordinator.initialize(address(unit), address(this));

        coordinator.grantRole(coordinator.ADAPTER_MANAGER_ROLE(), address(this));
        coordinator.grantRole(coordinator.PREDEPOSIT_MANAGER_ROLE(), address(this));

        localAdapter = new MockBridgeAdapter(bridgeType, address(coordinator));

        deal(address(unit), user, 1_000_000e18, true);
        vm.startPrank(user);
        unit.approve(address(gusd), type(uint256).max);
        gusd.wrap(user, 1_000_000e18);
        gusd.approve(address(coordinator), type(uint256).max);
        vm.stopPrank();

        deal(user, 10 ether);
        deal(relayer, 10 ether);

        vm.label(address(coordinator), "BridgeCoordinatorL1");
        vm.label(address(controller), "Controller");
        vm.label(address(gusd), "GUSD");
    }
}

contract BridgeCoordinatorL1_Bridge_IntegrationTest is BridgeCoordinatorL1IntegrationTest {
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
        localAdapter.returnMessageId(messageId);
        vm.prank(user);
        bytes32 msgId = coordinator.bridge{ value: 1 ether }(
            bridgeType, chainId, user, remoteUser, address(gusd), destWhitelabel, 100e18, "bridge data"
        );

        assertEq(msgId, messageId);
        assertEq(gusd.balanceOf(address(coordinator)), 0);
        assertEq(unit.balanceOf(address(coordinator)), 100e18);
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
        deal(address(unit), address(coordinator), 100e18, true); // Pre-fund coordinator for inbound bridge
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
        vm.prank(address(localAdapter));
        coordinator.settleInboundMessage(bridgeType, chainId, remoteAdapter, messageData, messageId);

        assertEq(gusd.balanceOf(receiver), 100e18);
        assertEq(unit.balanceOf(address(coordinator)), 0);

        // Fail to settle and store failed message execution for rollback test
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

        // Store failed message execution (not enough funds)
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

contract BridgeCoordinatorL1_Predeposit_IntegrationTest is BridgeCoordinatorL1IntegrationTest {
    bytes32 chainNickname = keccak256("super duper L2 chain");

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(user);
        gusd.unwrap(user, user, 1_000_000e18);
        unit.approve(address(coordinator), type(uint256).max);
        vm.stopPrank();
    }

    function test_predeposit_dispatch() public {
        // Fail to predeposit before enabling
        vm.expectRevert(PredepositCoordinator.Predeposit_NotEnabled.selector);
        vm.prank(user);
        coordinator.predeposit(chainNickname, user, remoteUser, 100e18);

        // Enable predeposits for a chain
        coordinator.enablePredeposits(chainNickname);
        assertEq(
            uint8(coordinator.getChainPredepositState(chainNickname)),
            uint8(PredepositCoordinator.PredepositState.ENABLED)
        );

        // Predeposit successfully
        vm.prank(user);
        coordinator.predeposit(chainNickname, user, remoteUser, 100e18);

        assertEq(unit.balanceOf(address(coordinator)), 100e18);
        assertEq(coordinator.getPredeposit(chainNickname, user, remoteUser), 100e18);

        // Predeposit more successfully
        vm.prank(user);
        coordinator.predeposit(chainNickname, user, remoteUser, 300e18);

        assertEq(unit.balanceOf(address(coordinator)), 400e18);
        assertEq(coordinator.getPredeposit(chainNickname, user, remoteUser), 400e18);

        // Enable dispatch for a chain
        coordinator.enablePredepositsDispatch(chainNickname, chainId, destWhitelabel);
        assertEq(
            uint8(coordinator.getChainPredepositState(chainNickname)),
            uint8(PredepositCoordinator.PredepositState.DISPATCHED)
        );
        assertEq(coordinator.getChainIdForNickname(chainNickname), chainId);

        // Fail to withdraw after enabling dispatch
        vm.expectRevert(PredepositCoordinator.Predeposit_WithdrawalsNotEnabled.selector);
        vm.prank(user);
        coordinator.withdrawPredeposit(chainNickname, remoteUser, user, srcWhitelabel);

        // Fail to dispatch when no adapters are set
        vm.expectRevert(BridgeCoordinator.NoOutboundLocalBridgeAdapter.selector);
        vm.prank(relayer);
        coordinator.bridgePredeposit{ value: 1 ether }(bridgeType, chainNickname, user, remoteUser, "");

        // Setup adapters
        assertFalse(coordinator.supportsBridgeTypeFor(bridgeType, chainId));
        coordinator.setIsLocalBridgeAdapter(bridgeType, localAdapter, true);
        coordinator.setIsRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter, true);
        coordinator.setOutboundLocalBridgeAdapter(bridgeType, localAdapter);
        coordinator.setOutboundRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter);
        assertTrue(coordinator.supportsBridgeTypeFor(bridgeType, chainId));

        // Dispatch successfully
        localAdapter.returnMessageId(messageId);
        vm.prank(relayer);
        bytes32 msgId =
            coordinator.bridgePredeposit{ value: 1 ether }(bridgeType, chainNickname, user, remoteUser, "bridge data");

        assertEq(msgId, messageId);
        assertEq(unit.balanceOf(address(coordinator)), 400e18);
        assertEq(coordinator.getPredeposit(chainNickname, user, remoteUser), 0);
        bytes memory expectedMessage = coordinator.encodeBridgeMessage(
            BridgeMessage({
                sender: coordinator.encodeOmnichainAddress(user),
                recipient: remoteUser,
                sourceWhitelabel: coordinator.encodeOmnichainAddress(address(0)),
                destinationWhitelabel: destWhitelabel,
                amount: 400e18
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
        assertEq(refundAddress, relayer, "refund address mismatch");
        assertEq(bridgeParams, "bridge data", "bridge params mismatch");

        // Fail to predeposit after enabling dispatch
        vm.expectRevert(PredepositCoordinator.Predeposit_NotEnabled.selector);
        vm.prank(user);
        coordinator.predeposit(chainNickname, user, remoteUser, 100e18);
    }

    function test_predeposit_withdraw() public {
        // Enable predeposits for a chain
        coordinator.enablePredeposits(chainNickname);

        // Predeposit successfully
        vm.prank(user);
        coordinator.predeposit(chainNickname, user, remoteUser, 100e18);

        // Enable withdrawals for a chain
        coordinator.enablePredepositsWithdraw(chainNickname);
        assertEq(
            uint8(coordinator.getChainPredepositState(chainNickname)),
            uint8(PredepositCoordinator.PredepositState.WITHDRAWN)
        );
        assertEq(coordinator.getChainIdForNickname(chainNickname), 0);

        // Fail to dispatch after enabling withdrawals
        vm.expectRevert(PredepositCoordinator.Predeposit_DispatchNotEnabled.selector);
        vm.prank(relayer);
        coordinator.bridgePredeposit{ value: 1 ether }(bridgeType, chainNickname, user, remoteUser, "");

        // Withdraw successfully
        vm.prank(user);
        coordinator.withdrawPredeposit(chainNickname, remoteUser, user, address(gusd));

        assertEq(gusd.balanceOf(user), 100e18);
        assertEq(gusd.balanceOf(address(coordinator)), 0);
        assertEq(coordinator.getPredeposit(chainNickname, user, remoteUser), 0);

        // Fail to predeposit after enabling withdrawals
        vm.expectRevert(PredepositCoordinator.Predeposit_NotEnabled.selector);
        vm.prank(user);
        coordinator.predeposit(chainNickname, user, remoteUser, 100e18);
    }
}
