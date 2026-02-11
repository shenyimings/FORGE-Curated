// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { Transaction } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IModuleValidator } from "../interfaces/IModuleValidator.sol";
import { IModule } from "../interfaces/IModule.sol";
import { VerifierCaller } from "../helpers/VerifierCaller.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Base64 } from "solady/src/utils/Base64.sol";
import { JSONParserLib } from "solady/src/utils/JSONParserLib.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title WebAuthValidator
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @dev This contract allows secure user authentication using WebAuthn public keys.
contract WebAuthValidator is VerifierCaller, IModuleValidator {
  using JSONParserLib for JSONParserLib.Item;
  using JSONParserLib for string;

  /// @dev P256Verify precompile implementation, as defined in RIP-7212, is found at
  /// https://github.com/matter-labs/era-contracts/blob/main/system-contracts/contracts/precompiles/P256Verify.yul
  address private constant P256_VERIFIER = address(0x100);

  error NOT_KEY_OWNER(address account);

  // check for secure validation: bit 0 = 1 (user present), bit 2 = 1 (user verified)
  bytes1 private constant AUTH_DATA_MASK = 0x05;
  bytes32 private constant LOW_S_MAX = 0x7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8;
  bytes32 private constant HIGH_R_MAX = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551;

  event PasskeyCreated(address indexed keyOwner, string originDomain, bytes credentialId);
  event PasskeyRemoved(address indexed keyOwner, string originDomain, bytes credentialId);

  mapping(string originDomain => mapping(bytes credentialId => mapping(address accountAddress => bytes32[2] publicKey)))
    public publicKeys;

  function getAccountKey(
    string calldata originDomain,
    bytes calldata credentialId,
    address accountAddress
  ) external view returns (bytes32[2] memory) {
    return publicKeys[originDomain][credentialId][accountAddress];
  }

  mapping(string originDomain => mapping(bytes credentialId => address accountAddress)) public registeredAddress;

  struct PasskeyId {
    string domain;
    bytes credentialId;
  }

  /// @notice Runs on module install
  /// @param data ABI-encoded WebAuthn passkey to add immediately, or empty if not needed
  function onInstall(bytes calldata data) external override {
    if (data.length > 0) {
      (bytes memory credentialId, bytes32[2] memory rawPublicKey, string memory originDomain) = abi.decode(
        data,
        (bytes, bytes32[2], string)
      );
      if (!addValidationKey(credentialId, rawPublicKey, originDomain)) {
        revert Errors.WEBAUTHN_KEY_EXISTS();
      }
    }
  }

  /// @notice Runs on module uninstall
  /// @param data ABI-encoded array of origin domains to remove keys for
  function onUninstall(bytes calldata data) external override {
    PasskeyId[] memory passkeyIds = abi.decode(data, (PasskeyId[]));
    for (uint256 i = 0; i < passkeyIds.length; i++) {
      PasskeyId memory passkeyId = passkeyIds[i];
      removeValidationKey(passkeyId.credentialId, passkeyId.domain);
    }
  }

  function removeValidationKey(bytes memory credentialId, string memory domain) public {
    if (registeredAddress[domain][credentialId] != msg.sender) {
      revert NOT_KEY_OWNER(registeredAddress[domain][credentialId]);
    }
    registeredAddress[domain][credentialId] = address(0);
    publicKeys[domain][credentialId][msg.sender] = [bytes32(0), bytes32(0)];

    emit PasskeyRemoved(msg.sender, domain, credentialId);
  }

  /// @notice Adds a WebAuthn passkey for the caller
  /// @param credentialId unique public identifier for the key
  /// @param rawPublicKey ABI-encoded WebAuthn public key to add
  /// @param originDomain the domain this associated with
  /// @return true if the key was added, false if one already exists
  function addValidationKey(
    bytes memory credentialId,
    bytes32[2] memory rawPublicKey,
    string memory originDomain
  ) public returns (bool) {
    bytes32[2] memory initialAccountKey = publicKeys[originDomain][credentialId][msg.sender];
    if (uint256(initialAccountKey[0]) != 0 || uint256(initialAccountKey[1]) != 0) {
      // only allow adding new keys, no overwrites/updates
      return false;
    }
    if (registeredAddress[originDomain][credentialId] != address(0)) {
      // this key already exists on the domain for an existing account
      return false;
    }
    if (rawPublicKey[0] == 0 && rawPublicKey[1] == 0) {
      // empty keys aren't valid
      return false;
    }

    publicKeys[originDomain][credentialId][msg.sender] = rawPublicKey;
    registeredAddress[originDomain][credentialId] = msg.sender;

    emit PasskeyCreated(msg.sender, originDomain, credentialId);

    return true;
  }

  /// @notice Validates a WebAuthn signature
  /// @param signedHash The hash of the signed message
  /// @param signature The signature to validate
  /// @return true if the signature is valid
  function validateSignature(bytes32 signedHash, bytes calldata signature) external view returns (bool) {
    return webAuthVerify(signedHash, signature);
  }

  /// @notice Validates a transaction signed with a passkey
  /// @dev Does not validate the transaction signature field, which is expected to be different due to the modular format
  /// @param signedHash The hash of the signed transaction
  /// @param transaction The transaction to validate
  /// @return true if the signature is valid
  function validateTransaction(bytes32 signedHash, Transaction calldata transaction) external view returns (bool) {
    (bytes memory signature, , ) = abi.decode(transaction.signature, (bytes, address, bytes));
    return webAuthVerify(signedHash, signature);
  }

  /// @notice Validates a WebAuthn signature
  /// @dev Performs r & s range validation to prevent signature malleability
  /// @dev Checks passkey authenticator data flags (valid number of credentials)
  /// @dev Requires that the transaction signature hash was the signed challenge
  /// @dev Verifies that the signature was performed by a 'get' request
  /// @param transactionHash The hash of the signed message
  /// @param fatSignature The signature to validate (authenticator data, client data, [r, s])
  /// @return true if the signature is valid
  function webAuthVerify(bytes32 transactionHash, bytes memory fatSignature) internal view returns (bool) {
    (
      bytes memory authenticatorData,
      string memory clientDataJSON,
      bytes32[2] memory rs,
      bytes memory credentialId
    ) = _decodeFatSignature(fatSignature);

    // prevent signature replay https://yondon.blog/2019/01/01/how-not-to-use-ecdsa/
    if (uint256(rs[0]) == 0 || rs[0] > HIGH_R_MAX || uint256(rs[1]) == 0 || rs[1] > LOW_S_MAX) {
      return false;
    }

    // https://developer.mozilla.org/en-US/docs/Web/API/Web_Authentication_API/Authenticator_data#attestedcredentialdata
    if (authenticatorData[32] & AUTH_DATA_MASK != AUTH_DATA_MASK) {
      return false;
    }

    // parse out the required fields (type, challenge, crossOrigin): https://goo.gl/yabPex
    JSONParserLib.Item memory root = JSONParserLib.parse(clientDataJSON);
    // challenge should contain the transaction hash, ensuring that the transaction is signed
    string memory challenge = root.at('"challenge"').value().decodeString();
    bytes memory challengeData = Base64.decode(challenge);
    if (challengeData.length != 32) {
      return false; // wrong hash size
    }
    if (bytes32(challengeData) != transactionHash) {
      return false;
    }

    // type ensures the signature was created from a validation request
    string memory type_ = root.at('"type"').value().decodeString();
    if (!Strings.equal("webauthn.get", type_)) {
      return false;
    }

    // the origin determines which key to validate against
    // as passkeys are linked to domains, so the storage mapping reflects that
    string memory origin = root.at('"origin"').value().decodeString();
    bytes32[2] memory publicKey = publicKeys[origin][credentialId][msg.sender];
    if (uint256(publicKey[0]) == 0 && uint256(publicKey[1]) == 0) {
      // no key found!
      return false;
    }

    // cross-origin validation is optional, but explicitly not supported.
    // cross-origin requests would be from embedding the auth request
    // from another domain. The current SSO setup uses a pop-up instead of
    // an i-frame, so we're rejecting these until the implemention supports it
    JSONParserLib.Item memory crossOriginItem = root.at('"crossOrigin"');
    if (!crossOriginItem.isUndefined()) {
      string memory crossOrigin = crossOriginItem.value();
      if (!Strings.equal("false", crossOrigin)) {
        return false;
      }
    }

    bytes32 message = _createMessage(authenticatorData, bytes(clientDataJSON));
    return callVerifier(P256_VERIFIER, message, rs, publicKey);
  }

  /// @inheritdoc IERC165
  function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
    return
      interfaceId == type(IERC165).interfaceId ||
      interfaceId == type(IModuleValidator).interfaceId ||
      interfaceId == type(IModule).interfaceId;
  }

  function _createMessage(
    bytes memory authenticatorData,
    bytes memory clientData
  ) private pure returns (bytes32 message) {
    bytes32 clientDataHash = sha256(clientData);
    message = sha256(bytes.concat(authenticatorData, clientDataHash));
  }

  function _decodeFatSignature(
    bytes memory fatSignature
  )
    private
    pure
    returns (
      bytes memory authenticatorData,
      string memory clientDataSuffix,
      bytes32[2] memory rs,
      bytes memory credentialId
    )
  {
    (authenticatorData, clientDataSuffix, rs, credentialId) = abi.decode(
      fatSignature,
      (bytes, string, bytes32[2], bytes)
    );
  }
}
