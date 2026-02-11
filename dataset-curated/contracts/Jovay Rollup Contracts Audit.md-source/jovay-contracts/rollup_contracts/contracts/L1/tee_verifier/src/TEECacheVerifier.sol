// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {BELE} from "dcap-attestation/utils/BELE.sol";
import {P256Verifier} from "dcap-attestation/utils/P256Verifier.sol";
import "dcap-attestation/types/Constants.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {console} from "forge-std/console.sol";

/**
 * @title  TEECacheVerifier
 * @notice Provides full on-chain verification for Intel DCAP attestation.
 */
contract TEECacheVerifier is P256Verifier, Ownable {
    uint16 private constant DATA_OFFSET = 526;
    mapping(address => bool) _authorized;
    bool _isCallerRestricted = true;
    mapping(bytes => bool) private _verificationCache;
    bytes[] private _initializedKeys;

    error Forbidden();
    error KeyNotInitialized();
    error UnsupportedQuoteVersion();
    error InvalidAddress();
    error ListTooLong();
    error UnknownTdReportType();

    modifier onlyAuthorized() {
        if (_isCallerRestricted && !_authorized[msg.sender]) {
            revert Forbidden();
        }
        _;
    }

    constructor(address _ecdsaVerifier) P256Verifier(_ecdsaVerifier) {
        if (_ecdsaVerifier == address(0)) revert InvalidAddress();
        _initializeOwner(msg.sender);
        _authorized[msg.sender] = true;
    }

    function setAuthorized(address caller, bool authorized) external onlyOwner {
        if (caller == address(0)) revert InvalidAddress();
        _authorized[caller] = authorized;
    }

    function enableCallerRestriction() external onlyOwner {
        _isCallerRestricted = true;
    }

    // function disableCallerRestriction() external onlyOwner {
    //     _isCallerRestricted = false;
    // }

    function isInitialized(bytes calldata key) external view returns (bool) {
        return _verificationCache[key];
    }

    function initializeCache(bytes calldata key) external onlyAuthorized {
         // Limit the number of iterations to prevent malicious injection and gas exhaustion
        if (_initializedKeys.length >= 10000) revert ListTooLong();
        _verificationCache[key] = true;
        _initializedKeys.push(key);
    }

    function deleteKey(bytes calldata key) external onlyOwner {
        require(_verificationCache[key], KeyNotInitialized());
        // Limit the number of iterations to prevent gas exhaustion
        // if (_initializedKeys.length >= 10000) revert ListTooLong();
        _verificationCache[key] = false;
        bytes32 keyHash = keccak256(key);
        for (uint256 i = 0; i < _initializedKeys.length; ++i) {
            if (keccak256(_initializedKeys[i]) == keyHash) {
                _initializedKeys[i] = _initializedKeys[_initializedKeys.length - 1];
                _initializedKeys.pop();
                break;
            }
        }
    }

    function clearupAllKey() external onlyOwner {
        for (uint256 i = 0; i < _initializedKeys.length; ++i) {
            delete _verificationCache[_initializedKeys[i]];
        }
        delete _initializedKeys;
    }

    function getAllKey() external view returns (bytes[] memory) {
        return _initializedKeys;
    }

    function parseAttestationKey(bytes calldata rawQuote, uint256 version)
        external
        pure
        returns (bytes memory ecdsa256BitSignature, bytes memory ecdsaAttestationKey)
    {
        if (version == 3) {
            (ecdsa256BitSignature, ecdsaAttestationKey) = _parseKeyV3(rawQuote);
        } else if (version == 4) {
            (ecdsa256BitSignature, ecdsaAttestationKey) = _parseKeyV4(rawQuote);
        } else if (version == 5) {
            (ecdsa256BitSignature, ecdsaAttestationKey) = _parseKeyV5(rawQuote);
        } else {
            revert UnsupportedQuoteVersion();
        }
    }

    function verifyAndAttestOnChain(
        bytes calldata rawQuote,
        bytes memory ecdsa256BitSignature,
        bytes memory ecdsaAttestationKey,
        uint256 version
    ) external view onlyAuthorized returns (uint32 _error_code, bytes32 commitment) {
        // Extract the quote version from the raw quote
        // uint16 version = uint16(BELE.leBytesToBeUint(rawQuote[0:2]));
        if (version == 3) {
            (_error_code, commitment) = _verifyQuoteV3(rawQuote, ecdsa256BitSignature, ecdsaAttestationKey);
        } else if (version == 4) {
            (_error_code, commitment) = _verifyQuoteV4(rawQuote, ecdsa256BitSignature, ecdsaAttestationKey);
        } else if (version == 5) {
            (_error_code, commitment) = _verifyQuoteV5(rawQuote, ecdsa256BitSignature, ecdsaAttestationKey);
        } else {
            revert UnsupportedQuoteVersion();
        }
    }

    function _parseKeyV3(bytes calldata rawQuote)
        private
        pure
        returns (bytes memory ecdsa256BitSignature, bytes memory ecdsaAttestationKey)
    {
        uint256 offset = HEADER_LENGTH + ENCLAVE_REPORT_LENGTH;
        uint256 localAuthDataSize = BELE.leBytesToBeUint(rawQuote[offset:offset + 4]);
        offset += 4;
        bytes calldata rawAuthData = rawQuote[offset:offset + localAuthDataSize];
        ecdsa256BitSignature = rawAuthData[0:64];
        ecdsaAttestationKey = rawAuthData[64:128];
    }

    function _parseKeyV4(bytes calldata rawQuote)
        private
        pure
        returns (bytes memory ecdsa256BitSignature, bytes memory ecdsaAttestationKey)
    {
        bytes4 teeType = bytes4(rawQuote[4:8]);
        uint256 offset = HEADER_LENGTH;
        if (teeType == SGX_TEE) {
            offset += ENCLAVE_REPORT_LENGTH;
        } else {
            offset += TD_REPORT10_LENGTH;
        }
        offset += 4; // localAuthDataSize
        ecdsa256BitSignature = rawQuote[offset:offset + 64];
        ecdsaAttestationKey = rawQuote[offset + 64:offset + 128];
    }

    function _parseKeyV5(bytes calldata rawQuote)
        private
        pure
        returns (bytes memory ecdsa256BitSignature, bytes memory ecdsaAttestationKey)
    {
        bytes memory bodyType = rawQuote[HEADER_LENGTH:HEADER_LENGTH + 2];
        uint256 offset = HEADER_LENGTH + TD_REPORT_BODY_DESCRIPTOR_LENGTH;
        uint16 tdReportBodyType = SafeCast.toUint16(BELE.leBytesToBeUint(bodyType));
        if (tdReportBodyType == TD_REPORT_VERSION_10) {
            offset += TD_REPORT10_LENGTH;
        } else if (tdReportBodyType == TD_REPORT_VERSION_15) {
            offset += TD_REPORT15_LENGTH;
        } else {
            revert UnknownTdReportType();
        }
        offset += 4; // localAuthDataSize
        ecdsa256BitSignature = rawQuote[offset:offset + 64];
        ecdsaAttestationKey = rawQuote[offset + 64:offset + 128];
    }

    function _verifyQuoteV3(
        bytes calldata rawQuote,
        bytes memory ecdsa256BitSignature,
        bytes memory ecdsaAttestationKey
    ) private view returns (uint32, bytes32) {
        // Extract the header and body from the raw quote
        bytes memory rawHeader = rawQuote[0:HEADER_LENGTH];
        uint256 offset = HEADER_LENGTH + ENCLAVE_REPORT_LENGTH;
        bytes memory rawBody = rawQuote[HEADER_LENGTH:offset];

        bytes memory localAttestationData = abi.encodePacked(rawHeader, rawBody);
        bool success = P256Verifier.ecdsaVerify(sha256(localAttestationData), ecdsa256BitSignature, ecdsaAttestationKey);
        if (!success) {
            return (1, bytes32(0));
        }
        // Extract report data from the raw body
        offset = ENCLAVE_REPORT_LENGTH - 64; // Calculate the start index

        bytes32 commitment;
        assembly {
            // 0x20: skip bytes header(32 byte)
            commitment := mload(add(rawBody, add(offset, 0x20)))
        }
        return (0, commitment);
    }

    function _verifyQuoteV4(
        bytes calldata rawQuote,
        bytes memory ecdsa256BitSignature,
        bytes memory ecdsaAttestationKey
    ) private view returns (uint32, bytes32) {
        // Extract the header and body from the raw quote
        bytes memory rawHeader = rawQuote[0:HEADER_LENGTH];
        bytes4 teeType = bytes4(rawQuote[4:8]);
        uint256 offset = HEADER_LENGTH;
        if (teeType == SGX_TEE) {
            offset += ENCLAVE_REPORT_LENGTH;
        } else {
            offset += TD_REPORT10_LENGTH;
        }
        bytes memory rawBody = rawQuote[HEADER_LENGTH:offset];

        bytes memory localAttestationData = abi.encodePacked(rawHeader, rawBody);
        bool success = P256Verifier.ecdsaVerify(sha256(localAttestationData), ecdsa256BitSignature, ecdsaAttestationKey);
        if (!success) {
            return (1, bytes32(0));
        }
        // Extract report data from the raw body
        if (teeType == SGX_TEE) {
            offset = ENCLAVE_REPORT_LENGTH - 64;
        } else {
            offset = TD_REPORT10_LENGTH - 64;
        }

        bytes32 commitment;
        assembly {
            // 0x20: skip bytes header(32 byte)
            commitment := mload(add(rawBody, add(offset, 0x20)))
        }
        return (0, commitment);
    }

    function _verifyQuoteV5(
        bytes calldata rawQuote,
        bytes memory ecdsa256BitSignature,
        bytes memory ecdsaAttestationKey
    ) private view returns (uint32, bytes32) {
        // Extract the header and body from the raw quote
        bytes memory rawHeader = rawQuote[0:HEADER_LENGTH];
        bytes memory bodyType = rawQuote[HEADER_LENGTH:HEADER_LENGTH + 2];
        bytes memory rawBody;
        uint256 offset;
        uint16 tdReportBodyType = SafeCast.toUint16(BELE.leBytesToBeUint(bodyType));
        if (tdReportBodyType == TD_REPORT_VERSION_10) {
            rawBody = rawQuote[HEADER_LENGTH:HEADER_LENGTH + TD_REPORT10_LENGTH + TD_REPORT_BODY_DESCRIPTOR_LENGTH];
        } else if (tdReportBodyType == TD_REPORT_VERSION_15) {
            rawBody = rawQuote[HEADER_LENGTH:HEADER_LENGTH + TD_REPORT15_LENGTH + TD_REPORT_BODY_DESCRIPTOR_LENGTH];
        } else {
            return (1, bytes32(0));
        }

        bytes memory localAttestationData = abi.encodePacked(rawHeader, rawBody);
        bool success = P256Verifier.ecdsaVerify(sha256(localAttestationData), ecdsa256BitSignature, ecdsaAttestationKey);
        if (!success) {
            return (1, bytes32(0));
        }
        // Extract report data from the raw body
        offset = DATA_OFFSET; // Calculate the start index
        bytes32 commitment;
        assembly {
            // 0x20: skip bytes header(32 byte)
            commitment := mload(add(rawBody, add(offset, 0x20)))
        }
        return (0, commitment);
    }
}
