// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { PacketBytesHelper } from "../foundry/helpers/PacketBytesHelper.sol";
import { GovernanceOAppSender } from "../../contracts/GovernanceOAppSender.sol";
import { GovernanceOAppReceiver, MessageOrigin } from "../../contracts/GovernanceOAppReceiver.sol";
import { ILayerZeroEndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract MockControlledContractNestedDelivery is Test {
    uint32 aEid = 1;
    GovernanceOAppSender aGov;
    GovernanceOAppReceiver bGov;
    address originCaller;
    bytes packetTwoBytes;

    constructor(GovernanceOAppSender _aGov, GovernanceOAppReceiver _bGov, address _originCaller) {
        aGov = _aGov;
        bGov = _bGov;
        originCaller = _originCaller;
    }

    function setPacketBytes(bytes calldata _bytes) external {
        packetTwoBytes = _bytes;
    }

    function deliverNestedPacket() external {
        MessageOrigin memory origin = bGov.messageOrigin();
        require(origin.srcEid == aEid, "src eid mismatch");
        require(origin.srcSender == addressToBytes32(originCaller), "origin caller mismatch");

        (bytes32 guidTwo, bytes memory messageTwo) = new PacketBytesHelper().decodeGuidAndMessage(packetTwoBytes);

        ILayerZeroEndpointV2(bGov.endpoint()).lzReceive(Origin({ srcEid: aEid, sender: addressToBytes32(address(aGov)), nonce: 2 }), address(bGov), guidTwo, messageTwo, bytes(""));

        MessageOrigin memory origin2 = bGov.messageOrigin();
        require(origin2.srcEid == aEid, "src eid 2 mismatch");
        require(origin2.srcSender == addressToBytes32(originCaller), "origin caller 2 mismatch");
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}