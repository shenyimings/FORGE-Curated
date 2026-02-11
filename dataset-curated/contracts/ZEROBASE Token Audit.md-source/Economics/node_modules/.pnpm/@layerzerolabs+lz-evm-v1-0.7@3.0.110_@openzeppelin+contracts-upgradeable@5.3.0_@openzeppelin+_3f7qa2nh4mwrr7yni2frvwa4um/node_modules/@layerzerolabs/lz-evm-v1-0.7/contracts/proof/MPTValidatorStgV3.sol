// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "./utility/LayerZeroPacket.sol";
import "./utility/Buffer.sol";
import "../interfaces/ILayerZeroValidationLibrary.sol";
import "./utility/UltraLightNodeEVMDecoder.sol";

contract MPTValidatorStgV3 is ILayerZeroValidationLibrary {
    using RLPDecode for RLPDecode.RLPItem;
    using RLPDecode for RLPDecode.Iterator;
    using Buffer for Buffer.buffer;
    using SafeMath for uint;

    bytes32 public constant PACKET_SIGNATURE = 0xe8d23d927749ec8e512eb885679c2977d57068839d8cca1a85685dbbea0648f6;

    address public immutable stargateBridgeAddress;
    address public immutable stgTokenAddress;
    uint16 public immutable localChainId;

    constructor(address _stargateBridgeAddress, address _stgTokenAddress, uint16 _localChainId) {
        stargateBridgeAddress = _stargateBridgeAddress;
        stgTokenAddress = _stgTokenAddress;
        localChainId = _localChainId;
    }

    struct ULNLog {
        bytes32 contractAddress;
        bytes32 topicZeroSig;
        bytes data;
    }

    // Stargate objects for abi encoding / decoding
    struct SwapObj {
        uint amount;
        uint eqFee;
        uint eqReward;
        uint lpFee;
        uint protocolFee;
        uint lkbRemove;
    }

    struct CreditObj {
        uint credits;
        uint idealBalance;
    }

    function validateProof(
        bytes32 _receiptsRoot,
        bytes calldata _transactionProof,
        uint _remoteAddressSize
    ) external view override returns (LayerZeroPacket.Packet memory) {
        (uint16 remoteChainId, bytes[] memory proof, uint[] memory receiptSlotIndex, uint logIndex) = abi.decode(
            _transactionProof,
            (uint16, bytes[], uint[], uint)
        );

        ULNLog memory log = _getVerifiedLog(_receiptsRoot, receiptSlotIndex, logIndex, proof);
        require(log.topicZeroSig == PACKET_SIGNATURE, "ProofLib: packet not recognized"); //data

        LayerZeroPacket.Packet memory packet = _getPacket(
            log.data,
            remoteChainId,
            _remoteAddressSize,
            log.contractAddress
        );

        require(packet.dstChainId == localChainId, "ProofLib: invalid destination chain ID");

        if (packet.dstAddress == stargateBridgeAddress) packet.payload = _secureStgPayload(packet.payload);

        if (packet.dstAddress == stgTokenAddress) packet.payload = _secureStgTokenPayload(packet.payload);

        return packet;
    }

    function _secureStgTokenPayload(bytes memory _payload) internal pure returns (bytes memory) {
        (bytes memory toAddressBytes, uint qty) = abi.decode(_payload, (bytes, uint));

        address toAddress = address(0);
        if (toAddressBytes.length > 0) {
            assembly {
                toAddress := mload(add(toAddressBytes, 20))
            }
        }

        if (toAddress == address(0)) {
            address deadAddress = address(0x000000000000000000000000000000000000dEaD);
            bytes memory newToAddressBytes = abi.encodePacked(deadAddress);
            return abi.encode(newToAddressBytes, qty);
        }

        // default to return the original payload
        return _payload;
    }

    function _secureStgPayload(bytes memory _payload) internal view returns (bytes memory) {
        // functionType is uint8 even though the encoding will take up the side of uint256
        uint8 functionType;
        assembly {
            functionType := mload(add(_payload, 32))
        }

        // TYPE_SWAP_REMOTE == 1 && only if the payload has a payload
        // only swapRemote inside of stargate can call sgReceive on an user supplied to address
        // thus we do not care about the other type functions even if the toAddress is overly long.
        if (functionType == 1) {
            // decode the _payload with its types
            (
                ,
                uint srcPoolId,
                uint dstPoolId,
                uint dstGasForCall,
                CreditObj memory c,
                SwapObj memory s,
                bytes memory toAddressBytes,
                bytes memory contractCallPayload
            ) = abi.decode(_payload, (uint8, uint, uint, uint, CreditObj, SwapObj, bytes, bytes));

            // if contractCallPayload.length > 0 need to check if the to address is a contract or not
            if (contractCallPayload.length > 0) {
                // otherwise, need to check if the payload can be delivered to the toAddress
                address toAddress = address(0);
                if (toAddressBytes.length > 0) {
                    assembly {
                        toAddress := mload(add(toAddressBytes, 20))
                    }
                }

                // check if the toAddress is a contract. We are not concerned about addresses that pretend to be wallets. because worst case we just delete their payload if being malicious
                // we can guarantee that if a size > 0, then the contract is definitely a contract address in this context
                uint size;
                assembly {
                    size := extcodesize(toAddress)
                }

                if (size == 0) {
                    // size == 0 indicates its not a contract, payload wont be delivered
                    // secure the _payload to make sure funds can be delivered to the toAddress
                    bytes memory newToAddressBytes = abi.encodePacked(toAddress);
                    bytes memory securePayload = abi.encode(
                        functionType,
                        srcPoolId,
                        dstPoolId,
                        dstGasForCall,
                        c,
                        s,
                        newToAddressBytes,
                        bytes("")
                    );
                    return securePayload;
                }
            }
        }

        // default to return the original payload
        return _payload;
    }

    function secureStgTokenPayload(bytes memory _payload) external pure returns (bytes memory) {
        return _secureStgTokenPayload(_payload);
    }

    function secureStgPayload(bytes memory _payload) external view returns (bytes memory) {
        return _secureStgPayload(_payload);
    }

    function _getVerifiedLog(
        bytes32 hashRoot,
        uint[] memory paths,
        uint logIndex,
        bytes[] memory proof
    ) internal pure returns (ULNLog memory) {
        require(paths.length == proof.length, "ProofLib: invalid proof size");

        RLPDecode.RLPItem memory item;
        bytes memory proofBytes;

        for (uint i = 0; i < proof.length; i++) {
            proofBytes = proof[i];
            require(hashRoot == keccak256(proofBytes), "ProofLib: invalid hashlink");
            item = RLPDecode.toRlpItem(proofBytes).safeGetItemByIndex(paths[i]);
            if (i < proof.length - 1) hashRoot = bytes32(item.toUint());
        }

        // burning status + gasUsed + logBloom
        RLPDecode.RLPItem memory logItem = item.typeOffset().safeGetItemByIndex(3);
        RLPDecode.Iterator memory it = logItem.safeGetItemByIndex(logIndex).iterator();
        ULNLog memory log;
        log.contractAddress = bytes32(it.next().toUint());
        log.topicZeroSig = bytes32(it.next().getItemByIndex(0).toUint());
        log.data = it.next().toBytes();

        return log;
    }

    // profiling and test
    function getVerifyLog(
        bytes32 hashRoot,
        uint[] memory receiptSlotIndex,
        uint logIndex,
        bytes[] memory proof
    ) external pure returns (ULNLog memory) {
        return _getVerifiedLog(hashRoot, receiptSlotIndex, logIndex, proof);
    }

    function getPacket(
        bytes memory data,
        uint16 srcChain,
        uint sizeOfSrcAddress,
        bytes32 ulnAddress
    ) external pure returns (LayerZeroPacket.Packet memory) {
        return _getPacket(data, srcChain, sizeOfSrcAddress, ulnAddress);
    }

    function _getPacket(
        bytes memory data,
        uint16 srcChain,
        uint sizeOfSrcAddress,
        bytes32 ulnAddress
    ) internal pure returns (LayerZeroPacket.Packet memory) {
        uint16 dstChainId;
        address dstAddress;
        uint size;
        uint64 nonce;

        // The log consists of the destination chain id and then a bytes payload
        //      0--------------------------------------------31
        // 0   |  destination chain id
        // 32  |  defines bytes array
        // 64  |
        // 96  |  bytes array size
        // 128 |  payload
        assembly {
            dstChainId := mload(add(data, 32))
            size := mload(add(data, 96)) /// size of the byte array
            nonce := mload(add(data, 104)) // offset to convert to uint64  128  is index -24
            dstAddress := mload(add(data, sub(add(128, sizeOfSrcAddress), 4))) // offset to convert to address 12 -8
        }

        Buffer.buffer memory srcAddressBuffer;
        srcAddressBuffer.init(sizeOfSrcAddress);
        srcAddressBuffer.writeRawBytes(0, data, 136, sizeOfSrcAddress); // 128 + 8

        uint payloadSize = size.sub(20).sub(sizeOfSrcAddress);
        Buffer.buffer memory payloadBuffer;
        payloadBuffer.init(payloadSize);
        payloadBuffer.writeRawBytes(0, data, sizeOfSrcAddress.add(156), payloadSize); // 148 + 8
        return
            LayerZeroPacket.Packet(
                srcChain,
                dstChainId,
                nonce,
                dstAddress,
                srcAddressBuffer.buf,
                ulnAddress,
                payloadBuffer.buf
            );
    }
}
