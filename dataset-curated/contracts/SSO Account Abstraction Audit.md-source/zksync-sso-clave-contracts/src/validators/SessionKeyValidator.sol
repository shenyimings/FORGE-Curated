// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Transaction } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { IModuleValidator } from "../interfaces/IModuleValidator.sol";
import { IModule } from "../interfaces/IModule.sol";
import { IValidatorManager } from "../interfaces/IValidatorManager.sol";
import { SessionLib } from "../libraries/SessionLib.sol";
import { SignatureDecoder } from "../libraries/SignatureDecoder.sol";
import { TimestampAsserterLocator } from "../helpers/TimestampAsserterLocator.sol";

/// @title SessionKeyValidator
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice This contract is used to manage sessions for a smart account.
contract SessionKeyValidator is IModuleValidator {
  using SessionLib for SessionLib.SessionStorage;

  event SessionCreated(address indexed account, bytes32 indexed sessionHash, SessionLib.SessionSpec sessionSpec);
  event SessionRevoked(address indexed account, bytes32 indexed sessionHash);

  // account => number of open sessions
  // NOTE: expired sessions are still counted if not explicitly revoked
  mapping(address => uint256) private sessionCounter;
  // session hash => session state
  mapping(bytes32 => SessionLib.SessionStorage) private sessions;

  /// @notice Get the session state for an account
  /// @param account The account to fetch the session state for
  /// @param spec The session specification to get the state of
  /// @return The session state: status, remaining fee limit, transfer limits, call value and call parameter limits
  function sessionState(
    address account,
    SessionLib.SessionSpec calldata spec
  ) external view returns (SessionLib.SessionState memory) {
    return sessions[keccak256(abi.encode(spec))].getState(account, spec);
  }

  /// @notice Get the status of a session
  /// @param account The account to fetch the session status for
  /// @param sessionHash The session hash to fetch the status of
  /// @return The status of the session: NotInitialized, Active or Closed
  function sessionStatus(address account, bytes32 sessionHash) external view returns (SessionLib.Status) {
    return sessions[sessionHash].status[account];
  }

  /// @notice Runs on module install
  /// @param data ABI-encoded session specification to immediately create a session, or empty if not needed
  function onInstall(bytes calldata data) external override {
    if (data.length > 0) {
      require(_addValidationKey(data), "SessionKeyValidator: failed to add key");
    }
  }

  /// @notice Runs on module uninstall
  /// @param data ABI-encoded array of session hashes to revoke
  /// @dev Revokes provided sessions before uninstalling,
  /// reverts if any session is still active after that.
  function onUninstall(bytes calldata data) external override {
    // Revoke keys before uninstalling
    bytes32[] memory sessionHashes = abi.decode(data, (bytes32[]));
    for (uint256 i = 0; i < sessionHashes.length; i++) {
      revokeKey(sessionHashes[i]);
    }
    // Here we have make sure that all keys are revoked, so that if the module
    // is installed again later, there will be no active sessions from the past.
    require(sessionCounter[msg.sender] == 0, "Revoke all keys first");
  }

  /// @notice This module should not be used to validate signatures
  /// @return false
  function validateSignature(bytes32, bytes memory) external pure returns (bool) {
    return false;
  }

  /// @notice Create a new session for an account
  /// @param sessionSpec The session specification to create a session with
  function createSession(SessionLib.SessionSpec memory sessionSpec) public {
    bytes32 sessionHash = keccak256(abi.encode(sessionSpec));
    require(isInitialized(msg.sender), "Account not initialized");
    require(sessionSpec.signer != address(0), "Invalid signer (create)");
    require(sessions[sessionHash].status[msg.sender] == SessionLib.Status.NotInitialized, "Session already exists");
    require(sessionSpec.feeLimit.limitType != SessionLib.LimitType.Unlimited, "Unlimited fee allowance is not safe");
    // Sessions should expire in no less than 60 seconds.
    uint256 minuteBeforeExpiration = sessionSpec.expiresAt <= 60 ? 0 : sessionSpec.expiresAt - 60;
    TimestampAsserterLocator.locate().assertTimestampInRange(0, minuteBeforeExpiration);

    sessionCounter[msg.sender]++;
    sessions[sessionHash].status[msg.sender] = SessionLib.Status.Active;
    emit SessionCreated(msg.sender, sessionHash, sessionSpec);
  }

  /// @notice creates a new session for an account, called by onInstall
  /// @param sessionData ABI-encoded session specification
  function _addValidationKey(bytes calldata sessionData) internal returns (bool) {
    SessionLib.SessionSpec memory sessionSpec = abi.decode(sessionData, (SessionLib.SessionSpec));
    createSession(sessionSpec);
    return true;
  }

  /// @inheritdoc IERC165
  function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
    return
      interfaceId == type(IERC165).interfaceId ||
      interfaceId == type(IModuleValidator).interfaceId ||
      interfaceId == type(IModule).interfaceId;
  }

  /// @notice Revoke a session for an account
  /// @param sessionHash The hash of a session to revoke
  /// @dev Decreases the session counter for the account
  function revokeKey(bytes32 sessionHash) public {
    require(sessions[sessionHash].status[msg.sender] == SessionLib.Status.Active, "Nothing to revoke");
    sessions[sessionHash].status[msg.sender] = SessionLib.Status.Closed;
    sessionCounter[msg.sender]--;
    emit SessionRevoked(msg.sender, sessionHash);
  }

  /// @notice Revoke multiple sessions for an account
  /// @param sessionHashes An array of session hashes to revoke
  function revokeKeys(bytes32[] calldata sessionHashes) external {
    for (uint256 i = 0; i < sessionHashes.length; i++) {
      revokeKey(sessionHashes[i]);
    }
  }

  /// @notice Check if the validator is registered for the smart account
  /// @param smartAccount The smart account to check
  /// @return true if validator is registered for the account, false otherwise
  function isInitialized(address smartAccount) public view returns (bool) {
    return IValidatorManager(smartAccount).isModuleValidator(address(this));
  }

  /// @notice Validate a session transaction for an account
  /// @param signedHash The hash of the transaction
  /// @param transaction The transaction to validate
  /// @return true if the transaction is valid
  /// @dev Session spec and period IDs must be provided as validator data
  function validateTransaction(
    bytes32 signedHash,
    bytes calldata,
    Transaction calldata transaction
  ) external returns (bool) {
    (bytes memory transactionSignature, address _validator, bytes memory validatorData) = SignatureDecoder
      .decodeSignature(transaction.signature);
    (SessionLib.SessionSpec memory spec, uint64[] memory periodIds) = abi.decode(
      validatorData, // this is passed by the signature builder
      (SessionLib.SessionSpec, uint64[])
    );
    require(spec.signer != address(0), "Invalid signer (empty)");
    bytes32 sessionHash = keccak256(abi.encode(spec));
    // this generally throws instead of returning false
    sessions[sessionHash].validate(transaction, spec, periodIds);
    (address recoveredAddress, ECDSA.RecoverError recoverError) = ECDSA.tryRecover(signedHash, transactionSignature);
    if (recoverError != ECDSA.RecoverError.NoError || recoveredAddress == address(0)) {
      return false;
    }
    require(recoveredAddress == spec.signer, "Invalid signer (mismatch)");
    // This check is separate and performed last to prevent gas estimation failures
    sessions[sessionHash].validateFeeLimit(transaction, spec, periodIds[0]);
    return true;
  }
}
