// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IExecutor } from "../interfaces/IExecutor.sol";

library ExecutorDecoder {
    uint8 internal constant NATIVE_DROP_GAS_LIMIT_OFFSET = 0; // uint32
    uint8 internal constant SRC_EID_OFFSET = 4; // uint32
    uint8 internal constant SENDER_OFFSET = 8; // bytes32
    uint8 internal constant NONCE_OFFSET = 40; // uint64
    uint8 internal constant RECEIVER_OFFSET = 48; // address

    uint8 internal constant NATIVEDROP_DST_EID_OFFSET = 68; // uint32
    uint8 internal constant DST_EID_SIZE = 4; // uint32
    function nativeDrop(
        bytes calldata _encoded
    )
        internal
        pure
        returns (
            Origin memory origin,
            uint32 dstEid,
            address receiver,
            IExecutor.NativeDropParams[] memory nativeDropParams,
            uint256 nativeDropGasLimit
        )
    {
        nativeDropGasLimit = uint256(uint32(bytes4(_encoded[NATIVE_DROP_GAS_LIMIT_OFFSET:SRC_EID_OFFSET])));
        origin.srcEid = uint32(bytes4(_encoded[SRC_EID_OFFSET:SENDER_OFFSET]));
        origin.sender = bytes32(_encoded[SENDER_OFFSET:NONCE_OFFSET]);
        origin.nonce = uint64(bytes8(_encoded[NONCE_OFFSET:RECEIVER_OFFSET]));
        receiver = address(bytes20(_encoded[RECEIVER_OFFSET:NATIVEDROP_DST_EID_OFFSET]));

        uint8 nativeDropOffset = NATIVEDROP_DST_EID_OFFSET + DST_EID_SIZE;
        dstEid = uint32(bytes4(_encoded[NATIVEDROP_DST_EID_OFFSET:nativeDropOffset]));

        nativeDropParams = _nativeDrop(_encoded[nativeDropOffset:]);
    }

    uint8 internal constant EXECUTE301_GAS_LIMIT_OFFSET = 0; // uint64
    uint8 internal constant EXECUTE301_PACKET_OFFSET = 8; // uint64
    function execute301(bytes calldata encoded) internal pure returns (bytes memory packet, uint256 gasLimit) {
        gasLimit = uint256(uint64(bytes8(encoded[EXECUTE301_GAS_LIMIT_OFFSET:EXECUTE301_PACKET_OFFSET])));
        packet = encoded[EXECUTE301_PACKET_OFFSET:];
    }

    uint8 internal constant NATIVEDROP_AND_EXECUTE301_GAS_LIMIT_OFFSET = 48; // uint64
    uint8 internal constant NATIVEDROP_AND_EXECUTE301_PACKET_LENGTH_OFFSET = 56; // uint64
    uint8 internal constant NATIVEDROP_AND_EXECUTE301_PACKET_OFFSET = 64; // uint64
    function nativeDropAndExecute301(
        bytes calldata _encoded
    )
        internal
        pure
        returns (
            Origin memory origin,
            IExecutor.NativeDropParams[] memory nativeDropParams,
            uint256 nativeDropGasLimit,
            bytes memory packet,
            uint256 gasLimit
        )
    {
        nativeDropGasLimit = uint256(uint32(bytes4(_encoded[NATIVE_DROP_GAS_LIMIT_OFFSET:SRC_EID_OFFSET])));
        origin.srcEid = uint32(bytes4(_encoded[SRC_EID_OFFSET:SENDER_OFFSET]));
        origin.sender = bytes32(_encoded[SENDER_OFFSET:NONCE_OFFSET]);
        origin.nonce = uint64(bytes8(_encoded[NONCE_OFFSET:NATIVEDROP_AND_EXECUTE301_GAS_LIMIT_OFFSET]));

        gasLimit = uint256(
            uint64(
                bytes8(
                    _encoded[NATIVEDROP_AND_EXECUTE301_GAS_LIMIT_OFFSET:NATIVEDROP_AND_EXECUTE301_PACKET_LENGTH_OFFSET]
                )
            )
        );

        uint64 packetLength = uint64(
            bytes8(_encoded[NATIVEDROP_AND_EXECUTE301_PACKET_LENGTH_OFFSET:NATIVEDROP_AND_EXECUTE301_PACKET_OFFSET])
        );

        uint256 cursor = NATIVEDROP_AND_EXECUTE301_PACKET_OFFSET;

        packet = _encoded[cursor:cursor + packetLength];
        cursor += packetLength;

        nativeDropParams = _nativeDrop(_encoded[cursor:]);
    }

    uint8 internal constant EXECUTE302_GUID_OFFSET = 68; // bytes32
    uint8 internal constant EXECUTE302_GAS_LIMIT_OFFSET = 100; // uint64
    uint8 internal constant EXECUTE302_MESSAGE_LENGTH_OFFSET = 108; // uint64
    uint8 internal constant EXECUTE302_MESSAGE_OFFSET = 116; // uint64
    uint8 internal constant EXTRA_DATA_LENGTH_SIZE = 8; // uint64
    function nativeDropAndExecute302(
        bytes calldata _encoded
    )
        internal
        pure
        returns (
            IExecutor.NativeDropParams[] memory nativeDropParams,
            uint256 nativeDropGasLimit,
            IExecutor.ExecutionParams memory executionParams
        )
    {
        nativeDropGasLimit = uint256(uint32(bytes4(_encoded[NATIVE_DROP_GAS_LIMIT_OFFSET:SRC_EID_OFFSET])));
        executionParams.origin.srcEid = uint32(bytes4(_encoded[SRC_EID_OFFSET:SENDER_OFFSET]));
        executionParams.origin.sender = bytes32(_encoded[SENDER_OFFSET:NONCE_OFFSET]);
        executionParams.origin.nonce = uint64(bytes8(_encoded[NONCE_OFFSET:RECEIVER_OFFSET]));
        executionParams.receiver = address(bytes20(_encoded[RECEIVER_OFFSET:EXECUTE302_GUID_OFFSET]));
        executionParams.guid = bytes32(_encoded[EXECUTE302_GUID_OFFSET:EXECUTE302_GAS_LIMIT_OFFSET]);
        executionParams.gasLimit = uint256(
            uint64(bytes8(_encoded[EXECUTE302_GAS_LIMIT_OFFSET:EXECUTE302_MESSAGE_LENGTH_OFFSET]))
        );

        uint64 messageLength = uint64(bytes8(_encoded[EXECUTE302_MESSAGE_LENGTH_OFFSET:EXECUTE302_MESSAGE_OFFSET]));
        uint256 cursor = EXECUTE302_MESSAGE_OFFSET;

        executionParams.message = _encoded[cursor:cursor + messageLength];
        cursor += messageLength;

        uint64 extraDataLength = uint64(bytes8(_encoded[cursor:cursor + EXTRA_DATA_LENGTH_SIZE]));
        cursor += EXTRA_DATA_LENGTH_SIZE;

        executionParams.extraData = _encoded[cursor:cursor + extraDataLength];
        cursor += extraDataLength;

        nativeDropParams = _nativeDrop(_encoded[cursor:]);
    }

    uint8 internal constant NATIVE_DROP_RECEIVER_SIZE = 20; // address
    uint8 internal constant NATIVE_DROP_AMOUNT_SIZE = 9; // uint72
    uint8 internal constant NATIVE_DROP_PARAM_SIZE = 29; // 20 + 9
    function _nativeDrop(
        bytes calldata _encoded
    ) internal pure returns (IExecutor.NativeDropParams[] memory nativeDropParams) {
        uint256 cursor = 0;
        uint256 nativeDropParamsLength = _encoded.length / NATIVE_DROP_PARAM_SIZE;

        nativeDropParams = new IExecutor.NativeDropParams[](nativeDropParamsLength);
        for (uint256 i = 0; i < nativeDropParamsLength; i++) {
            nativeDropParams[i].receiver = address(bytes20(_encoded[cursor:cursor + NATIVE_DROP_RECEIVER_SIZE]));
            cursor += NATIVE_DROP_RECEIVER_SIZE;
            nativeDropParams[i].amount = uint256(uint72(bytes9(_encoded[cursor:cursor + NATIVE_DROP_AMOUNT_SIZE])));
            cursor += NATIVE_DROP_AMOUNT_SIZE;
        }
    }
}
