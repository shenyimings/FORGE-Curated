// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.7.0;
pragma abicoder v2;

import "../proof/utility/LayerZeroPacket.sol";
import "./ILayerZeroValidationLibrary.sol";

interface IValidationLibraryHelper {
    struct ULNLog {
        bytes32 contractAddress;
        bytes32 topicZeroSig;
        bytes data;
    }

    function getVerifyLog(
        bytes32 hashRoot,
        uint[] memory receiptSlotIndex,
        uint logIndex,
        bytes[] memory proof
    ) external pure returns (ULNLog memory);

    function getPacket(
        bytes memory data,
        uint16 srcChain,
        uint sizeOfSrcAddress,
        bytes32 ulnAddress
    ) external pure returns (LayerZeroPacket.Packet memory);

    function getUtilsVersion() external view returns (uint8);
}
