// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { BridgeCoordinator, IBridgeAdapter } from "../../../src/coordinator/BridgeCoordinator.sol";
import { BridgeMessageCoordinator, BridgeMessage } from "../../../src/coordinator/BridgeMessageCoordinator.sol";
import { Bytes32AddressLib } from "../../../src/utils/Bytes32AddressLib.sol";

import { BridgeCoordinatorTest, BridgeCoordinator_SettleInboundBridge_Test } from "./BridgeCoordinator.t.sol";

using Bytes32AddressLib for address;
using Bytes32AddressLib for bytes32;

abstract contract BridgeCoordinator_BridgeMessage_Test is BridgeCoordinatorTest {
    address owner = makeAddr("owner");
    BridgeMessage bridgeMessage = BridgeMessage({
        sender: owner.toBytes32WithLowAddress(),
        recipient: remoteRecipient,
        sourceWhitelabel: srcWhitelabel.toBytes32WithLowAddress(),
        destinationWhitelabel: destWhitelabel,
        amount: 1
    });
}

contract BridgeCoordinator_BridgeMessage_Bridge_Test is BridgeCoordinator_BridgeMessage_Test {
    function test_shouldRevert_whenNoOutboundLocalAdapter() public {
        coordinator.workaround_setOutboundLocalBridgeAdapter(bridgeType, address(0)); // remove local adapter

        vm.expectRevert(BridgeCoordinator.NoOutboundLocalBridgeAdapter.selector);
        coordinator.bridge(bridgeType, remoteChainId, owner, remoteRecipient, srcWhitelabel, destWhitelabel, 1, "");
    }

    function test_shouldRevert_whenNoOutboundRemoteAdapter() public {
        // remove remote adapter
        coordinator.workaround_setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, bytes32(0));

        vm.expectRevert(BridgeCoordinator.NoOutboundRemoteBridgeAdapter.selector);
        coordinator.bridge(bridgeType, remoteChainId, owner, remoteRecipient, srcWhitelabel, destWhitelabel, 1, "");
    }

    function test_shouldRevert_whenOnBehalfIsZero() public {
        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidOnBehalf.selector);
        coordinator.bridge(bridgeType, remoteChainId, address(0), remoteRecipient, srcWhitelabel, destWhitelabel, 1, "");
    }

    function test_shouldRevert_whenRemoteRecipientIsZero() public {
        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidRemoteRecipient.selector);
        coordinator.bridge(bridgeType, remoteChainId, owner, bytes32(0), srcWhitelabel, destWhitelabel, 1, "");
    }

    function test_shouldRevert_whenAmountIsZero() public {
        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidAmount.selector);
        coordinator.bridge(bridgeType, remoteChainId, owner, remoteRecipient, srcWhitelabel, destWhitelabel, 0, "");
    }

    function testFuzz_shouldCallBridgeOnLocalAdapter(
        uint256 fee,
        uint256 amount,
        bytes calldata bridgeParams
    )
        public
    {
        vm.assume(amount > 0);
        fee = bound(fee, 1 ether, 10 ether);

        deal(sender, fee);

        bridgeMessage.amount = amount;
        bytes memory bridgeMessageData = coordinator.encodeBridgeMessage(bridgeMessage);

        vm.expectCall(
            localAdapter,
            fee,
            abi.encodeWithSelector(
                IBridgeAdapter.bridge.selector,
                remoteChainId,
                remoteAdapter,
                bridgeMessageData,
                sender, // caller as refund address
                bridgeParams
            )
        );

        vm.prank(sender);
        coordinator.bridge{ value: fee }(
            bridgeType, remoteChainId, owner, remoteRecipient, srcWhitelabel, destWhitelabel, amount, bridgeParams
        );
    }

    function testFuzz_shouldRestrictUnitTokens(address sender, address whitelabel, uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(sender != address(0));

        vm.prank(sender);
        coordinator.bridge(bridgeType, remoteChainId, owner, remoteRecipient, whitelabel, destWhitelabel, amount, "");

        (address whitelabel_, address sender_, uint256 amount_) = coordinator.lastRestrictCall();
        assertEq(whitelabel_, whitelabel);
        assertEq(sender_, sender);
        assertEq(amount_, amount);
    }

    function test_shouldReturnMessageId() public {
        bytes32 returnedMessageId =
            coordinator.bridge(bridgeType, remoteChainId, owner, remoteRecipient, srcWhitelabel, destWhitelabel, 1, "");

        assertEq(returnedMessageId, messageId);
    }

    function test_shouldEmit_MessageOut() public {
        bytes memory bridgeMessageData = coordinator.encodeBridgeMessage(bridgeMessage);

        vm.expectEmit();
        emit BridgeCoordinator.MessageOut(bridgeType, remoteChainId, messageId, bridgeMessageData);

        coordinator.bridge(bridgeType, remoteChainId, owner, remoteRecipient, srcWhitelabel, destWhitelabel, 1, "");
    }

    function testFuzz_shouldEmit_BridgedOut(uint256 amount) public {
        vm.assume(amount > 0);

        bridgeMessage.amount = amount;

        vm.expectEmit();
        emit BridgeMessageCoordinator.BridgedOut(sender, owner, remoteRecipient, amount, messageId, bridgeMessage);

        vm.prank(sender);
        coordinator.bridge(bridgeType, remoteChainId, owner, remoteRecipient, srcWhitelabel, destWhitelabel, amount, "");
    }
}

