// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Transaction } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { EnumerableSetUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import { WebAuthValidator } from "./WebAuthValidator.sol";
import { IGuardianRecoveryValidator } from "../interfaces/IGuardianRecoveryValidator.sol";
import { IModuleValidator } from "../interfaces/IModuleValidator.sol";
import { IModule } from "../interfaces/IModule.sol";
import { TimestampAsserterLocator } from "../helpers/TimestampAsserterLocator.sol";
import { BatchCaller, Call } from "../batch/BatchCaller.sol";

contract GuardianRecoveryValidator is Initializable, IGuardianRecoveryValidator {
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

  struct Guardian {
    address addr;
    bool isReady;
    uint64 addedAt;
  }

  struct RecoveryRequest {
    bytes32 hashedCredentialId;
    bytes32[2] rawPublicKey;
    uint256 timestamp;
  }

  error GuardianCannotBeSelf();
  error GuardianNotFound(address guardian);
  error GuardianNotProposed(address guardian);
  error AccountAlreadyGuardedByGuardian(address account, address guardian);
  error AccountNotGuardedByAddress(address account, address guardian);
  error PasskeyNotMatched();
  error CooldownPeriodNotPassed();
  error ExpiredRequest();

  event RecoveryInitiated(
    address indexed account,
    bytes32 indexed hashedOriginDomain,
    bytes32 indexed hashedCredentialId,
    address guardian
  );
  event RecoveryFinished(
    address indexed account,
    bytes32 indexed hashedOriginDomain,
    bytes32 indexed hashedCredentialId
  );
  event RecoveryDiscarded(
    address indexed account,
    bytes32 indexed hashedOriginDomain,
    bytes32 indexed hashedCredentialId
  );
  event GuardianProposed(address indexed account, bytes32 indexed hashedOriginDomain, address indexed guardian);
  event GuardianAdded(address indexed account, bytes32 indexed hashedOriginDomain, address indexed guardian);
  event GuardianRemoved(address indexed account, bytes32 indexed hashedOriginDomain, address indexed guardian);

  uint256 public constant REQUEST_VALIDITY_TIME = 72 * 60 * 60; // 72 hours
  uint256 public constant REQUEST_DELAY_TIME = 24 * 60 * 60; // 24 hours

  bytes30 private _gap; // Gap to claim 30 bytes remaining in slot 0 after fields layout of Initializable contract
  WebAuthValidator public webAuthValidator; // Enforced slot 1 in order to be able to access it during validateTransaction step
  mapping(bytes32 hashedOriginDomain => mapping(address account => EnumerableSetUpgradeable.AddressSet))
    private accountGuardians;
  mapping(bytes32 hashedOriginDomain => mapping(address guardian => EnumerableSetUpgradeable.AddressSet))
    private guardedAccounts;
  mapping(bytes32 hashedOriginDomain => mapping(address account => RecoveryRequest)) public pendingRecoveryData;
  mapping(bytes32 hashedOriginDomain => mapping(address account => mapping(address guardian => Guardian)))
    public accountGuardianData;

  constructor() {
    _disableInitializers();
  }

  function initialize(WebAuthValidator _webAuthValidator) public initializer {
    webAuthValidator = _webAuthValidator;
  }

  /// @notice Validator initiator for given sso account. This module does not support initialization on creation
  function onInstall(bytes calldata) external {}

  /// @notice Removes all past guardians when this module is disabled in a account
  function onUninstall(bytes calldata data) external {
    bytes32[] memory hashedOriginDomains = abi.decode(data, (bytes32[]));
    for (uint256 j = 0; j < hashedOriginDomains.length; j++) {
      bytes32 hashedOriginDomain = hashedOriginDomains[j];
      address[] memory guardians = accountGuardians[hashedOriginDomain][msg.sender].values();
      for (uint256 i = 0; i < guardians.length; i++) {
        address guardian = guardians[i];

        EnumerableSetUpgradeable.AddressSet storage accounts = guardedAccounts[hashedOriginDomain][guardian];
        bool guardedAccountsRemovalSuccessful = accounts.remove(msg.sender);

        if (!guardedAccountsRemovalSuccessful) {
          revert AccountNotGuardedByAddress(msg.sender, guardian);
        }
        delete accountGuardianData[hashedOriginDomain][msg.sender][guardian];

        bool removalSuccessful = accountGuardians[hashedOriginDomain][msg.sender].remove(guardian);

        if (!removalSuccessful) {
          revert GuardianNotFound(guardian);
        }

        emit GuardianRemoved(msg.sender, hashedOriginDomain, guardian);
      }
    }
  }

  /// @notice The `proposeValidationKey` method handles the initial registration of guardians by:
  ///   1. Taking an external account address and store it as pending guardian
  ///   2. Enable `addValidationKey` to confirm this account
  /// @param hashedOriginDomain Hash of origin domain
  /// @param newGuardian New Guardian's address
  function proposeValidationKey(bytes32 hashedOriginDomain, address newGuardian) external {
    if (msg.sender == newGuardian) revert GuardianCannotBeSelf();

    bool additionSuccessful = accountGuardians[hashedOriginDomain][msg.sender].add(newGuardian);

    if (!additionSuccessful) {
      return;
    }

    accountGuardianData[hashedOriginDomain][msg.sender][newGuardian] = Guardian(
      newGuardian,
      false,
      uint64(block.timestamp)
    );
    emit GuardianProposed(msg.sender, hashedOriginDomain, newGuardian);
  }

  /// @notice This method handles the removal of guardians by:
  ///   1. Accepting an address as input
  ///   2. Removing the account from the list of guardians
  /// @param hashedOriginDomain Hash of origin domain
  /// @param guardianToRemove Guardian's address to remove
  function removeValidationKey(bytes32 hashedOriginDomain, address guardianToRemove) external {
    bool removalSuccessful = accountGuardians[hashedOriginDomain][msg.sender].remove(guardianToRemove);

    if (removalSuccessful) {
      bool wasActiveGuardian = accountGuardianData[hashedOriginDomain][msg.sender][guardianToRemove].isReady;
      delete accountGuardianData[hashedOriginDomain][msg.sender][guardianToRemove];

      if (wasActiveGuardian) {
        EnumerableSetUpgradeable.AddressSet storage accounts = guardedAccounts[hashedOriginDomain][guardianToRemove];
        bool accountsRemovalSuccessful = accounts.remove(msg.sender);

        if (!accountsRemovalSuccessful) {
          revert AccountNotGuardedByAddress(msg.sender, guardianToRemove);
        }
      }
      emit GuardianRemoved(msg.sender, hashedOriginDomain, guardianToRemove);
      return;
    }

    revert GuardianNotFound(guardianToRemove);
  }

  /// @notice This method allows to accept being a guardian of given account
  /// @param hashedOriginDomain Hash of origin domain
  /// @param accountToGuard Address of account which msg.sender is becoming guardian of
  /// @return Flag indicating whether guardian was already valid or not
  function addValidationKey(bytes32 hashedOriginDomain, address accountToGuard) external returns (bool) {
    bool guardianProposed = accountGuardians[hashedOriginDomain][accountToGuard].contains(msg.sender);

    if (guardianProposed) {
      // We return true if the guardian was not confirmed before.
      if (accountGuardianData[hashedOriginDomain][accountToGuard][msg.sender].isReady) return false;

      accountGuardianData[hashedOriginDomain][accountToGuard][msg.sender].isReady = true;
      bool addSuccessful = guardedAccounts[hashedOriginDomain][msg.sender].add(accountToGuard);

      if (!addSuccessful) {
        revert AccountAlreadyGuardedByGuardian(accountToGuard, msg.sender);
      }

      emit GuardianAdded(accountToGuard, hashedOriginDomain, msg.sender);
      return true;
    }

    revert GuardianNotProposed(msg.sender);
  }

  /// @notice This modifier allows execution only by active guardian of account
  /// @param hashedOriginDomain Hash of origin domain
  /// @param account Address of account for which we verify guardian existence
  modifier onlyGuardianOf(bytes32 hashedOriginDomain, address account) {
    bool isGuardian = accountGuardians[hashedOriginDomain][account].contains(msg.sender) &&
      accountGuardianData[hashedOriginDomain][account][msg.sender].isReady;

    if (!isGuardian) revert GuardianNotFound(msg.sender);
    // Continue execution if called by guardian
    _;
  }

  /// @notice This method initializes a recovery process for a given account
  /// @param accountToRecover Address of account for which given recovery is initiated
  /// @param hashedCredentialId Hashed credential ID of the new passkey
  /// @param rawPublicKey Raw public key of the new passkey
  /// @param hashedOriginDomain Hash of origin domain of the new passkey
  function initRecovery(
    address accountToRecover,
    bytes32 hashedCredentialId,
    bytes32[2] memory rawPublicKey,
    bytes32 hashedOriginDomain
  ) external onlyGuardianOf(hashedOriginDomain, accountToRecover) {
    pendingRecoveryData[hashedOriginDomain][accountToRecover] = RecoveryRequest(
      hashedCredentialId,
      rawPublicKey,
      block.timestamp
    );

    emit RecoveryInitiated(accountToRecover, hashedOriginDomain, hashedCredentialId, msg.sender);
  }

  /// @notice This method allows to discard currently pending recovery
  /// @param hashedOriginDomain Hash of origin domain
  function discardRecovery(bytes32 hashedOriginDomain) external {
    emit RecoveryDiscarded(
      msg.sender,
      hashedOriginDomain,
      pendingRecoveryData[hashedOriginDomain][msg.sender].hashedCredentialId
    );
    _discardRecovery(hashedOriginDomain);
  }

  /// @notice This method allows to finish currently pending recovery
  /// @param hashedOriginDomain Hash of origin domain
  function finishRecovery(bytes32 hashedOriginDomain) internal {
    emit RecoveryFinished(
      msg.sender,
      hashedOriginDomain,
      pendingRecoveryData[hashedOriginDomain][msg.sender].hashedCredentialId
    );
    _discardRecovery(hashedOriginDomain);
  }

  /// @notice This method allows to discard currently pending recovery
  /// @param hashedOriginDomain Hash of origin domain
  function _discardRecovery(bytes32 hashedOriginDomain) internal {
    delete pendingRecoveryData[hashedOriginDomain][msg.sender];
  }

  /// @inheritdoc IModuleValidator
  function validateTransaction(bytes32, Transaction calldata transaction) external returns (bool) {
    // Finishing Recovery Process. If the user has a recovery in progress then:
    //   1. The method will check if the transaction is attempting to modify passkeys
    //   2. Verify the new passkey matches the one stored in `initRecovery`
    //   3. Allows anyone to call this method, as the recovery was already verified in `initRecovery`
    //   4. Verifies that the required timelock period has passed since `initRecovery` was called
    //   5. If all the above are true, the recovery is finished
    require(transaction.data.length >= 4, "Only function calls are supported");
    require(transaction.to <= type(uint160).max, "Overflow");
    // Verify the transaction is a call to WebAuthValidator contract
    address target = address(uint160(transaction.to));
    if (target != address(webAuthValidator)) {
      return false;
    }

    // Verify the transaction is a call to `addValidationKey`
    bytes4 selector = bytes4(transaction.data[:4]);
    if (selector != WebAuthValidator.addValidationKey.selector) {
      return false;
    }

    // Verify the current request matches pending one
    bytes calldata transactionData = transaction.data[4:];
    (bytes memory credentialId, bytes32[2] memory rawPublicKey, string memory originDomain) = abi.decode(
      transactionData,
      (bytes, bytes32[2], string)
    );

    bytes32 hashedOriginDomain = keccak256(abi.encodePacked(originDomain));
    RecoveryRequest storage storedData = pendingRecoveryData[hashedOriginDomain][msg.sender];

    bytes32 hashedCredentialIdFromTx = keccak256(credentialId);
    if (hashedCredentialIdFromTx != storedData.hashedCredentialId) {
      return false;
    }

    if (rawPublicKey[0] != storedData.rawPublicKey[0] || rawPublicKey[1] != storedData.rawPublicKey[1]) {
      return false;
    }
    // Verify request is in valid time range
    TimestampAsserterLocator.locate().assertTimestampInRange(
      storedData.timestamp + REQUEST_DELAY_TIME,
      storedData.timestamp + REQUEST_VALIDITY_TIME
    );

    finishRecovery(hashedOriginDomain);
    return true;
  }

  /// @inheritdoc IModuleValidator
  function validateSignature(bytes32, bytes memory) external pure returns (bool) {
    return false;
  }

  /// @inheritdoc IERC165
  function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
    return
      interfaceId == type(IERC165).interfaceId ||
      interfaceId == type(IModuleValidator).interfaceId ||
      interfaceId == type(IModule).interfaceId;
  }

  /// @notice Returns all guardians for an account
  /// @param hashedOriginDomain Hash of origin domain
  /// @param addr Address of account to get guardians for
  /// @return Array of guardians for the account
  function guardiansFor(bytes32 hashedOriginDomain, address addr) public view returns (Guardian[] memory) {
    address[] memory guardians = accountGuardians[hashedOriginDomain][addr].values();
    Guardian[] memory result = new Guardian[](guardians.length);
    for (uint256 i = 0; i < guardians.length; i++) {
      result[i] = accountGuardianData[hashedOriginDomain][addr][guardians[i]];
    }
    return result;
  }

  /// @notice Returns all accounts guarded by a guardian
  /// @param hashedOriginDomain Hash of origin domain
  /// @param guardian Address of guardian to get guarded accounts for
  /// @return Array of accounts guarded by the guardian
  function guardianOf(bytes32 hashedOriginDomain, address guardian) public view returns (address[] memory) {
    return guardedAccounts[hashedOriginDomain][guardian].values();
  }

  /// @notice Returns the pending recovery data for an account and origin domain
  /// @param hashedOriginDomain Hash of the origin domain
  /// @param account Address of the account
  /// @return The full RecoveryRequest struct containing hashedCredentialId, rawPublicKey, and timestamp
  function getPendingRecoveryData(
    bytes32 hashedOriginDomain,
    address account
  ) public view returns (RecoveryRequest memory) {
    return pendingRecoveryData[hashedOriginDomain][account];
  }
}
