// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { LineaBridgeAdapter, BaseAdapter } from "../../../src/adapters/LineaBridgeAdapter.sol";
import { IBridgeCoordinator } from "../../../src/interfaces/IBridgeCoordinator.sol";
import { BridgeMessage } from "../../../src/coordinator/Message.sol";
import { ILineaBridgeAdapter } from "../../../src/interfaces/bridges/linea/ILineaBridgeAdapter.sol";
import { IMessageService } from "../../../src/interfaces/bridges/linea/IMessageService.sol";
import { Bytes32AddressLib } from "../../../src/utils/Bytes32AddressLib.sol";

contract MockBridgeCoordinator is IBridgeCoordinator {
    uint16 public lastBridgeType;
    uint256 public lastChainId;
    bytes32 public lastRemoteSender;
    bytes public lastMessage;
    bytes32 public lastMessageId;
    uint256 public settleInboundCount;

    receive() external payable { }

    mapping(uint16 bridgeType => mapping(uint256 chainId => bytes32 remoteAdapter)) public remoteBridgeAdapters;

    function bridge(uint16, uint256, bytes32, uint256, bytes calldata) external payable returns (bytes32) {
        revert("bridge: not implemented");
    }

    function settleInboundMessage(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 remoteSender,
        bytes calldata message,
        bytes32 messageId
    )
        external
        override
    {
        lastBridgeType = bridgeType;
        lastChainId = chainId;
        lastRemoteSender = remoteSender;
        lastMessage = message;
        lastMessageId = messageId;
        settleInboundCount++;

        bytes32 expectedRemote = remoteBridgeAdapters[bridgeType][chainId];
        if (expectedRemote != bytes32(0)) {
            require(remoteSender == expectedRemote, "Mock: remote adapter mismatch");
        }
    }

    function setRemoteBridgeAdapter(uint16 bridgeType, uint256 chainId, bytes32 adapter) external {
        remoteBridgeAdapters[bridgeType][chainId] = adapter;
    }
}

contract MockMessageService is IMessageService {
    address public senderValue;

    address public lastTo;
    uint256 public lastFee;
    bytes public lastCalldata;
    uint256 public lastValue;
    uint256 public sendCount;

    function setSender(address newSender) external {
        senderValue = newSender;
    }

    function claimMessage(
        address,
        address,
        uint256,
        uint256,
        address payable,
        bytes calldata,
        uint256
    )
        external
        pure
        override
    {
        revert("claimMessage: not implemented");
    }

    function sendMessage(address _to, uint256 _fee, bytes calldata _calldata) external payable override {
        lastValue = msg.value;
        lastTo = _to;
        lastFee = _fee;
        lastCalldata = _calldata;
        sendCount++;
    }

    function sender() external view override returns (address) {
        return senderValue;
    }
}

