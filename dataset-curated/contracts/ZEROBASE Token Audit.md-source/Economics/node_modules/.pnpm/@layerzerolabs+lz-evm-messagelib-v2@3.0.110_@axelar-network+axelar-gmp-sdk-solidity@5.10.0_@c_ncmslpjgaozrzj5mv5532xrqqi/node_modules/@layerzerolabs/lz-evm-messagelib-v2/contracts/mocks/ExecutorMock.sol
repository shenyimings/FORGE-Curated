// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { IExecutor } from "../../contracts/interfaces/IExecutor.sol";

contract ExecutorMock {
    using PacketV1Codec for bytes;

    event NativeDropMeta(
        uint32 srcEid,
        bytes32 sender,
        uint64 nonce,
        uint32 dstEid,
        address oapp,
        uint256 nativeDropGasLimit
    );
    event NativeDropped(address receiver, uint256 amount);
    event Executed301(bytes packet, uint256 gasLimit);
    event Executed302(
        uint32 srcEid,
        bytes32 sender,
        uint64 nonce,
        address receiver,
        bytes32 guid,
        bytes message,
        bytes extraData,
        uint256 gasLimit
    );

    uint32 public immutable dstEid;

    constructor(uint32 _dstEid) {
        dstEid = _dstEid;
    }

    function nativeDrop(
        Origin calldata _origin,
        uint32 _dstEid,
        address _oapp,
        IExecutor.NativeDropParams[] calldata _nativeDropParams,
        uint256 _nativeDropGasLimit
    ) external payable {
        _nativeDrop(_origin, _dstEid, _oapp, _nativeDropParams, _nativeDropGasLimit);
    }

    function nativeDropAndExecute301(
        Origin calldata _origin,
        IExecutor.NativeDropParams[] calldata _nativeDropParams,
        uint256 _nativeDropGasLimit,
        bytes calldata _packet,
        uint256 _gasLimit
    ) external payable {
        _nativeDrop(_origin, _packet.dstEid(), _packet.receiverB20(), _nativeDropParams, _nativeDropGasLimit);
        emit Executed301(_packet, _gasLimit);
    }

    function execute301(bytes calldata _packet, uint256 _gasLimit) external {
        emit Executed301(_packet, _gasLimit);
    }

    function nativeDropAndExecute302(
        IExecutor.NativeDropParams[] calldata _nativeDropParams,
        uint256 _nativeDropGasLimit,
        IExecutor.ExecutionParams calldata _executionParams
    ) external payable {
        _nativeDrop(_executionParams.origin, dstEid, _executionParams.receiver, _nativeDropParams, _nativeDropGasLimit);

        emit Executed302(
            _executionParams.origin.srcEid,
            _executionParams.origin.sender,
            _executionParams.origin.nonce,
            _executionParams.receiver,
            _executionParams.guid,
            _executionParams.message,
            _executionParams.extraData,
            _executionParams.gasLimit
        );
    }

    function _nativeDrop(
        Origin calldata _origin,
        uint32 _dstEid,
        address _oapp,
        IExecutor.NativeDropParams[] calldata _nativeDropParams,
        uint256 _nativeDropGasLimit
    ) internal {
        for (uint256 i = 0; i < _nativeDropParams.length; i++) {
            emit NativeDropped(_nativeDropParams[i].receiver, _nativeDropParams[i].amount);
        }
        emit NativeDropMeta(_origin.srcEid, _origin.sender, _origin.nonce, _dstEid, _oapp, _nativeDropGasLimit);
    }
}
