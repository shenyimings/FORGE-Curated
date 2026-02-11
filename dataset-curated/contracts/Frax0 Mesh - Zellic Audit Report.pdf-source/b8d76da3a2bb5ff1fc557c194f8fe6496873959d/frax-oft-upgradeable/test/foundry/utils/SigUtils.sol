// SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;

// NO NEED TO AUDIT. USED FOR TESTS ONLY
contract SigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    // keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

    // keccak256("ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

    // keccak256("CancelAuthorization(address authorizer,bytes32 nonce)")
    bytes32 public constant CANCEL_AUTHORIZATION_TYPEHASH =
        0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429;


    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    function getPermitStructHash(Permit memory _permit) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    _permit.owner,
                    _permit.spender,
                    _permit.value,
                    _permit.nonce,
                    _permit.deadline
                )
            );
    }

    function getPermitTypedDataHash(Permit memory _permit) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getPermitStructHash(_permit)
                )
            );
    }

    struct Authorization {
        address from;
        address to;
        uint256 value;
        uint256 validAfter;
        uint256 validBefore;
        bytes32 nonce;
    }

    function getTransferWithAuthorizationStructHash(Authorization memory _authorization) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                    _authorization.from,
                    _authorization.to,
                    _authorization.value,
                    _authorization.validAfter,
                    _authorization.validBefore,
                    _authorization.nonce
                )
            );
    }

    function getTransferWithAuthorizationTypedDataHash(Authorization memory _authorization) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getTransferWithAuthorizationStructHash(_authorization)
                )
            );
    }

    function getReceivewithAuthorizationStructHash(Authorization memory _authorization) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    RECEIVE_WITH_AUTHORIZATION_TYPEHASH,
                    _authorization.from,
                    _authorization.to,
                    _authorization.value,
                    _authorization.validAfter,
                    _authorization.validBefore,
                    _authorization.nonce
                )
            );
    }

    function getReceiveWithAuthorizationTypedDataHash(Authorization memory _authorization) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getReceivewithAuthorizationStructHash(_authorization)
                )
            );
    }

    struct CancelAuthorization {
        address authorizer;
        bytes32 nonce;
    }

    function getCancelAuthorizationStructHash(CancelAuthorization memory _cancelAuthorization) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    CANCEL_AUTHORIZATION_TYPEHASH,
                    _cancelAuthorization.authorizer,
                    _cancelAuthorization.nonce
                )
            );
    }

    function getCancelAuthorizationTypedDataHash(CancelAuthorization memory _cancelAuthorization) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getCancelAuthorizationStructHash(_cancelAuthorization)
                )
            );
    }
}
