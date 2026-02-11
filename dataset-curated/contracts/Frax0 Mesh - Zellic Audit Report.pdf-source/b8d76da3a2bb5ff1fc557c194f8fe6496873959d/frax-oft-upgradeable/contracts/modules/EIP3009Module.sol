pragma solidity ^0.8.0;

import {SignatureModule} from "./signatureModule/SignatureModule.sol";

/// @title Eip3009
/// @notice Eip3009 provides internal implementations for gas-abstracted transfers under Eip3009 guidelines
/// @author Frax Finance, inspired by Agora (thanks Drake)
abstract contract EIP3009Module is SignatureModule {

    /// @notice keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 internal constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

    /// @notice keccak256("ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 internal constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

    /// @notice keccak256("CancelAuthorization(address authorizer,bytes32 nonce)")
    bytes32 internal constant CANCEL_AUTHORIZATION_TYPEHASH =
        0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429;

    //==============================================================================
    // Storage
    //==============================================================================

    struct EIP3009ModuleStorage {
        mapping(address authorizer => mapping(bytes32 nonce => bool used)) isAuthorizationUsed;
    }

    // keccak256(abi.encode(uint256(keccak256("frax.storage.EIP3009Module")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant EIP3009ModuleStorageLocation = 0x6607eb842e76408d8b3956685dc6b9da5897a1d9b47edcc993ce266e603fa500;

    function _getEIP3009ModuleStorage() private pure returns (EIP3009ModuleStorage storage $) {
        assembly {
            $.slot := EIP3009ModuleStorageLocation
        }
    }

    //==============================================================================
    // Functions
    //==============================================================================

    /// @notice The ```transferWithAuthorization``` function executes a transfer with a signed authorization according to Eip3009
    /// @dev EOA wallet signatures should be packed in the order of r, s, v
    /// @dev added in v1.1.0
    /// @param from Payer's address (Authorizer)
    /// @param to Payee's address
    /// @param value Amount to be transferred
    /// @param validAfter The block.timestamp after which the authorization is valid
    /// @param validBefore The block.timestamp before which the authorization is valid
    /// @param nonce Unique nonce
    /// @param v ECDSA signature parameter v
    /// @param r ECDSA signature parameters r
    /// @param s ECDSA signature parameters s
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
    ) external {
        // Packs signature pieces into bytes
        transferWithAuthorization({
            from: from,
            to: to,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: abi.encodePacked(r, s, v)
        });
    }

    /// @notice The ```transferWithAuthorization``` function executes a transfer with a signed authorization
    /// @dev EOA wallet signatures should be packed in the order of r, s, v
    /// @param from Payer's address (Authorizer)
    /// @param to Payee's address
    /// @param value Amount to be transferred
    /// @param validAfter The time after which this is valid (unix time)
    /// @param validBefore The time before which this is valid (unix time)
    /// @param nonce Unique nonce
    /// @param signature Signature byte array produced by an EOA wallet or a contract wallet
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) public {
        // Checks: authorization validity
        if (block.timestamp <= validAfter) revert InvalidAuthorization();
        if (block.timestamp >= validBefore) revert ExpiredAuthorization();
        _requireUnusedAuthorization({ authorizer: from, nonce: nonce });

        // Checks: valid signature
        _requireIsValidSignatureNow({
            signer: from,
            structHash: keccak256(
                abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
            ),
            signature: signature
        });

        // Effects: mark authorization as used and transfer
        _markAuthorizationAsUsed({ authorizer: from, nonce: nonce });
        _transfer({ from: from, to: to, amount: value });
    }

    /// @notice The ```receiveWithAuthorization``` function receives a transfer with a signed authorization from the payer
    /// @dev This has an additional check to ensure that the payee's address matches the caller of this function to prevent front-running attacks
    /// @dev EOA wallet signatures should be packed in the order of r, s, v
    /// @param from Payer's address (Authorizer)
    /// @param to Payee's address
    /// @param value Amount to be transferred
    /// @param validAfter The block.timestamp after which the authorization is valid
    /// @param validBefore The block.timestamp before which the authorization is valid
    /// @param nonce Unique nonce
    /// @param v ECDSA signature parameter v
    /// @param r ECDSA signature parameters r
    /// @param s ECDSA signature parameters s
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
    ) external {
        // Packs signature pieces into bytes
        receiveWithAuthorization({
            from: from,
            to: to,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: abi.encodePacked(r, s, v)
        });
    }

    /// @notice The ```receiveWithAuthorization``` function receives a transfer with a signed authorization from the payer
    /// @dev This has an additional check to ensure that the payee's address matches the caller of this function to prevent front-running attacks
    /// @dev EOA wallet signatures should be packed in the order of r, s, v
    /// @param from Payer's address (Authorizer)
    /// @param to Payee's address
    /// @param value Amount to be transferred
    /// @param validAfter The block.timestamp after which the authorization is valid
    /// @param validBefore The block.timestamp before which the authorization is valid
    /// @param nonce Unique nonce
    /// @param signature Signature byte array produced by an EOA wallet or a contract wallet
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) public {
        // Checks: authorization validity
        if (to != msg.sender) revert InvalidPayee({ caller: msg.sender, payee: to });
        if (block.timestamp <= validAfter) revert InvalidAuthorization();
        if (block.timestamp >= validBefore) revert ExpiredAuthorization();
        _requireUnusedAuthorization({ authorizer: from, nonce: nonce });

        // Checks: valid signature
        _requireIsValidSignatureNow({
            signer: from,
            structHash: keccak256(
                abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
            ),
            signature: signature
        });

        // Effects: mark authorization as used and transfer
        _markAuthorizationAsUsed({ authorizer: from, nonce: nonce });
        _transfer({ from: from, to: to, amount: value });
    }

    /// @notice The ```cancelAuthorization``` function cancels an authorization nonce
    /// @dev EOA wallet signatures should be packed in the order of r, s, v
    /// @param authorizer   Authorizer's address
    /// @param nonce        Nonce of the authorization
    /// @param v            ECDSA signature v value
    /// @param r            ECDSA signature r value
    /// @param s            ECDSA signature s value
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external {
        cancelAuthorization({ authorizer: authorizer, nonce: nonce, signature: abi.encodePacked(r, s, v) });
    }

    /// @notice The ```cancelAuthorization``` function cancels an authorization nonce
    /// @dev EOA wallet signatures should be packed in the order of r, s, v
    /// @param authorizer    Authorizer's address
    /// @param nonce         Nonce of the authorization
    /// @param signature     Signature byte array produced by an EOA wallet or a contract wallet
    function cancelAuthorization(address authorizer, bytes32 nonce, bytes memory signature) public {
        _requireUnusedAuthorization({ authorizer: authorizer, nonce: nonce });
        _requireIsValidSignatureNow({
            signer: authorizer,
            structHash: keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce)),
            signature: signature
        });

        _getEIP3009ModuleStorage().isAuthorizationUsed[authorizer][nonce] = true;
        emit AuthorizationCanceled({ authorizer: authorizer, nonce: nonce });
    }

    //==============================================================================
    // Internal Checks Functions
    //==============================================================================

    /// @notice The ```_requireUnusedAuthorization``` checks that an authorization nonce is unused
    /// @param authorizer    Authorizer's address
    /// @param nonce         Nonce of the authorization
    function _requireUnusedAuthorization(address authorizer, bytes32 nonce) private view {
        if (_getEIP3009ModuleStorage().isAuthorizationUsed[authorizer][nonce])
            revert UsedOrCanceledAuthorization();
    }

    //==============================================================================
    // Internal Effects Functions
    //==============================================================================

    /// @notice The ```_markAuthorizationAsUsed``` function marks an authorization nonce as used
    /// @param authorizer    Authorizer's address
    /// @param nonce         Nonce of the authorization
    function _markAuthorizationAsUsed(address authorizer, bytes32 nonce) private {
        _getEIP3009ModuleStorage().isAuthorizationUsed[authorizer][nonce] = true;
        emit AuthorizationUsed({ authorizer: authorizer, nonce: nonce });
    }

    //==============================================================================
    // Views
    //==============================================================================

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
        return _getEIP3009ModuleStorage().isAuthorizationUsed[authorizer][nonce];
    }

    //==============================================================================
    // Overridden methods
    //==============================================================================

    function _transfer(address from, address to, uint256 amount) internal virtual {}

    //==============================================================================
    // Events
    //==============================================================================

    /// @notice ```AuthorizationUsed``` event is emitted when an authorization is used
    /// @param authorizer Authorizer's address
    /// @param nonce Nonce of the authorization
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    /// @notice ```AuthorizationCanceled``` event is emitted when an authorization is canceled
    /// @param authorizer Authorizer's address
    /// @param nonce Nonce of the authorization
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    //==============================================================================
    // Errors
    //==============================================================================

    /// @notice The ```InvalidPayee``` error is emitted when the payee does not match sender in receiveWithAuthorization
    /// @param caller The caller of the function
    /// @param payee The expected payee in the function
    error InvalidPayee(address caller, address payee);

    /// @notice The ```InvalidAuthorization``` error is emitted when the authorization is invalid because its too early
    error InvalidAuthorization();

    /// @notice The ```ExpiredAuthorization``` error is emitted when the authorization is expired
    error ExpiredAuthorization();

    /// @notice The ```UsedOrCanceledAuthorization``` error is emitted when the authorization nonce is already used or canceled
    error UsedOrCanceledAuthorization();
}