// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

contract SignatureBitMap {
    mapping(uint256 => uint256) private signatures;

    function consumeSignature(bytes memory signature) internal {
        uint256 signatureInt = uint256(keccak256(signature));
        uint256 wordIndex = signatureInt / 256;
        uint256 bitIndex = signatureInt % 256;
        signatures[wordIndex] |= (1 << bitIndex);
    }

    function isSignatureConsumed(bytes memory signature) internal view returns (bool) {
        uint256 signatureInt = uint256(keccak256(signature));
        uint256 wordIndex = signatureInt / 256;
        uint256 bitIndex = signatureInt % 256;
        uint256 mask = (1 << bitIndex);
        return (signatures[wordIndex] & mask) == mask;
    }
}
