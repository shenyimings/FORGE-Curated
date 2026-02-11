// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

/// @title VerificationLibrary
/// @notice Solidity Verification functions for signatures generated with Horizen ZEND mainchain.
library VerificationLibrary {

    error InvalidSignature();  //signature not correctly generated
    error SignatureNotMatching();  //signature was correctly generated but public key not matching 
    error SignatureMustBe65Bytes();

    bytes private constant MESSAGE_MAGIC_BYTES = bytes("Zcash Signed Message:\n");

    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    /// @notice Parse a ZEND signature from its byte representation.
    ///         First byte represents the v field, then 32 bytes for r field and 32 bytes for s field
    function parseZendSignature(bytes memory hexSignature) internal pure returns (Signature memory){
        if(hexSignature.length != 65) revert SignatureMustBe65Bytes();
        bytes32 r;
        bytes32 s;
        uint8 v = uint8(hexSignature[0]);
        assembly {       
            r := mload(add(hexSignature, 33)) //  bytes 1-32
            s := mload(add(hexSignature, 65)) // bytes 33-65 bytes
        }
        // Rejects the “high-s” twin ( s′ = n − s ) that signs the very same message, to avoid S-malleability issues
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0)
            revert InvalidSignature();
        return Signature({r: r, s: s, v: v});
    }

    function verifyZendSignatureBool(bytes32 messageHash, Signature memory signature, bytes32 pubKeyX, bytes32 pubKeyY) internal pure returns(bool) {
        uint8 v_ethereumFormat;
        if (signature.v == 31 || signature.v==32){
            //zend signature from compressed pubkey has +4 in the first byte, but ethereum does not expect this
            v_ethereumFormat = signature.v - 4;
        }else{
            v_ethereumFormat = signature.v;
        }
        address msgSigner = ecrecover(messageHash, v_ethereumFormat, signature.r, signature.s);
        if(msgSigner == address(0)) revert InvalidSignature();

        //generate an ethereum address from the pubkey
         bytes32 hash = keccak256(abi.encodePacked(pubKeyX, pubKeyY));
        address ethAddress = address(uint160(uint256(hash)));

        return msgSigner == ethAddress; 
    }

    function verifyZendSignature(bytes32 messageHash, Signature memory signature, bytes32 pubKeyX, bytes32 pubKeyY) internal pure {
        if(!verifyZendSignatureBool(messageHash, signature, pubKeyX, pubKeyY)) revert SignatureNotMatching();
    }

    /// @notice Create a message hash compatible with ZEND format from an arbitrary message string.
    function createMessageHash(string memory message) internal pure returns(bytes32) {

        bytes memory messageToSignBytes = bytes(message);        
        bytes memory mmb2 = abi.encodePacked(uint8(MESSAGE_MAGIC_BYTES.length), MESSAGE_MAGIC_BYTES);
        bytes memory mts2 = abi.encodePacked(uint8(messageToSignBytes.length), messageToSignBytes);
       
        // array concatenation
        bytes memory combinedMessage = abi.encodePacked(mmb2, mts2);
        
        // Double SHA-256 hashing
        return sha256(abi.encodePacked(sha256(combinedMessage)));
    }

    function pubKeyUncompressedToZenAddress(bytes32 pubKeyX, bytes32 pubKeyY) internal pure returns (bytes20) {
        return ripemd160(abi.encodePacked(sha256(abi.encodePacked(hex"04", pubKeyX, pubKeyY))));
    }

    function pubKeyCompressedToZenAddress(bytes32 xPubKeyBE, uint8 sign) internal pure returns (bytes20) {
        return ripemd160(abi.encodePacked(sha256(abi.encodePacked(sign, xPubKeyBE))));
    }

    function signByte(bytes32 yPubKeyBE) internal pure returns (uint8) {
        uint256 yPub = uint256(yPubKeyBE);
        if (yPub % 2 == 0) {
            return 0x02;
        } else {
            return 0x03;
        }
    }
}