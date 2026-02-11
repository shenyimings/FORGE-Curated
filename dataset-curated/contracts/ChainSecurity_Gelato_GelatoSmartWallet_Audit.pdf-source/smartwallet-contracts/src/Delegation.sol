// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC7821} from "./interfaces/IERC7821.sol";
import {IERC1271} from "./interfaces/IERC1271.sol";
import {IERC4337} from "./interfaces/IERC4337.sol";
import {IValidator} from "./interfaces/IValidator.sol";
import {
    CALL_TYPE_BATCH,
    EXEC_TYPE_DEFAULT,
    EXEC_MODE_DEFAULT,
    EXEC_MODE_OP_DATA,
    ENTRY_POINT_V8
} from "./types/Constants.sol";
import {EIP712} from "solady/utils/EIP712.sol";

contract Delegation is IERC7821, IERC1271, IERC4337, EIP712 {
    error UnsupportedExecutionMode();
    error InvalidCaller();
    error InvalidValidator();
    error InvalidSignatureLength();
    error InvalidSignatureS();
    error InvalidSignature();
    error Unauthorized();
    error InvalidNonce();
    error ExcessiveInvalidation();

    event ValidatorAdded(IValidator validator);
    event ValidatorRemoved(IValidator validator);

    // https://eips.ethereum.org/EIPS/eip-7201
    /// @custom:storage-location erc7201:gelato.delegation.storage
    struct Storage {
        mapping(uint192 => uint64) nonceSequenceNumber;
        mapping(IValidator => bool) validatorEnabled;
    }

    IValidator transient transientValidator;

    // keccak256(abi.encode(uint256(keccak256("gelato.delegation.storage")) - 1)) &
    // ~bytes32(uint256(0xff));
    bytes32 private constant STORAGE_LOCATION =
        0x1581abf533ae210f1ff5d25f322511179a9a65d8d8e43c998eab264f924af900;

    // keccak256("Execute(bytes32 mode,Call[] calls,uint256 nonce)Call(address to,uint256
    // value,bytes data)")
    bytes32 private constant EXECUTE_TYPEHASH =
        0xdf21343e200fb58137ad2784f9ea58605ec77f388015dc495486275b8eec47da;

    // keccak256("Call(address to,uint256 value,bytes data)")
    bytes32 private constant CALL_TYPEHASH =
        0x9085b19ea56248c94d86174b3784cfaaa8673d1041d6441f61ff52752dac8483;

    modifier onlyThis() {
        if (msg.sender != address(this)) {
            revert InvalidCaller();
        }
        _;
    }

    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint()) {
            revert InvalidCaller();
        }
        _;
    }

    fallback() external payable {}

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function execute(bytes32 mode, bytes calldata executionData) external payable {
        _execute(mode, executionData, false);
    }

    function supportsExecutionMode(bytes32 mode) external pure returns (bool) {
        (bytes1 callType, bytes1 execType, bytes4 modeSelector,) = _decodeExecutionMode(mode);

        if (callType != CALL_TYPE_BATCH || execType != EXEC_TYPE_DEFAULT) {
            return false;
        }

        if (modeSelector != EXEC_MODE_DEFAULT && modeSelector != EXEC_MODE_OP_DATA) {
            return false;
        }

        return true;
    }

    // https://eips.ethereum.org/EIPS/eip-1271
    function isValidSignature(bytes32 digest, bytes calldata signature)
        external
        view
        returns (bytes4)
    {
        // If `signature` length is 65, treat it as secp256k1 signature.
        // Otherwise, invoke the specified validator module.
        if (signature.length == 65) {
            return _verifySignature(digest, signature) ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
        }

        (IValidator validator, bytes calldata innerSignature) = _decodeValidator(signature);

        if (!_getStorage().validatorEnabled[validator]) {
            revert InvalidValidator();
        }

        return validator.isValidSignature(digest, innerSignature);
    }

    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external onlyEntryPoint returns (uint256) {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
            (success); // ignore failure since it's the EntryPoint's job to verify
        }

        // If `signature` length is 65, treat it as secp256k1 signature.
        // Otherwise, invoke the specified validator module.
        if (userOp.signature.length == 65) {
            return _verifySignature(userOpHash, userOp.signature) ? 0 : 1;
        }

        (IValidator validator, bytes calldata innerSignature) = _decodeValidator(userOp.signature);

        if (!_getStorage().validatorEnabled[validator]) {
            revert InvalidValidator();
        }

        transientValidator = validator;

        Call[] calldata calls = _decodeCallsFromExecute(userOp.callData);

        return validator.validate(calls, msg.sender, userOpHash, innerSignature) ? 0 : 1;
    }

    function addValidator(IValidator validator) external onlyThis {
        _getStorage().validatorEnabled[validator] = true;
        emit ValidatorAdded(validator);
    }

    function removeValidator(IValidator validator) external onlyThis {
        delete _getStorage().validatorEnabled[validator];
        emit ValidatorRemoved(validator);
    }

    function isValidatorEnabled(IValidator validator) external view returns (bool) {
        return _getStorage().validatorEnabled[validator];
    }

    function entryPoint() public pure returns (address) {
        // https://github.com/eth-infinitism/account-abstraction/releases/tag/v0.8.0
        return ENTRY_POINT_V8;
    }

    function getNonce(uint192 key) external view returns (uint256) {
        Storage storage s = _getStorage();
        return _encodeNonce(key, s.nonceSequenceNumber[key]);
    }

    function invalidateNonce(uint256 newNonce) external onlyThis {
        (uint192 key, uint64 targetSeq) = _decodeNonce(newNonce);
        uint64 currentSeq = _getStorage().nonceSequenceNumber[key];

        if (targetSeq <= currentSeq) {
            revert InvalidNonce();
        }

        // Limit how many nonces can be invalidated at once.
        unchecked {
            uint64 delta = targetSeq - currentSeq;
            if (delta > type(uint16).max) revert ExcessiveInvalidation();
        }

        _getStorage().nonceSequenceNumber[key] = targetSeq;
    }

    function _execute(bytes32 mode, bytes calldata executionData, bool mockSignature) internal {
        (bytes1 callType, bytes1 execType, bytes4 modeSelector,) = _decodeExecutionMode(mode);

        if (callType != CALL_TYPE_BATCH || execType != EXEC_TYPE_DEFAULT) {
            revert UnsupportedExecutionMode();
        }

        Call[] calldata calls = _decodeCalls(executionData);

        if (modeSelector == EXEC_MODE_DEFAULT) {
            // https://eips.ethereum.org/EIPS/eip-7821
            // If `opData` is empty, the implementation SHOULD require that `msg.sender ==
            // address(this)`.
            // If `msg.sender` is an authorized entry point, then `execute` MAY accept calls from
            // the entry point.
            if (msg.sender == address(this)) {
                _executeCalls(calls);
            } else if (msg.sender == entryPoint()) {
                IValidator validator = transientValidator;
                delete transientValidator;

                _executeCalls(calls);

                if (address(validator) != address(0)) {
                    validator.postExecute();
                }
            } else {
                revert Unauthorized();
            }
        } else if (modeSelector == EXEC_MODE_OP_DATA) {
            bytes calldata opData = _decodeOpData(executionData);
            bytes calldata signature = _decodeSignature(opData);

            uint256 nonce = _getAndUseNonce(_decodeNonceKey(opData));
            bytes32 digest = _computeDigest(mode, calls, nonce);

            // If `opData` is not empty, the implementation SHOULD use the signature encoded in
            // `opData` to determine if the caller can perform the execution.
            // If `signature` length is 65, treat it as secp256k1 signature.
            // Otherwise, invoke the specified validator module.
            if (signature.length == 65) {
                if (!_verifySignature(digest, signature) && !mockSignature) {
                    revert Unauthorized();
                }

                _executeCalls(calls);
            } else {
                (IValidator validator, bytes calldata innerSignature) = _decodeValidator(signature);

                if (!_getStorage().validatorEnabled[validator]) {
                    revert InvalidValidator();
                }

                if (
                    !validator.validate(calls, msg.sender, digest, innerSignature) && !mockSignature
                ) {
                    revert Unauthorized();
                }

                _executeCalls(calls);

                validator.postExecute();
            }
        } else {
            revert UnsupportedExecutionMode();
        }
    }

    function _executeCalls(Call[] calldata calls) internal {
        for (uint256 i = 0; i < calls.length; i++) {
            Call calldata call = calls[i];
            address to = call.to == address(0) ? address(this) : call.to;

            (bool success, bytes memory data) = to.call{value: call.value}(call.data);

            if (!success) {
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
        }
    }

    function _decodeCalls(bytes calldata executionData)
        internal
        pure
        returns (Call[] calldata calls)
    {
        // `executionData` is simply `abi.encode(calls)`.
        // We decode this from calldata rather than abi.decode which avoids a memory copy.
        assembly {
            let offset := add(executionData.offset, calldataload(executionData.offset))
            calls.offset := add(offset, 32)
            calls.length := calldataload(offset)
        }
    }

    function _decodeCallsFromExecute(bytes calldata callData)
        internal
        pure
        returns (Call[] calldata calls)
    {
        // `callData` is the call to `execute(bytes32 mode,bytes calldata executionData)` and
        // `executionData` is simply `abi.encode(calls)`.
        // We decode this from calldata rather than abi.decode which avoids a memory copy.
        assembly {
            let executionData := add(callData.offset, 100)
            let offset := add(executionData, calldataload(executionData))
            calls.offset := add(offset, 32)
            calls.length := calldataload(offset)
        }
    }

    function _decodeOpData(bytes calldata executionData)
        internal
        pure
        returns (bytes calldata opData)
    {
        // If `opData` is not empty, `executionData` is `abi.encode(calls, opData)`.
        // We decode this from calldata rather than abi.decode which avoids a memory copy.
        assembly {
            let offset := add(executionData.offset, calldataload(add(executionData.offset, 32)))
            opData.offset := add(offset, 32)
            opData.length := calldataload(offset)
        }
    }

    function _decodeNonceKey(bytes calldata opData) internal pure returns (uint192 nonceKey) {
        assembly {
            nonceKey := shr(64, calldataload(opData.offset))
        }
    }

    function _decodeSignature(bytes calldata opData)
        internal
        pure
        returns (bytes calldata signature)
    {
        assembly {
            signature.offset := add(opData.offset, 24)
            signature.length := sub(opData.length, 24)
        }
    }

    function _decodeSignatureComponents(bytes calldata signature)
        internal
        pure
        returns (bytes32 r, bytes32 s, uint8 v)
    {
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
    }

    function _decodeValidator(bytes calldata signature)
        internal
        pure
        returns (IValidator validator, bytes calldata data)
    {
        // `signature` is `abi.encodePacked(validator, data)`.
        // We decode this from calldata rather than abi.decode which avoids a memory copy.
        assembly {
            validator := shr(96, calldataload(signature.offset))

            data.offset := add(signature.offset, 20)
            data.length := sub(signature.length, 20)
        }
    }

    function _verifySignature(bytes32 digest, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        (bytes32 r, bytes32 s, uint8 v) = _decodeSignatureComponents(signature);

        // https://github.com/openzeppelin/openzeppelin-contracts/blob/v5.3.0/contracts/utils/cryptography/ECDSA.sol#L134-L145
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert InvalidSignatureS();
        }

        address signer = ecrecover(digest, v, r, s);

        if (signer == address(0)) {
            revert InvalidSignature();
        }

        return signer == address(this);
    }

    function _computeDigest(bytes32 mode, Call[] calldata calls, uint256 nonce)
        internal
        view
        returns (bytes32)
    {
        bytes32[] memory callsHashes = new bytes32[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            callsHashes[i] = keccak256(
                abi.encode(CALL_TYPEHASH, calls[i].to, calls[i].value, keccak256(calls[i].data))
            );
        }

        bytes32 executeHash = keccak256(
            abi.encode(EXECUTE_TYPEHASH, mode, keccak256(abi.encodePacked(callsHashes)), nonce)
        );

        return _hashTypedData(executeHash);
    }

    function _getAndUseNonce(uint192 key) internal returns (uint256) {
        uint64 seq = _getStorage().nonceSequenceNumber[key];
        _getStorage().nonceSequenceNumber[key]++;
        return _encodeNonce(key, seq);
    }

    function _encodeNonce(uint192 key, uint64 seq) internal pure returns (uint256) {
        return (uint256(key) << 64) | seq;
    }

    function _decodeNonce(uint256 nonce) internal pure returns (uint192 key, uint64 seq) {
        key = uint192(nonce >> 64);
        seq = uint64(nonce);
    }

    function _getStorage() internal pure returns (Storage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    function _decodeExecutionMode(bytes32 mode)
        internal
        pure
        returns (bytes1 calltype, bytes1 execType, bytes4 modeSelector, bytes22 modePayload)
    {
        // https://eips.ethereum.org/EIPS/eip-7579
        // https://eips.ethereum.org/EIPS/eip-7821
        assembly {
            calltype := mode
            execType := shl(8, mode)
            modeSelector := shl(48, mode)
            modePayload := shl(80, mode)
        }
    }

    function _domainNameAndVersion()
        internal
        pure
        override
        returns (string memory name, string memory version)
    {
        name = "GelatoDelegation";
        version = "0.0.1";
    }
}
