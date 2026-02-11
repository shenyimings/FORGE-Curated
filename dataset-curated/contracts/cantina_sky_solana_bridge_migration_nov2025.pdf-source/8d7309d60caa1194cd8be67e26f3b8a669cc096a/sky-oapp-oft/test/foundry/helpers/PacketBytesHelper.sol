// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

contract PacketBytesHelper {
    function decodeGuidAndMessage(bytes calldata packetBytes) external pure returns (bytes32 guid, bytes memory message) {
        guid = PacketV1Codec.guid(packetBytes);
        message = PacketV1Codec.message(packetBytes);
    }
}
