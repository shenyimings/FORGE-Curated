// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";

library BlockHeaders {
    using RLP for RLP.Encoder;

    struct L1BlockHeader {
        bytes32 parentHash;
        bytes32 sha3Uncles;
        address miner;
        bytes32 stateRoot;
        bytes32 transactionsRoot;
        bytes32 receiptsRoot;
        bytes logsBloom;
        uint256 difficulty;
        uint256 number;
        uint64 gasLimit;
        uint64 gasUsed;
        uint64 timestamp;
        bytes extraData;
        bytes32 mixHash;
        bytes8 nonce;
        uint256 baseFeePerGas;
        bytes32 withdrawalsRoot;
        uint64 blobGasUsed;
        uint64 excessBlobGas;
        bytes32 parentBeaconBlockRoot;
        bytes32 requestsHash;
    }

    struct ArbitrumBlockHeader {
        bytes32 parentHash;
        bytes32 sha3Uncles;
        address miner;
        bytes32 stateRoot;
        bytes32 transactionsRoot;
        bytes32 receiptsRoot;
        bytes logsBloom;
        uint256 difficulty;
        uint256 number;
        uint64 gasLimit;
        uint64 gasUsed;
        uint64 timestamp;
        bytes extraData;
        bytes32 mixHash;
        bytes8 nonce;
        uint256 baseFeePerGas;
        bytes32 withdrawalsRoot;
        uint64 blobGasUsed;
        uint64 excessBlobGas;
        bytes32 parentBeaconBlockRoot;
        bytes32 requestsHash;
        uint256 totalDifficulty;
        uint256 l1BlockNumber;
        uint256 sendCount;
        bytes32 sendRoot;
        uint256 arbOsVersion;
    }

    function encode(L1BlockHeader memory h) internal pure returns (bytes memory out) {
        RLP.Encoder memory enc = RLP.encoder().push(h.parentHash).push(h.sha3Uncles).push(h.miner).push(h.stateRoot)
            .push(h.transactionsRoot).push(h.receiptsRoot).push(h.logsBloom).push(h.difficulty).push(h.number)
            .push(h.gasLimit).push(h.gasUsed).push(h.timestamp).push(h.extraData).push(h.mixHash)
            .push(abi.encodePacked(h.nonce)).push(h.baseFeePerGas).push(h.withdrawalsRoot).push(h.blobGasUsed)
            .push(h.excessBlobGas).push(h.parentBeaconBlockRoot).push(h.requestsHash);

        out = enc.encode(); // wraps items as an RLP list
    }

    function encode(ArbitrumBlockHeader memory h) internal pure returns (bytes memory out) {
        RLP.Encoder memory enc = RLP.encoder().push(h.parentHash).push(h.sha3Uncles).push(h.miner).push(h.stateRoot)
            .push(h.transactionsRoot).push(h.receiptsRoot).push(h.logsBloom).push(h.difficulty).push(h.number)
            .push(h.gasLimit).push(h.gasUsed).push(h.timestamp).push(h.extraData).push(h.mixHash)
            .push(abi.encodePacked(h.nonce)).push(h.baseFeePerGas).push(h.totalDifficulty);

        out = enc.encode(); // wraps items as an RLP list
    }
}
