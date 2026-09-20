// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20Mock } from "@layerzerolabs/oft-evm/test/mocks/ERC20Mock.sol";
import { ILayerZeroEndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { GovernanceControllerOApp } from "../../contracts/GovernanceControllerOApp.sol";
import { GovernanceMessageEVMCodec } from "../../contracts/GovernanceMessageEVMCodec.sol";
import { GovernanceAction } from "../../contracts/IGovernanceController.sol";
import { MockControlledContract } from "../mocks/MockControlledContract.sol";
import { MockGovernanceRelay } from "../mocks/MockGovernanceRelay.sol";
import { MockSpell } from "../mocks/MockSpell.sol";
import { TestHelperOz5WithRevertAssertions } from "./helpers/TestHelperOz5WithRevertAssertions.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { PacketBytesHelper } from "./helpers/PacketBytesHelper.sol";
import { MockControlledContractNestedDelivery } from "../mocks/MockControlledContractNestedDelivery.sol";
import { MockFundsReceiver } from "../mocks/MockFundsReceiver.sol";

contract GovernanceControllerOAppTest is TestHelperOz5WithRevertAssertions {
    using OptionsBuilder for bytes;

    uint32 aEid = 1;
    uint32 bEid = 2;

    GovernanceControllerOApp aGov;
    GovernanceControllerOApp bGov;

    MockGovernanceRelay aRelay;
    MockGovernanceRelay bRelay;

    MockControlledContract aControlledContract;
    MockControlledContract bControlledContract;

    address NOT_OWNER = makeAddr("NOT_OWNER");
    address THIEF = makeAddr("THIEF");

    /// @notice Calls setUp from TestHelper and initializes contract instances for testing.
    function setUp() public virtual override {
        super.setUp();

        // Setup function to initialize 2 Mock Endpoints with Mock MessageLib.
        setUpEndpoints(2, LibraryType.UltraLightNode);

        aGov = new GovernanceControllerOApp(
            endpoints[aEid],
            address(this), // delegate/owner
            false, // addInitialValidTarget
            0, // initialValidTargetSrcEid
            bytes32(0), // initialValidTargetOriginCaller
            address(0) // initialValidTargetGovernedContract
        );

        bGov = new GovernanceControllerOApp(
            endpoints[bEid],
            address(this), // delegate/owner
            false, // addInitialValidTarget
            0, // initialValidTargetSrcEid
            bytes32(0), // initialValidTargetOriginCaller
            address(0) // initialValidTargetGovernedContract
        );

        // Setup peers
        aGov.setPeer(bEid, addressToBytes32(address(bGov)));
        bGov.setPeer(aEid, addressToBytes32(address(aGov)));

        aRelay = new MockGovernanceRelay(aGov, addressToBytes32(address(this)), bEid);
        bRelay = new MockGovernanceRelay(bGov, addressToBytes32(address(this)), aEid);

        aControlledContract = new MockControlledContract(address(aRelay));
        bControlledContract = new MockControlledContract(address(bRelay));

        aGov.addValidCaller(address(this));

        // Add necessary valid target entries for the tests to pass
        aGov.addValidTarget(bEid, addressToBytes32(address(this)), address(aRelay));
        bGov.addValidTarget(aEid, addressToBytes32(address(this)), address(bRelay));
    }

    function test_send() public {
        string memory dataBefore = bControlledContract.data();

        // Generates 1 lzReceive execution option via the OptionsBuilder library.
        // STEP 0: Estimating message gas fees via the quote function.
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        // STEP 1: Sending a message via the _lzSend() method.
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        // Asserting that the receiving OApps have NOT had data manipulated.
        assertEq(bControlledContract.data(), dataBefore, "shouldn't be changed until lzReceive packet is verified");

        // STEP 2 & 3: Deliver packet to bGov manually.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));

        // Asserting that the data variable has updated in the receiving OApp.
        assertEq(bControlledContract.data(), "test message", "lzReceive data assertion failure");

        // Asserting that the origin caller and eid are reset after governed contract execution.
        (uint32 originEid, bytes32 originCaller) = aGov.messageOrigin();

        assertEq(originEid, 0);
        assertEq(originCaller, bytes32(0));
    }

    function test_send_with_governed_contract_revert() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.revertTest.selector)
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodePacked(MockGovernanceRelay.TestRevert.selector), "");
    }

    function test_send_with_governed_contract_revert_no_data() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.revertTestNoData.selector)
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodePacked(GovernanceControllerOApp.GovernanceCallFailed.selector), "");
    }

    function test_send_with_valid_caller_enforcement() public {
        aGov.removeValidCaller(address(this));
        assertEq(aGov.validCallers(address(this)), false);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        vm.expectRevert(GovernanceControllerOApp.InvalidCaller.selector);
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        aGov.addValidCaller(address(this));
        assertEq(aGov.validCallers(address(this)), true);
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        aGov.removeValidCaller(address(this));
        assertEq(aGov.validCallers(address(this)), false);
        vm.expectRevert(GovernanceControllerOApp.InvalidCaller.selector);
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));
    }

    function test_valid_caller_management() public {
        vm.prank(NOT_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NOT_OWNER));
        aGov.addValidCaller(address(0x123));

        vm.prank(NOT_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NOT_OWNER));
        aGov.removeValidCaller(address(0x123));

        aGov.addValidCaller(address(0x123));
        assertEq(aGov.validCallers(address(0x123)), true);

        aGov.removeValidCaller(address(0x123));
        assertEq(aGov.validCallers(address(0x123)), false);
    }

    function test_valid_target_management() public {
        uint32 srcEid = 123;
        bytes32 originCaller = bytes32(uint256(uint160(address(0x456))));
        address governedContract = address(0x789);

        // Test unauthorized access
        vm.prank(NOT_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NOT_OWNER));
        aGov.addValidTarget(srcEid, originCaller, governedContract);

        // Test initial state
        assertEq(aGov.validTargets(srcEid, originCaller, governedContract), false);

        // Test adding to valid target list
        aGov.addValidTarget(srcEid, originCaller, governedContract);
        assertEq(aGov.validTargets(srcEid, originCaller, governedContract), true);

        // Test removing from valid target list
        aGov.removeValidTarget(srcEid, originCaller, governedContract);
        assertEq(aGov.validTargets(srcEid, originCaller, governedContract), false);
    }

    function test_valid_target_enforcement() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        // Remove from valid target list
        bGov.removeValidTarget(aEid, addressToBytes32(address(this)), address(bRelay));

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        // Should fail due to valid target check
        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodePacked(GovernanceControllerOApp.InvalidTarget.selector), "");

        // Add back to valid target list
        bGov.addValidTarget(aEid, addressToBytes32(address(this)), address(bRelay));

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        // Should succeed now
        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));
        assertEq(bControlledContract.data(), "test message", "lzReceive data assertion failure");
    }

    function test_constructor_initializes_valid_target_list() public {
        // Test that the constructor properly initializes the valid target list
        bytes32 pauseProxy = addressToBytes32(address(this));
        uint32 initialSrcEid = 999;
        address delegate = address(0x123);

        GovernanceControllerOApp testGov = new GovernanceControllerOApp(
            endpoints[aEid],
            delegate,
            true, // addInitialValidTarget
            initialSrcEid, // initialValidSrcEid
            pauseProxy, // initialValidOriginCaller
            address(0x123) // initialValidGovernedContract
        );

        // Check that the initial valid target entry was created
        assertEq(testGov.validTargets(initialSrcEid, pauseProxy, delegate), true);
    }

    function test_reentrancy_lz_receive() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockControlledContractNestedDelivery controllerNestedDelivery = new MockControlledContractNestedDelivery(aGov, bGov, address(this));

        // Add valid target entry for the nested delivery contract
        bGov.addValidTarget(aEid, addressToBytes32(address(this)), address(controllerNestedDelivery));

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(controllerNestedDelivery),
            callData: abi.encodeWithSelector(controllerNestedDelivery.deliverNestedPacket.selector)
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        bytes32 packetOneGuid = keccak256(abi.encodePacked(uint64(1), uint32(aEid), addressToBytes32(address(aGov)), uint32(bEid), addressToBytes32(address(bGov))));
        bytes memory packetOneBytes = abi.encodePacked(
            hex"01000000000000000100000001000000000000000000000000",
            address(aGov),
            hex"00000002000000000000000000000000",
            address(bGov),
            packetOneGuid,
            GovernanceMessageEVMCodec.encode(message)
        );

        bytes32 packetTwoGuid = keccak256(abi.encodePacked(uint64(2), uint32(aEid), addressToBytes32(address(aGov)), uint32(bEid), addressToBytes32(address(bGov))));
        bytes memory packetTwoBytes = abi.encodePacked(
            hex"01000000000000000200000001000000000000000000000000",
            address(aGov),
            hex"00000002000000000000000000000000",
            address(bGov),
            packetTwoGuid,
            GovernanceMessageEVMCodec.encode(message)
        );
        
        TestHelperOz5WithRevertAssertions(payable(address(this))).validatePacket(packetOneBytes);
        TestHelperOz5WithRevertAssertions(payable(address(this))).validatePacket(packetTwoBytes);

        (bytes32 guidOne, bytes memory messageOne) = new PacketBytesHelper().decodeGuidAndMessage(packetOneBytes);

        controllerNestedDelivery.setPacketBytes(packetTwoBytes);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        ILayerZeroEndpointV2(endpoints[bEid]).lzReceive(Origin({ srcEid: aEid, sender: addressToBytes32(address(aGov)), nonce: 1 }), address(bGov), guidOne, messageOne, bytes(""));
    }

    function test_send_unauthorized_origin_caller() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(0xdead)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        vm.expectRevert(GovernanceControllerOApp.UnauthorizedOriginCaller.selector);
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));
    }

    function test_send_raw_bytes() public {
        string memory dataBefore = bControlledContract.data();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        bytes memory messageBytes = GovernanceMessageEVMCodec.encode(message);
        MessagingFee memory fee = aGov.quoteRawBytesAction(messageBytes, bEid, options, false);

        aGov.sendRawBytesAction{ value: fee.nativeFee }(messageBytes, bEid, options, fee, address(this));

        // Asserting that the receiving OApps have NOT had data manipulated.
        assertEq(bControlledContract.data(), dataBefore, "shouldn't be changed until lzReceive packet is verified");

        // STEP 2 & 3: Deliver packet to bGov manually.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));

        // Asserting that the data variable has updated in the receiving OApp.
        assertEq(bControlledContract.data(), "test message", "lzReceive data assertion failure");
    }

    function test_sending_garbage_in_origin_caller_reverts() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        bytes32 originCallerWithGarbage = bytes32(abi.encodePacked(bytes12(type(uint96).max), address(this)));
        
        GovernanceMessageEVMCodec.GovernanceMessage memory messageWithGarbage = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: originCallerWithGarbage,
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(messageWithGarbage, bEid, options, false);

        vm.expectRevert(GovernanceControllerOApp.UnauthorizedOriginCaller.selector);
        aGov.sendEVMAction{ value: fee.nativeFee }(messageWithGarbage, bEid, options, fee, address(this));

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: bytes32(abi.encodePacked(bytes12(0), address(this))),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));
    }

    function test_send_no_calldata_just_value() public {
        MockFundsReceiver fundsReceiver = new MockFundsReceiver();

        // Add valid target entry for the funds receiver
        bGov.addValidTarget(aEid, addressToBytes32(address(this)), address(fundsReceiver));

        assertEq(address(fundsReceiver).balance, 0);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 1e10);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(fundsReceiver),
            callData: ""
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));

        assertEq(address(fundsReceiver).balance, 1e10);
    }

    function test_revert_invalid_governed_contract_endpoint() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        // Add valid target entry for the endpoint (though it should still revert)
        bGov.addValidTarget(aEid, addressToBytes32(address(this)), address(endpoints[bEid]));

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(endpoints[bEid]),
            callData: ""
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodeWithSelector(GovernanceControllerOApp.InvalidGovernedContract.selector, address(endpoints[bEid])), "");
    }

    function test_governed_contract_can_be_zero_address() public {
        address lzToken = ILayerZeroEndpointV2(endpoints[bEid]).lzToken();

        // Add valid target entry for the lzToken
        bGov.addValidTarget(aEid, addressToBytes32(address(this)), address(lzToken));

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(lzToken),
            callData: ""
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));
    }

    function test_revert_invalid_governed_contract_lz_token() public {
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(endpoints[bEid]);

        ERC20Mock lzTokenMock = new ERC20Mock("ZRO", "ZRO");
        lzTokenMock.mint(address(this), 10 ether);

        endpoint.setLzToken(address(lzTokenMock));
        assertEq(endpoint.lzToken(), address(lzTokenMock));

        lzTokenMock.approve(address(aGov), 10 ether);

        // Add valid target entry for the lzToken (though it should still revert)
        bGov.addValidTarget(aEid, addressToBytes32(address(this)), address(lzTokenMock));

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(lzTokenMock),
            callData: abi.encodeWithSelector(lzTokenMock.transferFrom.selector, address(this), THIEF, 10 ether)
        });
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodeWithSelector(GovernanceControllerOApp.InvalidGovernedContract.selector, address(lzTokenMock)), "");

        assertEq(lzTokenMock.balanceOf(THIEF), 0);
    }

}
