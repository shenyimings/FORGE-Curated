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

import { GovernanceOAppSender } from "../../contracts/GovernanceOAppSender.sol";
import { GovernanceOAppReceiver } from "../../contracts/GovernanceOAppReceiver.sol";
import { IGovernanceOAppSender, TxParams } from "../../contracts/interfaces/IGovernanceOAppSender.sol";
import { IGovernanceOAppReceiver, MessageOrigin } from "../../contracts/interfaces/IGovernanceOAppReceiver.sol";
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

    GovernanceOAppSender aGov;
    GovernanceOAppReceiver bGov;

    MockGovernanceRelay bRelay;

    MockControlledContract bControlledContract;

    address NOT_OWNER = makeAddr("NOT_OWNER");
    address THIEF = makeAddr("THIEF");

    /// @notice Calls setUp from TestHelper and initializes contract instances for testing.
    function setUp() public virtual override {
        super.setUp();

        // Setup function to initialize 2 Mock Endpoints with Mock MessageLib.
        setUpEndpoints(2, LibraryType.UltraLightNode);

        aGov = new GovernanceOAppSender(
            endpoints[aEid], // LayerZero endpoint
            address(this) // delegate/owner
        );

        bGov = new GovernanceOAppReceiver(
            aEid, // governanceOAppSenderEid
            addressToBytes32(address(aGov)), // governanceOAppSenderAddress
            endpoints[bEid], // LayerZero endpoint
            address(this) // delegate/owner
        );

        aGov.setPeer(bEid, addressToBytes32(address(bGov)));

        bRelay = new MockGovernanceRelay(bGov, addressToBytes32(address(this)), aEid);

        bControlledContract = new MockControlledContract(address(bRelay));

        aGov.setCanCallTarget(address(this), bEid, addressToBytes32(address(bRelay)), true);
    }

    function test_send() public {
        string memory dataBefore = bControlledContract.data();

        MockSpell spell = new MockSpell(bControlledContract);

        TxParams memory txParams = TxParams({
            dstEid: bEid,
            dstTarget: addressToBytes32(address(bRelay)),
            dstCallData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector)),
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0)
        });

        MessagingFee memory fee = aGov.quoteTx(txParams, false);

        aGov.sendTx{ value: fee.nativeFee }(txParams, fee, address(this));

        // Asserting that the receiving OApps have NOT had data manipulated.
        assertEq(bControlledContract.data(), dataBefore, "shouldn't be changed until lzReceive packet is verified");

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));

        // Asserting that the data variable has updated in the receiving OApp.
        assertEq(bControlledContract.data(), "test message", "lzReceive data assertion failure");

        // Asserting that the origin caller and eid are reset after governed contract execution.
        MessageOrigin memory origin = bGov.messageOrigin();

        assertEq(origin.srcEid, 0);
        assertEq(origin.srcSender, bytes32(0));
    }

    function test_send_with_governed_contract_revert() public {
        TxParams memory txParams = TxParams({
            dstEid: bEid,
            dstTarget: addressToBytes32(address(bRelay)),
            dstCallData: abi.encodeWithSelector(bRelay.revertTest.selector),
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0)
        });
        MessagingFee memory fee = aGov.quoteTx(txParams, false);

        aGov.sendTx{ value: fee.nativeFee }(txParams, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodePacked(MockGovernanceRelay.TestRevert.selector), "");
    }

    function test_send_with_governed_contract_revert_no_data() public {
        TxParams memory txParams = TxParams({
            dstEid: bEid,
            dstTarget: addressToBytes32(address(bRelay)),
            dstCallData: abi.encodeWithSelector(bRelay.revertTestNoData.selector),
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0)
        });
        MessagingFee memory fee = aGov.quoteTx(txParams, false);

        aGov.sendTx{ value: fee.nativeFee }(txParams, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodePacked(IGovernanceOAppReceiver.GovernanceCallFailed.selector), "");
    }

    function test_send_with_valid_caller_enforcement() public {
        aGov.setCanCallTarget(address(this), bEid, addressToBytes32(address(bRelay)), false);

        MockSpell spell = new MockSpell(bControlledContract);

        TxParams memory txParams = TxParams({
            dstEid: bEid,
            dstTarget: addressToBytes32(address(bRelay)),
            dstCallData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector)),
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0)
        });
        MessagingFee memory fee = aGov.quoteTx(txParams, false);

        vm.expectRevert(IGovernanceOAppSender.CannotCallTarget.selector);
        aGov.sendTx{ value: fee.nativeFee }(txParams, fee, address(this));

        aGov.setCanCallTarget(address(this), bEid, addressToBytes32(address(bRelay)), true);
        aGov.sendTx{ value: fee.nativeFee }(txParams, fee, address(this));
    }

    function test_valid_caller_management() public {
        vm.prank(NOT_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NOT_OWNER));
        aGov.setCanCallTarget(address(0x123), bEid, addressToBytes32(address(bRelay)), true);

        vm.prank(NOT_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NOT_OWNER));
        aGov.setCanCallTarget(address(0x123), bEid, addressToBytes32(address(bRelay)), false);

        aGov.setCanCallTarget(address(0x123), bEid, addressToBytes32(address(bRelay)), true);
        assertEq(aGov.canCallTarget(address(0x123), bEid, addressToBytes32(address(bRelay))), true);

        aGov.setCanCallTarget(address(0x123), bEid, addressToBytes32(address(bRelay)), false);
        assertEq(aGov.canCallTarget(address(0x123), bEid, addressToBytes32(address(bRelay))), false);
    }

    function test_reentrancy_lz_receive() public {
        MockControlledContractNestedDelivery controllerNestedDelivery = new MockControlledContractNestedDelivery(aGov, bGov, address(this));

        aGov.setCanCallTarget(address(this), bEid, addressToBytes32(address(controllerNestedDelivery)), true);

        TxParams memory txParams = TxParams({
            dstEid: bEid,
            dstTarget: addressToBytes32(address(controllerNestedDelivery)),
            dstCallData: abi.encodeWithSelector(controllerNestedDelivery.deliverNestedPacket.selector),
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0)
        });
        MessagingFee memory fee = aGov.quoteTx(txParams, false);

        aGov.sendTx{ value: fee.nativeFee }(txParams, fee, address(this));
        aGov.sendTx{ value: fee.nativeFee }(txParams, fee, address(this));

        bytes32 packetOneGuid = keccak256(abi.encodePacked(uint64(1), uint32(aEid), addressToBytes32(address(aGov)), uint32(bEid), addressToBytes32(address(bGov))));
        bytes memory packetOneBytes = abi.encodePacked(
            hex"01000000000000000100000001000000000000000000000000",
            address(aGov),
            hex"00000002000000000000000000000000",
            address(bGov),
            packetOneGuid,
            abi.encodePacked(addressToBytes32(address(this)), txParams.dstTarget, txParams.dstCallData)
        );

        bytes32 packetTwoGuid = keccak256(abi.encodePacked(uint64(2), uint32(aEid), addressToBytes32(address(aGov)), uint32(bEid), addressToBytes32(address(bGov))));
        bytes memory packetTwoBytes = abi.encodePacked(
            hex"01000000000000000200000001000000000000000000000000",
            address(aGov),
            hex"00000002000000000000000000000000",
            address(bGov),
            packetTwoGuid,
            abi.encodePacked(addressToBytes32(address(this)), txParams.dstTarget, txParams.dstCallData)
        );
        
        TestHelperOz5WithRevertAssertions(payable(address(this))).validatePacket(packetOneBytes);
        TestHelperOz5WithRevertAssertions(payable(address(this))).validatePacket(packetTwoBytes);

        (bytes32 guidOne, bytes memory messageOne) = new PacketBytesHelper().decodeGuidAndMessage(packetOneBytes);

        controllerNestedDelivery.setPacketBytes(packetTwoBytes);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        ILayerZeroEndpointV2(endpoints[bEid]).lzReceive(Origin({ srcEid: aEid, sender: addressToBytes32(address(aGov)), nonce: 1 }), address(bGov), guidOne, messageOne, bytes(""));
    }

    function test_send_unauthorized_origin_caller() public {
        vm.deal(THIEF, 100 ether);
        aGov.setCanCallTarget(THIEF, bEid, addressToBytes32(address(bRelay)), true);

        MockSpell spell = new MockSpell(bControlledContract);

        TxParams memory txParams = TxParams({
            dstEid: bEid,
            dstTarget: addressToBytes32(address(bRelay)),
            dstCallData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector)),
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0)
        });
        MessagingFee memory fee = aGov.quoteTx(txParams, false);

        vm.prank(THIEF);
        aGov.sendTx{ value: fee.nativeFee }(txParams, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodePacked(MockGovernanceRelay.UnauthorizedOriginCaller.selector), "");
    }

    function test_send_no_calldata_just_value() public {
        MockFundsReceiver fundsReceiver = new MockFundsReceiver();

        // Add valid target entry for the funds receiver
        aGov.setCanCallTarget(address(this), bEid, addressToBytes32(address(fundsReceiver)), true);

        assertEq(address(fundsReceiver).balance, 0);

        TxParams memory txParams = TxParams({
            dstEid: bEid,
            dstTarget: addressToBytes32(address(fundsReceiver)),
            dstCallData: "",
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 1e10)
        });
        MessagingFee memory fee = aGov.quoteTx(txParams, false);

        aGov.sendTx{ value: fee.nativeFee }(txParams, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));

        assertEq(address(fundsReceiver).balance, 1e10);
    }

    function test_governed_contract_can_be_zero_address() public {
        aGov.setCanCallTarget(address(this), bEid, addressToBytes32(address(0)), true);

        TxParams memory txParams = TxParams({
            dstEid: bEid,
            dstTarget: addressToBytes32(address(0)),
            dstCallData: "",
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0)
        });
        MessagingFee memory fee = aGov.quoteTx(txParams, false);

        aGov.sendTx{ value: fee.nativeFee }(txParams, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));
    }
}
