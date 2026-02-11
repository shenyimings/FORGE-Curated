/**
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2020 CENTRE SECZ
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

pragma solidity 0.8.26;

import { ERC20Permit } from "./ERC20PermitWithERC1271.sol";
import { IERC1271 } from "@openzeppelin/interfaces/IERC1271.sol";

/**
 * `TransferWithAuthorization` is the struct identifier name.
 * - `address` is the atomic type of named `the sender`.
 * - `address` is the atomic type of named `the receiver`.
 * - `uint256` is the atomic type of named `value`.
 * - `uint256` is the atomic type of named `validAfter`
 * - `uint256` is the atomic type of named `validBefore`
 * - `uint256` is the atomic type of the randomly 
 *    generated value during the signing process named `nonce`.
 */
struct TransferWithAuthorization {
    address from;
    address to;
    uint256 value;
    uint256 validAfter;
    uint256 validBefore;
    uint256 nonce;
}

/**
 * `ReceiveWithAuthorization` is the struct identifier name.
 * - `address` is the atomic type of named `the sender`.
 * - `address` is the atomic type of named `the receiver`.
 * - `uint256` is the atomic type of named `value`.
 * - `uint256` is the atomic type of named `validAfter`
 * - `uint256` is the atomic type of named `validBefore`
 * - `uint256` is the atomic type of the randomly 
 *    generated value during the signing process named `nonce`.
 */
struct ReceiveWithAuthorization {
    address from;
    address to;
    uint256 value;
    uint256 validAfter;
    uint256 validBefore;
    uint256 nonce;
}

/**
 * `CancelWithAuthorization` is the struct identifier name.
 * - `address` is the atomic type of named `the authorizaer`.
 * - `uint256` is the atomic type of the randomly 
 *    generated value during the signing process named `nonce`.
 */
struct CancelAuthorization {
    address authorizer;
    uint256 nonce;
}


abstract contract EIP3009 is ERC20Permit {
    // keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32
        public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = 0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

    // keccak256("ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32
        public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = 0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

    // keccak256("CancelAuthorization(address authorizer,bytes32 nonce)")
    bytes32
        public constant CANCEL_AUTHORIZATION_TYPEHASH = 0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429;

    /**
     * @dev authorizer address => nonce => state (true = used / false = unused)
     */
    mapping(address => mapping(bytes32 => bool)) internal _authorizationStates;

    /**
     * @dev Invalid signature for authorization.
     */
    error EIP3009InvalidSignature();

    /**
     * @dev Authorization has already been used.
     */
    error EIP3009AuthorizationAlreadyUsed(address authorizer, bytes32 nonce);

    /**
     * @dev Authorization is not yet valid.
     */
    error EIP3009AuthorizationNotYetValid(uint256 validAfter, uint256 currentTime);

    /**
     * @dev Authorization has expired.
     */
    error EIP3009AuthorizationExpired(uint256 validBefore, uint256 currentTime);

    /**
     * @dev Caller is not the payee.
     */
    error EIP3009CallerMustBePayee(address caller, address payee);

    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(
        address indexed authorizer,
        bytes32 indexed nonce
    );

    /**
     * @notice Returns the state of an authorization
     * @dev Nonces are randomly generated 32-byte data unique to the authorizer's
     * address
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     * @return True if the nonce is used
     */
    function authorizationState(address authorizer, bytes32 nonce)
        external
        virtual
        view
        returns (bool)
    {
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
    ) external virtual {
        bytes memory signature = rsvToSig(r, s, v);
        transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, signature);
    }

    /**
     * @notice Execute a transfer with a signed authorization (bytes signature for 7702/passkey)
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param signature     Signature bytes
     */
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) public virtual {
        _transferWithAuthorizationBytes(
            TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            signature
        );
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
    ) external virtual {
        bytes memory signature = rsvToSig(r, s, v);
        receiveWithAuthorization(from, to, value, validAfter, validBefore, nonce, signature);
    }

    /**
     * @notice Receive a transfer with a signed authorization (bytes signature for 7702/passkey)
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param signature     Signature bytes
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) public virtual {
        if (to != msg.sender) {
            revert EIP3009CallerMustBePayee(msg.sender, to);
        }

        _transferWithAuthorizationBytes(
            RECEIVE_WITH_AUTHORIZATION_TYPEHASH,
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            signature
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
    ) external virtual {
        bytes memory signature = rsvToSig(r, s, v);
        cancelAuthorization(authorizer, nonce, signature);
    }

    /**
     * @notice Cancel an authorization (bytes signature for 7702/passkey)
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     * @param signature     Signature bytes
     */
    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        bytes memory signature
    ) public virtual {
        if (_authorizationStates[authorizer][nonce]) {
            revert EIP3009AuthorizationAlreadyUsed(authorizer, nonce);
        }

        bytes32 structHash = keccak256(abi.encode(
            CANCEL_AUTHORIZATION_TYPEHASH,
            authorizer,
            nonce
        ));
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparatorV4(),
                structHash
            )
        );
        
        if (!_verifySig(authorizer, digest, signature)) {
            revert EIP3009InvalidSignature();
        }

        _authorizationStates[authorizer][nonce] = true;
        emit AuthorizationCanceled(authorizer, nonce);
    }

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
    ) internal virtual {
        bytes memory signature = rsvToSig(r, s, v);
        _transferWithAuthorizationBytes(typeHash, from, to, value, validAfter, validBefore, nonce, signature);
    }

    function _transferWithAuthorizationBytes(
        bytes32 typeHash,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) internal virtual {
        if (block.timestamp <= validAfter) {
            revert EIP3009AuthorizationNotYetValid(validAfter, block.timestamp);
        }
        if (block.timestamp >= validBefore) {
            revert EIP3009AuthorizationExpired(validBefore, block.timestamp);
        }
        if (_authorizationStates[from][nonce]) {
            revert EIP3009AuthorizationAlreadyUsed(from, nonce);
        }

        bytes32 structHash = keccak256(abi.encode(
            typeHash,
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce
        ));
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparatorV4(),
                structHash
            )
        );
        
        if (!_verifySig(from, digest, signature)) {
            revert EIP3009InvalidSignature();
        }

        _authorizationStates[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);

        _transfer(from, to, value);
    }
}