contract BridgeCoordinator_BridgeMessage_Rollback_Test is BridgeCoordinator_BridgeMessage_Test {
    bytes32 originalRemoteSender = keccak256("originalRemoteSender");
    bytes32 originalOmnichainRecipient = keccak256("originalOmnichainRecipient");
    uint256 originalAmount = 1000 ether;
    bytes32 originalMessageId = keccak256("originalMessageId");
    bytes32 failedMessagesHash;
    bytes originalMessageData;

    function setUp() public override {
        super.setUp();

        bridgeMessage.sender = originalRemoteSender;
        bridgeMessage.recipient = originalOmnichainRecipient;
        bridgeMessage.amount = originalAmount;
        originalMessageData = coordinator.encodeBridgeMessage(bridgeMessage);
        failedMessagesHash = keccak256(abi.encode(remoteChainId, originalMessageData));
        coordinator.workaround_setFailedMessageExecution(originalMessageId, failedMessagesHash);
    }

    function test_shouldRevert_whenNoOutboundLocalAdapter() public {
        coordinator.workaround_setOutboundLocalBridgeAdapter(bridgeType, address(0)); // remove local adapter

        vm.expectRevert(BridgeCoordinator.NoOutboundLocalBridgeAdapter.selector);
        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldRevert_whenNoOutboundRemoteAdapter() public {
        // remove remote adapter
        coordinator.workaround_setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, bytes32(0));

        vm.expectRevert(BridgeCoordinator.NoOutboundRemoteBridgeAdapter.selector);
        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldRevert_whenNoFailedMessageExecution() public {
        bytes32 badMessageId = keccak256("badMessageId");

        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_NoFailedMessageExecution.selector);
        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, badMessageId, "");
    }

    function test_shouldRevert_whenIncorrectFailedMessageData() public {
        // Register remote adapter for different chain ID so that the rollback does not revert on missing adapter
        coordinator.workaround_setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId + 1, remoteAdapter);

        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidFailedMessageData.selector);
        coordinator.rollback(bridgeType, remoteChainId + 1, originalMessageData, originalMessageId, "");

        bridgeMessage.sender = originalRemoteSender << 1;
        originalMessageData = coordinator.encodeBridgeMessage(bridgeMessage);
        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidFailedMessageData.selector);
        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldDeleteFailedMessageHash() public {
        assertEq(coordinator.failedMessageExecutions(originalMessageId), failedMessagesHash);

        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");

        assertEq(coordinator.failedMessageExecutions(originalMessageId), bytes32(0));
    }

    function test_shouldRevert_whenFailedMessageNotBridgeType() public {
        // Note: skipping this test as any attempt to encode a message value out of enum scope panics
        // stop skipping after adding new message type
        vm.skip(true);

        // Encode original message as a rollback message instead of bridge message
        originalMessageData = abi.encode(
            uint8(99),
            BridgeMessage({
                sender: originalRemoteSender,
                recipient: originalOmnichainRecipient,
                sourceWhitelabel: srcWhitelabel.toBytes32WithLowAddress(),
                destinationWhitelabel: destWhitelabel,
                amount: originalAmount
            })
        );
        failedMessagesHash = keccak256(abi.encode(remoteChainId, originalMessageData));
        coordinator.workaround_setFailedMessageExecution(originalMessageId, failedMessagesHash);

        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidMessageType.selector);
        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function testFuzz_shouldBridgeRollbackMessage(
        bytes32 msgId,
        address sender,
        uint256 amount,
        uint256 fee,
        bytes memory bridgeParams
    )
        public
    {
        vm.assume(msgId != bytes32(0));
        vm.assume(sender != address(0));
        fee = bound(fee, 0, 10 ether);

        address caller = makeAddr("caller");
        deal(caller, fee);

        originalMessageId = msgId;
        bridgeMessage.sender = sender.toBytes32WithLowAddress();
        bridgeMessage.recipient = remoteRecipient;
        bridgeMessage.amount = amount; // can be 0

        originalMessageData = coordinator.encodeBridgeMessage(bridgeMessage);
        failedMessagesHash = keccak256(abi.encode(remoteChainId, originalMessageData));
        coordinator.workaround_setFailedMessageExecution(originalMessageId, failedMessagesHash);

        bytes memory rollbackMessageData = coordinator.encodeBridgeMessage(
            BridgeMessage({
                sender: bytes32(0),
                recipient: bridgeMessage.sender,
                sourceWhitelabel: bytes32(0),
                destinationWhitelabel: srcWhitelabel.toBytes32WithLowAddress(),
                amount: bridgeMessage.amount
            })
        );

        vm.expectCall(
            localAdapter,
            fee,
            abi.encodeWithSelector(
                IBridgeAdapter.bridge.selector,
                remoteChainId,
                remoteAdapter,
                rollbackMessageData,
                caller, // caller as refund address
                bridgeParams
            )
        );

        vm.prank(caller);
        coordinator.rollback{ value: fee }(
            bridgeType, remoteChainId, originalMessageData, originalMessageId, bridgeParams
        );
    }

    function test_shouldEmit_MessageOut() public {
        bytes memory rollbackMessageData = coordinator.encodeBridgeMessage(
            BridgeMessage({
                sender: bytes32(0),
                recipient: originalRemoteSender,
                sourceWhitelabel: bytes32(0),
                destinationWhitelabel: srcWhitelabel.toBytes32WithLowAddress(),
                amount: originalAmount
            })
        );

        vm.expectEmit();
        emit BridgeCoordinator.MessageOut(bridgeType, remoteChainId, messageId, rollbackMessageData);

        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldEmit_BridgeRollbackedOut() public {
        vm.expectEmit();
        emit BridgeMessageCoordinator.BridgeRollbackedOut(originalMessageId, messageId);

        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldEmit_BridgedOut() public {
        BridgeMessage memory rollbackBridgeMessage = BridgeMessage({
            sender: bytes32(0),
            recipient: originalRemoteSender,
            sourceWhitelabel: bytes32(0),
            destinationWhitelabel: srcWhitelabel.toBytes32WithLowAddress(),
            amount: originalAmount
        });

        vm.expectEmit();
        emit BridgeMessageCoordinator.BridgedOut(
            sender, address(0), originalRemoteSender, originalAmount, messageId, rollbackBridgeMessage
        );

        vm.prank(sender);
        coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");
    }

    function test_shouldReturnMessageId() public {
        bytes32 returnedMessageId =
            coordinator.rollback(bridgeType, remoteChainId, originalMessageData, originalMessageId, "");

        assertEq(returnedMessageId, messageId);
    }
}

contract BridgeCoordinator_SettleInboundBridge_BridgeMessage_Test is
    BridgeCoordinator_BridgeMessage_Test,
    BridgeCoordinator_SettleInboundBridge_Test
{
    function setUp() public override {
        super.setUp();

        bridgeMessage = BridgeMessage({
            sender: remoteSender,
            recipient: recipient.toBytes32WithLowAddress(),
            sourceWhitelabel: srcWhitelabel.toBytes32WithLowAddress(),
            destinationWhitelabel: destWhitelabel,
            amount: 500
        });
        messageData = coordinator.encodeBridgeMessage(bridgeMessage);
    }

    function test_shouldStoreFailedMessage_whenRecipientIsZero() public {
        bridgeMessage.recipient = bytes32(0);
        messageData = coordinator.encodeBridgeMessage(bridgeMessage);

        vm.expectEmit();
        emit BridgeCoordinator.MessageExecutionFailed(messageId);

        vm.prank(localAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, remoteAdapter, messageData, messageId);

        bytes32 failedMessageHash = keccak256(abi.encode(remoteChainId, messageData));
        assertEq(coordinator.failedMessageExecutions(messageId), failedMessageHash);
    }

    function test_shouldStoreFailedMessage_whenAmountIsZero() public {
        bridgeMessage.amount = 0;
        messageData = coordinator.encodeBridgeMessage(bridgeMessage);

        vm.expectEmit();
        emit BridgeCoordinator.MessageExecutionFailed(messageId);

        vm.prank(localAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, remoteAdapter, messageData, messageId);

        bytes32 failedMessageHash = keccak256(abi.encode(remoteChainId, messageData));
        assertEq(coordinator.failedMessageExecutions(messageId), failedMessageHash);
    }

    function testFuzz_shouldReleaseUnitToken(address _recipient, uint256 amount) public {
        vm.assume(_recipient != address(0));
        vm.assume(amount > 0);

        bridgeMessage.recipient = _recipient.toBytes32WithLowAddress();
        bridgeMessage.amount = amount;
        messageData = coordinator.encodeBridgeMessage(bridgeMessage);

        vm.prank(localAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, remoteAdapter, messageData, messageId);

        (address whitelabel_, address receiver_, uint256 amount_) = coordinator.lastReleaseCall();
        assertEq(whitelabel_, destWhitelabel.toAddressFromLowBytes());
        assertEq(receiver_, _recipient);
        assertEq(amount_, amount);
    }

    function test_shouldEmit_BridgedIn() public {
        vm.expectEmit();
        emit BridgeMessageCoordinator.BridgedIn(remoteSender, recipient, 500, messageId, bridgeMessage);

        vm.prank(localAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, remoteAdapter, messageData, messageId);
    }
}
