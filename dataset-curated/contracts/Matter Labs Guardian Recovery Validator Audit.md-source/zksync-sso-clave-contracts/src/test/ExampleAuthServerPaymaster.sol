// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IPaymaster, ExecutionResult, PAYMASTER_VALIDATION_SUCCESS_MAGIC } from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymaster.sol";
import { IPaymasterFlow } from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymasterFlow.sol";
import { TransactionHelper, Transaction } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";

import { BOOTLOADER_FORMAL_ADDRESS } from "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { AAFactory } from "../AAFactory.sol";
import { SessionKeyValidator } from "../validators/SessionKeyValidator.sol";
import { GuardianRecoveryValidator } from "../validators/GuardianRecoveryValidator.sol";
import { WebAuthValidator } from "../validators/WebAuthValidator.sol";

/// @author Matter Labs
/// @notice This contract does not include any validations other than using the paymaster general flow.
contract ExampleAuthServerPaymaster is IPaymaster, Ownable {
  address public immutable AA_FACTORY_CONTRACT_ADDRESS;
  address public immutable SESSION_KEY_VALIDATOR_CONTRACT_ADDRESS;
  address public immutable ACCOUNT_RECOVERY_VALIDATOR_CONTRACT_ADDRESS;
  address public immutable WEB_AUTH_VALIDATOR_CONTRACT_ADDRESS;
  bytes4 constant DEPLOY_ACCOUNT_SELECTOR = AAFactory.deployProxySsoAccount.selector;
  bytes4 constant SESSION_CREATE_SELECTOR = SessionKeyValidator.createSession.selector;
  bytes4 constant SESSION_REVOKE_KEY_SELECTOR = SessionKeyValidator.revokeKey.selector;
  bytes4 constant SESSION_REVOKE_KEYS_SELECTOR = SessionKeyValidator.revokeKeys.selector;
  bytes4 constant GUARDIAN_RECOVERY_ADD_KEY_SELECTOR = GuardianRecoveryValidator.addValidationKey.selector;
  bytes4 constant GUARDIAN_RECOVERY_PROPOSE_KEY_SELECTOR = GuardianRecoveryValidator.proposeValidationKey.selector;
  bytes4 constant GUARDIAN_RECOVERY_DISCARD_RECOVERY_SELECTOR = GuardianRecoveryValidator.discardRecovery.selector;
  bytes4 constant GUARDIAN_RECOVERY_REMOVE_KEY_SELECTOR = GuardianRecoveryValidator.removeValidationKey.selector;
  bytes4 constant GUARDIAN_RECOVERY_INIT_RECOVERY_SELECTOR = GuardianRecoveryValidator.initRecovery.selector;
  bytes4 constant WEB_AUTH_VALIDATOR_REMOVE_KEY_SELECTOR = WebAuthValidator.removeValidationKey.selector;
  bytes4 constant WEB_AUTH_VALIDATOR_ADD_KEY_SELECTOR = WebAuthValidator.addValidationKey.selector;

  modifier onlyBootloader() {
    require(msg.sender == BOOTLOADER_FORMAL_ADDRESS, "Only bootloader can call this method");
    // Continue execution if called from the bootloader.
    _;
  }

  constructor(
    address aaFactoryAddress,
    address sessionKeyValidatorAddress,
    address accountRecoveryValidatorAddress,
    address webAuthValidatorAddress
  ) {
    AA_FACTORY_CONTRACT_ADDRESS = aaFactoryAddress;
    SESSION_KEY_VALIDATOR_CONTRACT_ADDRESS = sessionKeyValidatorAddress;
    ACCOUNT_RECOVERY_VALIDATOR_CONTRACT_ADDRESS = accountRecoveryValidatorAddress;
    WEB_AUTH_VALIDATOR_CONTRACT_ADDRESS = webAuthValidatorAddress;
  }

  function validateAndPayForPaymasterTransaction(
    bytes32,
    bytes32,
    Transaction calldata _transaction
  ) external payable onlyBootloader returns (bytes4 magic, bytes memory) {
    // By default we consider the transaction as accepted.
    magic = PAYMASTER_VALIDATION_SUCCESS_MAGIC;
    require(_transaction.paymasterInput.length >= 4, "The standard paymaster input must be at least 4 bytes long");

    // Ensure the transaction is calling one of our allowed contracts
    address to = address(uint160(_transaction.to));
    require(
      to == AA_FACTORY_CONTRACT_ADDRESS ||
        to == SESSION_KEY_VALIDATOR_CONTRACT_ADDRESS ||
        to == ACCOUNT_RECOVERY_VALIDATOR_CONTRACT_ADDRESS ||
        to == WEB_AUTH_VALIDATOR_CONTRACT_ADDRESS,
      "Unsupported contract address"
    );

    // Ensure the transaction is calling either the deployProxySsoAccount or createSession functions
    require(_transaction.data.length >= 4, "Transaction data is too short");
    bytes4 methodSelector = bytes4(_transaction.data[0:4]);
    if (to == AA_FACTORY_CONTRACT_ADDRESS) {
      require(methodSelector == DEPLOY_ACCOUNT_SELECTOR, "Unsupported method");
    }
    if (to == SESSION_KEY_VALIDATOR_CONTRACT_ADDRESS) {
      require(
        methodSelector == SESSION_CREATE_SELECTOR ||
          methodSelector == SESSION_REVOKE_KEY_SELECTOR ||
          methodSelector == SESSION_REVOKE_KEYS_SELECTOR,
        "Unsupported method"
      );
    }

    if (to == ACCOUNT_RECOVERY_VALIDATOR_CONTRACT_ADDRESS) {
      require(
        methodSelector == GUARDIAN_RECOVERY_ADD_KEY_SELECTOR ||
          methodSelector == GUARDIAN_RECOVERY_PROPOSE_KEY_SELECTOR ||
          methodSelector == GUARDIAN_RECOVERY_DISCARD_RECOVERY_SELECTOR ||
          methodSelector == GUARDIAN_RECOVERY_REMOVE_KEY_SELECTOR ||
          methodSelector == GUARDIAN_RECOVERY_INIT_RECOVERY_SELECTOR,
        "Unsupported method"
      );
    }

    if (to == WEB_AUTH_VALIDATOR_CONTRACT_ADDRESS) {
      require(
        methodSelector == WEB_AUTH_VALIDATOR_ADD_KEY_SELECTOR ||
          methodSelector == WEB_AUTH_VALIDATOR_REMOVE_KEY_SELECTOR,
        "Unsupported method"
      );
    }

    bytes4 paymasterInputSelector = bytes4(_transaction.paymasterInput[0:4]);
    require(paymasterInputSelector == IPaymasterFlow.general.selector, "Unsupported paymaster flow");

    // Note, that while the minimal amount of ETH needed is tx.gasPrice * tx.gasLimit,
    // neither paymaster nor account are allowed to access this context variable.
    uint256 requiredETH = _transaction.gasLimit * _transaction.maxFeePerGas;

    // The bootloader never returns any data, so it can safely be ignored here.
    (bool success, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{ value: requiredETH }("");
    require(success, "Failed to transfer tx fee to the Bootloader. Paymaster balance might not be enough.");
  }

  function postTransaction(
    bytes calldata _context,
    Transaction calldata _transaction,
    bytes32,
    bytes32,
    ExecutionResult _txResult,
    uint256 _maxRefundedGas
  ) external payable override onlyBootloader {}

  function withdraw(address payable _to) external onlyOwner {
    uint256 balance = address(this).balance;
    (bool success, ) = _to.call{ value: balance }("");
    require(success, "Failed to withdraw funds from paymaster.");
  }

  receive() external payable {}
}
