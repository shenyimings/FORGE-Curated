// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;

contract PacketData {
    event Packet(uint16 chainId, bytes payload);
    event Packet(bytes payload);

    function emitPacketV1(
        uint64 nonce,
        address ua,
        uint16 dstChainId,
        address dstAddress,
        bytes calldata payload
    ) public {
        bytes memory encodedPayload = abi.encodePacked(nonce, ua, dstAddress, payload);
        emit Packet(dstChainId, encodedPayload);
    }

    function emitPacketV2(
        uint64 nonce,
        uint16 localChainId,
        address ua,
        uint16 dstChainId,
        address dstAddress,
        bytes calldata payload
    ) public {
        bytes memory encodedPayload = abi.encodePacked(nonce, localChainId, ua, dstChainId, dstAddress, payload);
        emit Packet(encodedPayload);
    }
}
