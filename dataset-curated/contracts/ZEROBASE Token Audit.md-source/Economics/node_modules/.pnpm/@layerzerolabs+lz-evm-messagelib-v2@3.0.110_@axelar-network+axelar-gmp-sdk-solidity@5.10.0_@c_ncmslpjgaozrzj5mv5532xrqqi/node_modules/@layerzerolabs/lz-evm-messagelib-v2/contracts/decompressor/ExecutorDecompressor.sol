// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { Executor } from "../Executor.sol";
import { ExecutorDecoder } from "./ExecutorDecoder.sol";
import { DecompressorExtension } from "./DecompressorExtension.sol";

contract ExecutorDecompressor is Ownable, DecompressorExtension {
    Executor public immutable executor;

    constructor(Executor _executor) {
        executor = _executor;
    }

    function nativeDrop(bytes calldata _encoded) external onlyOwner {
        (
            Origin memory origin,
            uint32 dstEid,
            address oapp,
            Executor.NativeDropParams[] memory nativeDropParams,
            uint256 nativeDropGasLimit
        ) = ExecutorDecoder.nativeDrop(_encoded);

        executor.nativeDrop(origin, dstEid, oapp, nativeDropParams, nativeDropGasLimit);
    }

    function execute301(bytes calldata _encoded) external onlyOwner {
        (bytes memory packet, uint256 gasLimit) = ExecutorDecoder.execute301(_encoded);

        executor.execute301(packet, gasLimit);
    }

    function nativeDropAndExecute301(bytes calldata _encoded) external onlyOwner {
        (
            Origin memory origin,
            Executor.NativeDropParams[] memory nativeDropParams,
            uint256 nativeDropGasLimit,
            bytes memory packet,
            uint256 gasLimit
        ) = ExecutorDecoder.nativeDropAndExecute301(_encoded);

        executor.nativeDropAndExecute301(origin, nativeDropParams, nativeDropGasLimit, packet, gasLimit);
    }

    function nativeDropAndExecute302(bytes calldata _encoded) external onlyOwner {
        (
            Executor.NativeDropParams[] memory nativeDropParams,
            uint256 nativeDropGasLimit,
            Executor.ExecutionParams memory executionParams
        ) = ExecutorDecoder.nativeDropAndExecute302(_encoded);

        executor.nativeDropAndExecute302(nativeDropParams, nativeDropGasLimit, executionParams);
    }
}
