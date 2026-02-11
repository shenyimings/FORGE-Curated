pragma solidity ^0.8.0;

import {Ownable} from "solady/auth/Ownable.sol";
import {console} from "forge-std/console.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {MeasurementDao} from "./MeasurementDao.sol";
import {AutomataDcapAttestationFee} from "dcap-attestation/AutomataDcapAttestationFee.sol";
import {BELE} from "dcap-attestation/utils/BELE.sol";
import {BytesUtils} from "dcap-attestation/utils/BytesUtils.sol";
import {TEECacheVerifier} from "./TEECacheVerifier.sol";
import "dcap-attestation/types/Constants.sol";

/**
 * @notice verify quote from rollup
 */
contract DcapAttestationRouter is Ownable {
    using BytesUtils for bytes;

    uint16 private constant USER_DATA_V3_OFFSET = 333;
    uint16 private constant USER_DATA_V4_OFFSET = 533;
    uint16 private constant USER_DATA_V5_OFFSET = 539;

    address public dcapAttestation;
    address public measurementDao;
    bool public toVerifyMr;
    address public cacheVerifierAddr;
    bool public CacheOption;
    mapping(address => bool) _authorized;
    bool _isCallerRestricted = true;
    bool public toVerifyMrtd = false;

    error Forbidden();
    error InvalidAddress();
    error MrValidationFailed();
    error MRTDValidationFailed();

    modifier onlyAuthorized() {
        if (_isCallerRestricted && !_authorized[msg.sender]) {
            revert Forbidden();
        }
        _;
    }

    constructor(address _dcapAttestation, address _measurementDao, address _cacheVerifierAddr) {
        _initializeOwner(msg.sender);
        _setConfig(_dcapAttestation, _measurementDao, true, _cacheVerifierAddr, true);
    }

    function setConfig(
        address _dcapAttestation,
        address _measurementDao,
        bool _toVerifyMr,
        address _cacheVerifierAddr,
        bool _CacheOption
    ) external onlyOwner {
        _setConfig(_dcapAttestation, _measurementDao, _toVerifyMr, _cacheVerifierAddr, _CacheOption);
    }

    function setAuthorized(address caller, bool authorized) external onlyOwner {
        _authorized[caller] = authorized;
    }

    function enableCallerRestriction() external onlyOwner {
        _isCallerRestricted = true;
    }

    function disableCallerRestriction() external onlyOwner {
        _isCallerRestricted = false;
    }

    function verifyProof(bytes calldata aggrProof)
        external
        onlyAuthorized
        returns (uint32 _error_code, bytes32 commitment)
    {
        (_error_code, commitment) = _verifyProof(aggrProof);
    }

    function _setConfig(
        address _dcapAttestation,
        address _measurementDao,
        bool _toVerifyMr,
        address _cacheVerifierAddr,
        bool _CacheOption
    ) private {
        if (_dcapAttestation == address(0)) revert InvalidAddress();
        if (_measurementDao == address(0)) revert InvalidAddress();
        if (_cacheVerifierAddr == address(0)) revert InvalidAddress();
        dcapAttestation = _dcapAttestation;
        measurementDao = _measurementDao;
        toVerifyMr = _toVerifyMr;
        cacheVerifierAddr = _cacheVerifierAddr;
        CacheOption = _CacheOption;
    }

    function enableVerifyMRTD() external onlyOwner {
        toVerifyMrtd = true;
    }

    function disableVerifyMRTD() external onlyOwner {
        toVerifyMrtd = false;
    }

    function _verifyMeasurement(bytes calldata quote, uint16 quoteVersion) private view returns (bool) {
        bytes4 teeType = bytes4(quote.substring(4, 4));
        if (teeType == SGX_TEE) {
            return MeasurementDao(measurementDao).verifyMeasurementSGX(quote, quoteVersion);
        } else {
            if (toVerifyMrtd) {
                bool mrtdVerified = MeasurementDao(measurementDao).verifyMRTD(quote, quoteVersion);
                if (!mrtdVerified) {
                    revert MRTDValidationFailed();
                }
            }
            return MeasurementDao(measurementDao).verifyMeasurementTDX(quote, quoteVersion);
        }
    }

    function _verifyProof(bytes calldata aggrProof) private returns (uint32 _error_code, bytes32 commitment) {
        uint16 quoteVersion = SafeCast.toUint16(BELE.leBytesToBeUint(aggrProof[0:2]));
        if (toVerifyMr) {
            if (!_verifyMeasurement(aggrProof, quoteVersion)) {
                revert MrValidationFailed();
            }
        }
        bytes memory ecdsa256BitSignature;
        bytes memory ecdsaAttestationKey;
        bool success;
        bytes memory output;
        TEECacheVerifier CacheAttestation = TEECacheVerifier(cacheVerifierAddr);
        (ecdsa256BitSignature, ecdsaAttestationKey) = CacheAttestation.parseAttestationKey(aggrProof, quoteVersion);
        if (CacheOption && CacheAttestation.isInitialized(ecdsaAttestationKey)) {
            (_error_code, commitment) = CacheAttestation.verifyAndAttestOnChain(
                aggrProof, ecdsa256BitSignature, ecdsaAttestationKey, quoteVersion
            );
        } else {
            AutomataDcapAttestationFee attestation = AutomataDcapAttestationFee(dcapAttestation);
            (success, output) = attestation.verifyAndAttestOnChain(aggrProof);

            if (success) {
                if (CacheOption) CacheAttestation.initializeCache(ecdsaAttestationKey);
                _error_code = 0;
                uint256 offset;
                if (quoteVersion == 3) {
                    offset = USER_DATA_V3_OFFSET;
                } else if (quoteVersion == 4) {
                    offset = USER_DATA_V4_OFFSET;
                } else if (quoteVersion == 5) {
                    offset = USER_DATA_V5_OFFSET;
                } else {
                    _error_code = 1;
                }
                if (_error_code == 0) {
                    // extract user data from output generated by dcap attestation contract
                    assembly {
                        // 0x20: skip bytes header(32 byte)
                        commitment := mload(add(output, add(offset, 0x20)))
                    }
                } else {
                    commitment = bytes32(0);
                }
            } else {
                _error_code = 1;
                commitment = bytes32(0);
            }
        }
    }
}
