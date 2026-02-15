// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PaxosBaseAbstract} from "./PaxosBaseAbstract.sol";
import {EIP712} from "./EIP712.sol";

/**
 * @title EIP3009 contract
 * @dev An abstract contract to provide EIP3009 functionality.
 * @notice These functions do not prevent replay attacks when an initial 
 * transaction fails. If conditions change, such as the contract going
 * from paused to unpaused, an external observer can reuse the data from the 
 * failed transaction to execute it later.
 * @custom:security-contact smart-contract-security@paxos.com
 */
abstract contract EIP3009 is PaxosBaseAbstract {
    // keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

    // keccak256("ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

    // keccak256("CancelAuthorization(address authorizer,bytes32 nonce)")
    bytes32 public constant CANCEL_AUTHORIZATION_TYPEHASH =
        0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429;

    /**
     * @dev authorizer address => nonce => state (true = used / false = unused)
     */
    mapping(address => mapping(bytes32 => bool)) internal _authorizationStates;
    // Storage gap: https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#storage-gaps
    uint256[10] private __gap_EIP3009; // solhint-disable-line var-name-mixedcase

    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(
        address indexed authorizer,
        bytes32 indexed nonce
    );
    event AuthorizationAlreadyUsed(address indexed authorizer, bytes32 indexed nonce);

    error CallerMustBePayee();
    error AuthorizationInvalid();
    error AuthorizationExpired();
    error BlockedAccountAuthorizer();

    /**
     * @notice Returns the state of an authorization
     * @dev Nonces are randomly generated 32-byte data unique to the authorizer's
     * address
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     * @return True if the nonce is used
     */
    function authorizationState(
        address authorizer,
        bytes32 nonce
    ) external view returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }

    /**
     * @notice Execute a transfer with a signed authorization
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused {
        _transferWithAuthorization(
            TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /**
     * @notice Execute a batched transfer with signed authorizations
     * @param from          Array of payer addresses
     * @param to            Array of payee addresses
     * @param value         Array of amounts to be transferred
     * @param validAfter    Array of times after which the transfer is valid (unix time)
     * @param validBefore   Array of times before which the transfer is valid (unix time)
     * @param nonce         Array of unique nonces
     * @param v             Array of v part of the signatures
     * @param r             Array of r part of the signatures
     * @param s             Array of s part of the signatures
     */
    function transferWithAuthorizationBatch(
        address[] memory from,
        address[] memory to,
        uint256[] memory value,
        uint256[] memory validAfter,
        uint256[] memory validBefore,
        bytes32[] memory nonce,
        uint8[] memory v,
        bytes32[] memory r,
        bytes32[] memory s
    ) external whenNotPaused {
        if (
            !(to.length == from.length &&
                value.length == from.length &&
                validAfter.length == from.length &&
                validBefore.length == from.length &&
                nonce.length == from.length &&
                v.length == from.length &&
                r.length == from.length &&
                s.length == from.length)
        ) {
            revert ArgumentLengthMismatch();
        }

        for (uint256 i = 0; i < from.length;) {
            _transferWithAuthorization(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                from[i],
                to[i],
                value[i],
                validAfter[i],
                validBefore[i],
                nonce[i],
                v[i],
                r[i],
                s[i]
            );
            unchecked { ++i; }
        }
    }

    /**
     * @notice Receive a transfer with a signed authorization from the payer
     * @dev This has an additional check to ensure that the payee's address matches
     * the caller of this function to prevent front-running attacks. (See security
     * considerations)
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused {
        if (to != msg.sender) revert CallerMustBePayee();

        _transferWithAuthorization(
            RECEIVE_WITH_AUTHORIZATION_TYPEHASH,
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /**
     * @notice Attempt to cancel an authorization
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused {
        if (isAddrBlocked(authorizer)) revert BlockedAccountAuthorizer();

        if (_authorizationStates[authorizer][nonce]) {
            emit AuthorizationAlreadyUsed(authorizer, nonce);
            return; //Return instead of throwing an error to prevent revert of a complex transaction with authorized inner transactions. Helps preventing the frontrunning tx to cause griefing
        }

        bytes memory data = abi.encode(
            CANCEL_AUTHORIZATION_TYPEHASH,
            authorizer,
            nonce
        );

        if (EIP712.recover(DOMAIN_SEPARATOR(), v, r, s, data) != authorizer)
            revert InvalidSignature();

        _authorizationStates[authorizer][nonce] = true;
        emit AuthorizationCanceled(authorizer, nonce);
    }

    /**
     * @notice Internal function to execute a transfer with a signed authorization
     * @param typeHash      Hash of the authorization type
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function _transferWithAuthorization(
        bytes32 typeHash,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        if (block.timestamp <= validAfter) revert AuthorizationInvalid();
        if (block.timestamp >= validBefore) revert AuthorizationExpired();

        if (_authorizationStates[from][nonce]) {
            emit AuthorizationAlreadyUsed(from, nonce);
            return; //Return instead of throwing an error to prevent revert of a complex transaction with authorized inner transactions. Helps preventing the frontrunning tx to cause griefing
        }

        bytes memory data = abi.encode(
            typeHash,
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce
        );
        if (EIP712.recover(DOMAIN_SEPARATOR(), v, r, s, data) != from)
            revert InvalidSignature();

        _authorizationStates[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);

        _transfer(from, to, value);
    }
}
