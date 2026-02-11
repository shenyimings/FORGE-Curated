// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Vm } from "forge-std/Vm.sol";

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { ExecutorOptions } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/libs/ExecutorOptions.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import {
    MessagingFee,
    MessagingParams,
    ILayerZeroEndpointV2
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";

import { LayerZeroAdapter } from "../../../src/adapters/LayerZeroAdapter.sol";
import { BaseAdapter } from "../../../src/adapters/BaseAdapter.sol";
import { IBridgeCoordinator } from "../../../src/interfaces/IBridgeCoordinator.sol";
import { Message, MessageType, BridgeMessage } from "../../../src/coordinator/Message.sol";

import { BridgeCoordinatorHarness } from "../../harness/BridgeCoordinatorHarness.sol";

contract LayerZeroAdapterHarness is LayerZeroAdapter {
    constructor(
        IBridgeCoordinator coordinator,
        address owner,
        address endpoint
    )
        LayerZeroAdapter(coordinator, owner, endpoint)
    { }

    function exposedLzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata payload,
        address executor,
        bytes calldata extraData
    )
        external
    {
        _lzReceive(origin, guid, payload, executor, extraData);
    }
}

contract LayerZeroAdapterTest is TestHelperOz5 {
    using PacketV1Codec for bytes;
    LayerZeroAdapterHarness internal l1Adapter;
    LayerZeroAdapterHarness internal l2Adapter;
    BridgeCoordinatorHarness internal coordinator;

    address internal owner = makeAddr("owner");
    address internal unitToken = makeAddr("unitToken");
    address internal refundAddress = makeAddr("refundAddress");
    address internal srcWhitelabel = makeAddr("srcWhitelabel");
    bytes32 internal destWhitelabel = bytes32(uint256(uint160(address(makeAddr("destWhitelabel")))));

    uint16 internal constant EID_L1 = 1;
    uint16 internal constant EID_L2 = 2;

    uint16 internal constant BRIDGE_TYPE = 1;
    uint256 internal constant CHAIN_ID_L2 = 200;
    uint8 internal constant EXECUTOR_WORKER_ID = 1;
    uint8 internal constant OPTION_TYPE_LZRECEIVE = 1;
    bytes32 internal remoteAdapterId;

    function setUp() public override {
        super.setUp();

        setUpEndpoints(2, LibraryType.UltraLightNode);

        coordinator = new BridgeCoordinatorHarness();
        vm.store(address(coordinator), coordinator.exposed_initializableStorageSlot(), bytes32(0));
        coordinator.initialize(unitToken, owner);

        l1Adapter = new LayerZeroAdapterHarness(coordinator, owner, endpoints[EID_L1]);
        l2Adapter = new LayerZeroAdapterHarness(coordinator, owner, endpoints[EID_L2]);

        remoteAdapterId = bytes32(uint256(uint160(address(l2Adapter))));

        vm.startPrank(owner);
        coordinator.workaround_setIsLocalBridgeAdapter(BRIDGE_TYPE, address(l1Adapter), true);
        coordinator.workaround_setOutboundLocalBridgeAdapter(BRIDGE_TYPE, address(l1Adapter));
        coordinator.workaround_setIsRemoteBridgeAdapter(BRIDGE_TYPE, CHAIN_ID_L2, remoteAdapterId, true);
        coordinator.workaround_setOutboundRemoteBridgeAdapter(BRIDGE_TYPE, CHAIN_ID_L2, remoteAdapterId);
        l1Adapter.setRemoteEndpointConfig(CHAIN_ID_L2, EID_L2, remoteAdapterId);
        l2Adapter.setRemoteEndpointConfig(CHAIN_ID_L2, EID_L1, bytes32(uint256(uint160(address(l1Adapter)))));
        vm.stopPrank();
    }

    function buildReceiveOptions(uint128 gasLimit) internal pure returns (bytes memory) {
        bytes memory lzReceiveOption = ExecutorOptions.encodeLzReceiveOption(gasLimit, 0);
        uint16 optionSize = uint16(lzReceiveOption.length + 1);
        return abi.encodePacked(uint16(3), EXECUTOR_WORKER_ID, optionSize, OPTION_TYPE_LZRECEIVE, lzReceiveOption);
    }

    function test_bridgeDispatchesOutboundPacket() public {
        bytes memory message = abi.encode("ping");
        bytes memory bridgeOptions = buildReceiveOptions(200_000);

        uint256 nativeFee = l1Adapter.estimateBridgeFee(CHAIN_ID_L2, message, bridgeOptions);

        vm.deal(address(coordinator), nativeFee);
        vm.prank(address(coordinator));
        bytes32 messageId =
            l1Adapter.bridge{ value: nativeFee }(CHAIN_ID_L2, remoteAdapterId, message, refundAddress, bridgeOptions);

        assertTrue(hasPendingPackets(uint16(EID_L2), remoteAdapterId), "packet not queued");
        assertTrue(messageId != bytes32(0), "messageId not generated");

        bytes memory packet = getNextInflightPacket(uint16(EID_L2), remoteAdapterId);
        this._assertPacketFields(packet, message, messageId, bridgeOptions);
    }

    function test_bridgeRefundsExcessFee() public {
        bytes memory message = abi.encode("refund-test");
        bytes memory bridgeOptions = buildReceiveOptions(200_000);

        uint256 nativeFee = l1Adapter.estimateBridgeFee(CHAIN_ID_L2, message, bridgeOptions);
        uint256 overpayAmount = nativeFee + 1 ether;

        vm.deal(address(coordinator), overpayAmount);
        vm.prank(address(coordinator));
        l1Adapter.bridge{ value: overpayAmount }(CHAIN_ID_L2, remoteAdapterId, message, refundAddress, bridgeOptions);

        assertEq(refundAddress.balance, 1 ether, "refund amount incorrect");
    }

    function test_bridgeRevertsWhenPeerMismatch() public {
        bytes32 originalPeer = l1Adapter.peers(EID_L2);
        bytes32 badPeer = bytes32(uint256(uint160(makeAddr("badPeer"))));

        vm.prank(owner);
        l1Adapter.setPeer(EID_L2, badPeer);

        bytes memory message = abi.encode("peer-mismatch");
        bytes memory bridgeOptions = buildReceiveOptions(200_000);
        uint256 nativeFee = l1Adapter.estimateBridgeFee(CHAIN_ID_L2, message, bridgeOptions);

        vm.deal(address(coordinator), nativeFee);
        vm.expectRevert(abi.encodeWithSelector(LayerZeroAdapter.PeersMismatch.selector, badPeer, remoteAdapterId));
        vm.prank(address(coordinator));
        l1Adapter.bridge{ value: nativeFee }(CHAIN_ID_L2, remoteAdapterId, message, refundAddress, bridgeOptions);

        vm.prank(owner);
        l1Adapter.setPeer(EID_L2, originalPeer);
    }

    function test_bridgeRevertsWhenEndpointUnset() public {
        uint256 unconfiguredChain = 999;
        bytes memory message = abi.encode("missing-endpoint");

        vm.expectRevert(BaseAdapter.InvalidZeroAddress.selector);
        vm.prank(address(coordinator));
        l1Adapter.bridge(unconfiguredChain, remoteAdapterId, message, refundAddress, bytes(""));
    }

    function test_setRemoteEndpointConfigSetsMappingsAndPeer() public {
        uint256 newChainId = 777;
        uint32 newEndpointId = 55;
        bytes32 newRemoteAdapter = bytes32(uint256(uint160(makeAddr("remoteConfig"))));

        vm.prank(owner);
        l1Adapter.setRemoteEndpointConfig(newChainId, newEndpointId, newRemoteAdapter);

        assertEq(l1Adapter.chainIdToEndpointId(newChainId), newEndpointId, "endpoint id not recorded");
        assertEq(l1Adapter.endpointIdToChainId(newEndpointId), newChainId, "chain id reverse mapping not set");
        assertEq(l1Adapter.peers(newEndpointId), newRemoteAdapter, "peer not configured");
    }

    function test_setRemoteEndpointConfigClearsPreviousEndpointMapping() public {
        uint32 originalEndpointId = l1Adapter.chainIdToEndpointId(CHAIN_ID_L2);
        uint32 replacementEndpointId = EID_L1;

        vm.prank(owner);
        l1Adapter.setRemoteEndpointConfig(CHAIN_ID_L2, replacementEndpointId, remoteAdapterId);

        assertEq(l1Adapter.chainIdToEndpointId(CHAIN_ID_L2), replacementEndpointId, "new endpoint not recorded");
        assertEq(
            l1Adapter.endpointIdToChainId(replacementEndpointId), CHAIN_ID_L2, "reverse mapping not updated for new id"
        );
        assertEq(l1Adapter.endpointIdToChainId(originalEndpointId), 0, "stale endpoint mapping not cleared");
    }

    function test_setRemoteEndpointConfigClearsPreviousChainMappingWhenReusingEndpoint() public {
        uint256 otherChainId = 888;
        uint32 sharedEndpointId = l1Adapter.chainIdToEndpointId(CHAIN_ID_L2);
        bytes32 otherRemoteAdapter = bytes32(uint256(uint160(makeAddr("otherRemote"))));

        vm.prank(owner);
        l1Adapter.setRemoteEndpointConfig(otherChainId, sharedEndpointId, otherRemoteAdapter);

        assertEq(l1Adapter.chainIdToEndpointId(otherChainId), sharedEndpointId, "other chain not configured");

        vm.prank(owner);
        l1Adapter.setRemoteEndpointConfig(CHAIN_ID_L2, sharedEndpointId, remoteAdapterId);

        assertEq(l1Adapter.chainIdToEndpointId(CHAIN_ID_L2), sharedEndpointId, "chain not reconfigured");
        assertEq(l1Adapter.endpointIdToChainId(sharedEndpointId), CHAIN_ID_L2, "reverse mapping not reassigned");
        assertEq(l1Adapter.chainIdToEndpointId(otherChainId), 0, "stale chain mapping not cleared");
    }

    function test_setRemoteEndpointConfigRevertsOnZeroInputs() public {
        vm.expectRevert(BaseAdapter.InvalidZeroAddress.selector);
        vm.prank(owner);
        l1Adapter.setRemoteEndpointConfig(0, EID_L2, remoteAdapterId);

        vm.expectRevert(BaseAdapter.InvalidZeroAddress.selector);
        vm.prank(owner);
        l1Adapter.setRemoteEndpointConfig(CHAIN_ID_L2, 0, remoteAdapterId);

        vm.expectRevert(BaseAdapter.InvalidZeroAddress.selector);
        vm.prank(owner);
        l1Adapter.setRemoteEndpointConfig(CHAIN_ID_L2, EID_L2, bytes32(0));
    }

    function test_lzReceiveSettlesInboundMessage() public {
        address remoteUser = makeAddr("remoteUser");
        address recipient = makeAddr("recipient");
        uint256 amount = 42 ether;

        // Encode the bridge message exactly as BridgeCoordinator expects.
        BridgeMessage memory bridgeMessage = BridgeMessage({
            sender: coordinator.encodeOmnichainAddress(remoteUser),
            recipient: coordinator.encodeOmnichainAddress(recipient),
            sourceWhitelabel: coordinator.encodeOmnichainAddress(srcWhitelabel),
            destinationWhitelabel: destWhitelabel,
            amount: amount
        });
        Message memory decodedMessage = Message({ messageType: MessageType.BRIDGE, data: abi.encode(bridgeMessage) });

        bytes memory messageData = abi.encode(decodedMessage);
        bytes32 messageId = keccak256("lz-inbound"); // Mock data in the messageId
        bytes memory payload = abi.encode(messageData, messageId);

        // Build a LayerZero packet sourced from the L2 adapter and destined for L1.
        Packet memory packet = Packet({
            nonce: 1,
            srcEid: EID_L2,
            sender: address(l2Adapter),
            dstEid: EID_L1,
            receiver: bytes32(uint256(uint160(address(l1Adapter)))),
            guid: keccak256("lz-guid"),
            message: payload
        });
        bytes memory packetBytes = PacketV1Codec.encode(packet);
        bytes memory options = buildReceiveOptions(200_000);

        // Queue the packet in the LayerZero test harness.
        this.schedulePacket(packetBytes, options);

        vm.recordLogs();
        // Process the queued packet; this will call _lzReceive on l1Adapter.
        verifyPackets(EID_L1, address(l1Adapter));
        _assertMessageInEvent(vm.getRecordedLogs(), messageId, abi.encode(decodedMessage));

        {
            (address inWhitelabel_, address recipient_, uint256 inAmount_) = coordinator.lastReleaseCall();
            assertEq(
                inWhitelabel_, coordinator.decodeOmnichainAddress(destWhitelabel), "whitelabel mismatch on release"
            );
            assertEq(recipient_, recipient, "recipient mismatch on release");
            assertEq(inAmount_, amount, "amount mismatch on release");
        }

        // Queue should now be empty for this destination.
        assertFalse(
            hasPendingPackets(uint16(EID_L1), bytes32(uint256(uint160(address(l1Adapter))))), "packet queue not drained"
        );
    }

    function test_estimateBridgeFeeUsesLayerZeroQuote() public {
        bytes memory payload = abi.encode("fee-baseline");
        bytes memory options = bytes("");

        bytes memory encodedPayload = abi.encode(payload, l1Adapter.getMessageId(CHAIN_ID_L2));

        MessagingParams memory params = MessagingParams({
            dstEid: EID_L2, receiver: remoteAdapterId, message: encodedPayload, options: options, payInLzToken: false
        });
        MessagingFee memory fee = MessagingFee({ nativeFee: 0.25 ether, lzTokenFee: 0 });
        bytes memory callData = abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector, params, address(l1Adapter));

        vm.mockCall(endpoints[EID_L1], callData, abi.encode(fee));
        vm.expectCall(endpoints[EID_L1], callData);

        uint256 quoted = l1Adapter.estimateBridgeFee(CHAIN_ID_L2, payload, options);
        assertEq(quoted, fee.nativeFee, "fee mismatch");
    }

    function test_estimateBridgeFeeRespectsCustomOptions() public {
        bytes memory payload = abi.encode("fee-options");
        bytes memory options = buildReceiveOptions(350_000);

        bytes memory encodedPayload = abi.encode(payload, l1Adapter.getMessageId(CHAIN_ID_L2));

        MessagingParams memory params = MessagingParams({
            dstEid: EID_L2, receiver: remoteAdapterId, message: encodedPayload, options: options, payInLzToken: false
        });
        MessagingFee memory fee = MessagingFee({ nativeFee: 0.33 ether, lzTokenFee: 0 });
        bytes memory callData = abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector, params, address(l1Adapter));

        vm.mockCall(endpoints[EID_L1], callData, abi.encode(fee));
        vm.expectCall(endpoints[EID_L1], callData);

        uint256 quoted = l1Adapter.estimateBridgeFee(CHAIN_ID_L2, payload, options);
        assertEq(quoted, fee.nativeFee, "custom options fee mismatch");
    }

    function test_estimateBridgeFeeRevertsWithoutEndpoint() public {
        bytes memory payload = abi.encode("missing-endpoint");
        vm.expectRevert(abi.encodeWithSelector(IOAppCore.NoPeer.selector, uint32(0)));
        l1Adapter.estimateBridgeFee(999, payload, bytes(""));
    }

    function test_setRemoteEndpointConfigEmitsEvent() public {
        uint256 newChainId = 555;
        uint32 newEndpointId = 42;
        bytes32 newRemoteAdapter = bytes32(uint256(uint160(makeAddr("remote"))));

        vm.expectEmit(true, true, false, false, address(l1Adapter));
        emit LayerZeroAdapter.EndpointIdConfigured(newChainId, newEndpointId);
        vm.prank(owner);
        l1Adapter.setRemoteEndpointConfig(newChainId, newEndpointId, newRemoteAdapter);
    }

    function test_transferOwnershipFollowsTwoStep() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        l1Adapter.transferOwnership(newOwner);

        assertEq(l1Adapter.owner(), owner, "owner changed prematurely");
        assertEq(l1Adapter.pendingOwner(), newOwner, "pendingOwner not set");

        vm.prank(newOwner);
        l1Adapter.acceptOwnership();

        assertEq(l1Adapter.owner(), newOwner, "ownership not accepted");
        assertEq(l1Adapter.pendingOwner(), address(0), "pendingOwner not cleared");
    }

    function test_bridgeRoundTripEndToEnd() public {
        address user = makeAddr("user");
        address remoteRecipientAddress = makeAddr("remoteRecipient");
        uint256 amount = 77 ether;

        bytes32 remoteRecipient = coordinator.encodeOmnichainAddress(remoteRecipientAddress);
        BridgeMessage memory bridgeMessage = BridgeMessage({
            sender: coordinator.encodeOmnichainAddress(user),
            recipient: remoteRecipient,
            sourceWhitelabel: coordinator.encodeOmnichainAddress(srcWhitelabel),
            destinationWhitelabel: destWhitelabel,
            amount: amount
        });
        Message memory message = Message({ messageType: MessageType.BRIDGE, data: abi.encode(bridgeMessage) });

        bytes memory bridgeOptions = buildReceiveOptions(200_000);
        uint256 nativeFee = l1Adapter.estimateBridgeFee(CHAIN_ID_L2, abi.encode(message), bridgeOptions);

        vm.deal(user, nativeFee);
        vm.startPrank(user);
        vm.recordLogs();
        bytes32 messageId = coordinator.bridge{ value: nativeFee }(
            BRIDGE_TYPE, CHAIN_ID_L2, user, remoteRecipient, srcWhitelabel, destWhitelabel, amount, bridgeOptions
        );
        vm.stopPrank();

        {
            (address outWhitelabel_, address owner_, uint256 outAmount_) = coordinator.lastRestrictCall();
            assertEq(outWhitelabel_, srcWhitelabel, "whitelabel mismatch on restrict");
            assertEq(owner_, user, "recipient mismatch on restrict");
            assertEq(outAmount_, amount, "amount mismatch on restrict");
        }

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertMessageOutEvent(logs, messageId, abi.encode(message));

        assertTrue(hasPendingPackets(EID_L2, remoteAdapterId), "outbound packet missing");
        bytes memory packet = getNextInflightPacket(EID_L2, remoteAdapterId);
        this._assertPacketFields(packet, abi.encode(message), messageId, bridgeOptions);

        vm.startPrank(owner);
        coordinator.workaround_setIsLocalBridgeAdapter(BRIDGE_TYPE, address(l2Adapter), true);
        coordinator.workaround_setIsRemoteBridgeAdapter(
            BRIDGE_TYPE, CHAIN_ID_L2, bytes32(uint256(uint160(address(l1Adapter)))), true
        );
        vm.stopPrank();
        vm.recordLogs();
        verifyPackets(EID_L2, address(l2Adapter));
        logs = vm.getRecordedLogs();
        _assertMessageInEvent(logs, messageId, abi.encode(message));

        {
            (address inWhitelabel_, address recipient_, uint256 inAmount_) = coordinator.lastReleaseCall();
            assertEq(
                inWhitelabel_, coordinator.decodeOmnichainAddress(destWhitelabel), "whitelabel mismatch on release"
            );
            assertEq(recipient_, remoteRecipientAddress, "recipient mismatch on release");
            assertEq(inAmount_, amount, "amount mismatch on release");
        }

        assertFalse(hasPendingPackets(EID_L2, remoteAdapterId), "packet queue not drained");
    }

    function _assertMessageInEvent(
        Vm.Log[] memory entries,
        bytes32 expectedMessageId,
        bytes memory expectedMessage
    )
        internal
        view
    {
        bytes32 bridgedInTopic = keccak256("MessageIn(uint16,uint256,bytes32,bytes)");
        bytes32 expectedBridgeType = bytes32(uint256(BRIDGE_TYPE));
        bytes32 expectedSrcChain = bytes32(uint256(CHAIN_ID_L2));

        bool found;
        for (uint256 i = 0; i < entries.length; ++i) {
            Vm.Log memory entry = entries[i];
            if (entry.emitter != address(coordinator) || entry.topics[0] != bridgedInTopic) continue;

            found = true;
            assertEq(entry.topics[1], expectedBridgeType, "bridge type data mismatch");
            assertEq(entry.topics[2], expectedSrcChain, "srcChainId topic mismatch");
            assertEq(entry.topics[3], expectedMessageId, "messageId data mismatch");
            assertEq(abi.decode(entry.data, (bytes)), expectedMessage, "message data mismatch");
            break;
        }

        assertTrue(found, "BridgedIn event not found");
    }

    function _assertMessageOutEvent(
        Vm.Log[] memory entries,
        bytes32 expectedMessageId,
        bytes memory expectedMessage
    )
        internal
        view
    {
        bytes32 bridgedOutTopic = keccak256("MessageOut(uint16,uint256,bytes32,bytes)");
        bytes32 expectedBridgeType = bytes32(uint256(BRIDGE_TYPE));
        bytes32 expectedDestChain = bytes32(uint256(CHAIN_ID_L2));

        bool found;
        for (uint256 i = 0; i < entries.length; ++i) {
            Vm.Log memory entry = entries[i];
            if (entry.emitter != address(coordinator) || entry.topics[0] != bridgedOutTopic) continue;

            found = true;
            assertEq(entry.topics[1], expectedBridgeType, "bridge type data mismatch");
            assertEq(entry.topics[2], expectedDestChain, "destChainId topic mismatch");
            assertEq(entry.topics[3], expectedMessageId, "messageId data mismatch");
            assertEq(abi.decode(entry.data, (bytes)), expectedMessage, "message data mismatch");
            break;
        }

        assertTrue(found, "BridgedOut event not found");
    }

    function _assertPacketFields(
        bytes calldata packet,
        bytes memory expectedMessage,
        bytes32 expectedMessageId,
        bytes memory expectedOptions
    )
        external
        view
    {
        require(msg.sender == address(this), "self-call only");

        assertEq(packet.dstEid(), EID_L2, "dstEid mismatch");
        assertEq(packet.receiver(), remoteAdapterId, "receiver mismatch");

        (bytes memory forwardedMessage, bytes32 forwardedMessageId) = abi.decode(packet.message(), (bytes, bytes32));
        assertEq(forwardedMessage, expectedMessage, "payload message mismatch");
        assertEq(forwardedMessageId, expectedMessageId, "payload messageId mismatch");

        bytes32 guid = packet.guid();
        assertEq(optionsLookup[guid], expectedOptions, "executor options mismatch");
    }
}