contract LineaBridgeAdapterTest is Test {
    using Bytes32AddressLib for *;

    MockBridgeCoordinator internal coordinator;
    LineaBridgeAdapter internal adapter;
    MockMessageService internal messageService;

    address internal admin = makeAddr("admin");
    address internal refundAddress = makeAddr("refundAddress");
    address internal srcWhitelabel = address(0);
    bytes32 internal destWhitelabel = bytes32(0);

    uint16 internal constant BRIDGE_TYPE = 2;
    uint256 internal constant L2_CHAIN_ID = 110;
    address internal constant REMOTE_ADDRESS = address(0xBEEF);
    bytes32 internal constant REMOTE_ADAPTER = bytes32(uint256(uint160(REMOTE_ADDRESS)));

    function setUp() public {
        coordinator = new MockBridgeCoordinator();
        adapter = new LineaBridgeAdapter(IBridgeCoordinator(address(coordinator)), admin);
        messageService = new MockMessageService();

        coordinator.setRemoteBridgeAdapter(BRIDGE_TYPE, L2_CHAIN_ID, REMOTE_ADAPTER);
    }

    function _registerMessageService(uint256 chainId, MockMessageService svc) internal {
        vm.prank(admin);
        adapter.setMessageService(address(svc), chainId);
    }

    function test_constructor_revertsWhenAdminZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new LineaBridgeAdapter(IBridgeCoordinator(address(coordinator)), address(0));
    }

    function test_constructor_setsOwner() public view {
        assertEq(adapter.owner(), admin);
    }

    function test_setMessageService_revertsWhenCallerNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        adapter.setMessageService(address(messageService), L2_CHAIN_ID);
    }

    function test_setMessageService_revertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(BaseAdapter.InvalidZeroAddress.selector);
        adapter.setMessageService(address(0), L2_CHAIN_ID);
    }

    function test_setMessageService_updatesMappingsAndEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit LineaBridgeAdapter.MessageServiceConfigured(L2_CHAIN_ID, address(0), address(messageService));

        vm.prank(admin);
        adapter.setMessageService(address(messageService), L2_CHAIN_ID);

        assertEq(address(adapter.chainIdToMessageService(L2_CHAIN_ID)), address(messageService));
        assertEq(adapter.messageServiceToChainId(address(messageService)), L2_CHAIN_ID);

        MockMessageService replacement = new MockMessageService();
        vm.expectEmit(true, true, true, true);
        emit LineaBridgeAdapter.MessageServiceConfigured(L2_CHAIN_ID, address(messageService), address(replacement));

        vm.prank(admin);
        adapter.setMessageService(address(replacement), L2_CHAIN_ID);

        assertEq(address(adapter.chainIdToMessageService(L2_CHAIN_ID)), address(replacement));
        assertEq(adapter.messageServiceToChainId(address(replacement)), L2_CHAIN_ID);
    }

    function test_setMessageService_revokesPreviousService() public {
        _registerMessageService(L2_CHAIN_ID, messageService);

        MockMessageService replacement = new MockMessageService();
        vm.prank(admin);
        adapter.setMessageService(address(replacement), L2_CHAIN_ID);

        bytes memory messageData = abi.encodePacked(uint256(1));
        bytes32 messageId = keccak256(abi.encodePacked(uint256(1)));

        vm.expectRevert(BaseAdapter.UnauthorizedCaller.selector);
        vm.prank(address(messageService));
        adapter.settleInboundBridge(messageData, messageId);
    }

    function test_bridge_revertsWhenCallerNotCoordinator() public {
        bytes memory payload = abi.encodePacked(uint256(123));
        vm.expectRevert(BaseAdapter.UnauthorizedCaller.selector);
        adapter.bridge(L2_CHAIN_ID, REMOTE_ADAPTER, payload, refundAddress, "");
    }

    function test_bridge_forwardsMessageAndReturnsId() public {
        _registerMessageService(L2_CHAIN_ID, messageService);

        bytes memory payload = abi.encode(
            BridgeMessage({
                sender: makeAddr("sender").toBytes32WithLowAddress(),
                recipient: makeAddr("recipient").toBytes32WithLowAddress(),
                sourceWhitelabel: srcWhitelabel.toBytes32WithLowAddress(),
                destinationWhitelabel: destWhitelabel,
                amount: 42
            })
        );

        uint32 nonceBefore = adapter.nonce();
        uint16 bridgeType = adapter.bridgeType();
        uint256 timestampBefore = block.timestamp;

        vm.prank(address(coordinator));
        bytes32 messageId = adapter.bridge(L2_CHAIN_ID, REMOTE_ADAPTER, payload, refundAddress, "");

        bytes32 expectedMessageId = keccak256(abi.encodePacked(L2_CHAIN_ID, bridgeType, timestampBefore, nonceBefore));

        assertEq(messageId, expectedMessageId);
        assertEq(messageService.lastTo(), address(uint160(uint256(REMOTE_ADAPTER))));
        assertEq(messageService.lastFee(), 0);
        assertEq(messageService.lastValue(), 0);
        assertEq(
            messageService.lastCalldata(),
            abi.encodeCall(ILineaBridgeAdapter.settleInboundBridge, (payload, expectedMessageId))
        );
        assertEq(messageService.sendCount(), 1);
    }

    function test_bridge_refundsExcessNativeFee() public {
        _registerMessageService(L2_CHAIN_ID, messageService);

        bytes memory payload = "payload";

        uint256 fee = 1 ether;
        vm.deal(address(coordinator), fee);

        // Since the adapter does not require any native fee, the entire amount should be refunded.
        vm.expectCall(refundAddress, fee, "");

        vm.prank(address(coordinator));
        adapter.bridge{ value: fee }(L2_CHAIN_ID, REMOTE_ADAPTER, payload, refundAddress, "");

        assertEq(refundAddress.balance, fee, "excess fee not refunded");
    }

    function test_settleInboundBridge_revertsWhenUnregisteredService() public {
        bytes memory messageData = abi.encodePacked(uint256(1));
        bytes32 messageId = bytes32(uint256(1));

        vm.expectRevert(BaseAdapter.UnauthorizedCaller.selector);
        vm.prank(makeAddr("randomService"));
        adapter.settleInboundBridge(messageData, messageId);
    }

    function test_settleInboundBridge_notifiesCoordinator() public {
        _registerMessageService(L2_CHAIN_ID, messageService);

        address remoteSender = address(uint160(uint256(REMOTE_ADAPTER)));
        messageService.setSender(remoteSender);

        bytes memory messageData = abi.encode(
            BridgeMessage({
                sender: makeAddr("origin").toBytes32WithLowAddress(),
                recipient: makeAddr("l2Recipient").toBytes32WithLowAddress(),
                sourceWhitelabel: srcWhitelabel.toBytes32WithLowAddress(),
                destinationWhitelabel: destWhitelabel,
                amount: 100
            })
        );

        bytes32 messageId = bytes32(uint256(1));

        vm.prank(address(messageService));
        adapter.settleInboundBridge(messageData, messageId);

        assertEq(coordinator.settleInboundCount(), 1);
        assertEq(coordinator.lastBridgeType(), BRIDGE_TYPE);
        assertEq(coordinator.lastChainId(), L2_CHAIN_ID);
        assertEq(coordinator.lastMessage(), messageData);
        assertEq(coordinator.lastRemoteSender(), bytes32(uint256(uint160(remoteSender))));
        assertEq(coordinator.lastMessageId(), messageId);
    }

    function test_estimateBridgeFee_returnsZero() public view {
        assertEq(adapter.estimateBridgeFee(1, bytes("payload"), ""), 0);
    }
}
