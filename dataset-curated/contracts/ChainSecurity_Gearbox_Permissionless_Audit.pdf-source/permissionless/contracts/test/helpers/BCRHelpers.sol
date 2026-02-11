// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {SignatureHelper} from "./SignatureHelper.sol";
import {Bytecode} from "../../interfaces/Types.sol";
import {IBytecodeRepository} from "../../interfaces/IBytecodeRepository.sol";
import {console} from "forge-std/console.sol";
import {LibString} from "@solady/utils/LibString.sol";

contract BCRHelpers is SignatureHelper {
    using LibString for bytes32;

    address internal bytecodeRepository;
    uint256 internal auditorKey;
    address internal auditor;

    uint256 internal authorKey;
    address internal author;

    constructor() {
        auditorKey = _generatePrivateKey("AUDITOR");
        auditor = vm.rememberKey(auditorKey);

        authorKey = _generatePrivateKey("AUTHOR");
        author = vm.rememberKey(authorKey);
    }

    function _setUpBCR() internal {}

    function _uploadByteCode(bytes memory _initCode, bytes32 _contractType, uint256 _version)
        internal
        returns (bytes32 bytecodeHash)
    {
        Bytecode memory bytecode = Bytecode({
            contractType: _contractType,
            version: _version,
            initCode: _initCode,
            author: author,
            source: "github.com/gearbox-protocol/core-v3",
            authorSignature: ""
        });

        // Generate EIP-712 signature for bytecode
        bytes32 BYTECODE_TYPEHASH = IBytecodeRepository(bytecodeRepository).BYTECODE_TYPEHASH();

        bytecodeHash = keccak256(
            abi.encode(
                BYTECODE_TYPEHASH,
                bytecode.contractType,
                bytecode.version,
                keccak256(bytecode.initCode),
                bytecode.author,
                keccak256(bytes(bytecode.source))
            )
        );

        bytecode.authorSignature =
            _sign(authorKey, keccak256(abi.encodePacked("\x19\x01", _bytecodeDomainSeparator(), bytecodeHash)));

        _startPrankOrBroadcast(author);
        IBytecodeRepository(bytecodeRepository).uploadBytecode(bytecode);

        _stopPrankOrBroadcast();
    }

    function _uploadByteCodeAndSign(bytes memory _initCode, bytes32 _contractName, uint256 _version)
        internal
        returns (bytes32 bytecodeHash)
    {
        bytecodeHash = _uploadByteCode(_initCode, _contractName, _version);
        string memory reportUrl = "https://github.com/gearbox-protocol/security-review";

        // Build auditor signature
        bytes32 signatureHash = keccak256(
            abi.encode(
                keccak256("SignBytecodeHash(bytes32 bytecodeHash,string reportUrl)"),
                bytecodeHash,
                keccak256(bytes(reportUrl))
            )
        );

        // Sign the hash with auditor key
        bytes memory signature =
            _sign(auditorKey, keccak256(abi.encodePacked("\x19\x01", _bytecodeDomainSeparator(), signatureHash)));

        // Call signBytecodeHash with signature
        IBytecodeRepository(bytecodeRepository).signBytecodeHash(bytecodeHash, reportUrl, signature);
    }

    function _bytecodeDomainSeparator() internal view returns (bytes32) {
        // Get domain separator from BytecodeRepository contract
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("BYTECODE_REPOSITORY")),
                keccak256(bytes("310")),
                1,
                bytecodeRepository
            )
        );
    }
}
