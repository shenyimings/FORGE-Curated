// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/// @title Errors
/// @notice Errors used by ZKsync SSO and its components
/// @author Initial version by getclave.io, modified by Matter Labs
library Errors {
  // Account errors
  error INSUFFICIENT_FUNDS(uint256 required, uint256 available);
  error FEE_PAYMENT_FAILED();
  error METHOD_NOT_IMPLEMENTED();

  // ERC165 module errors
  error VALIDATOR_ERC165_FAIL(address validator);
  error HOOK_ERC165_FAIL(address hookAddress, bool isValidation);

  // Auth errors
  error NOT_FROM_BOOTLOADER(address notBootloader);
  error NOT_FROM_SELF(address notSelf);
  error NOT_FROM_INITIALIZED_ACCOUNT(address notInitialized);

  // Manager errors
  error OWNER_ALREADY_EXISTS(address owner);
  error OWNER_NOT_FOUND(address owner);
  error VALIDATOR_ALREADY_EXISTS(address validator);
  error VALIDATOR_NOT_FOUND(address validator);
  error HOOK_ALREADY_EXISTS(address hook, bool isValidation);
  error HOOK_NOT_FOUND(address hook, bool isValidation);

  // Sessions errors
  error UNINSTALL_WITH_OPEN_SESSIONS(uint256 openSessions);
  error SESSION_ZERO_SIGNER();
  error SESSION_INVALID_SIGNER(address recovered, address expected);
  error SESSION_ALREADY_EXISTS(bytes32 sessionHash);
  error SESSION_UNLIMITED_FEES();
  error SESSION_EXPIRES_TOO_SOON(uint256 expiresAt);
  error SESSION_NOT_ACTIVE();
  error SESSION_LIFETIME_USAGE_EXCEEDED(uint256 lifetimeUsage, uint256 maxUsage);
  error SESSION_ALLOWANCE_EXCEEDED(uint256 allowance, uint256 maxAllowance, uint64 period);
  error SESSION_INVALID_DATA_LENGTH(uint256 actualLength, uint256 expectedMinimumLength);
  error SESSION_CONDITION_FAILED(bytes32 param, bytes32 refValue, uint8 condition);
  error SESSION_CALL_POLICY_VIOLATED(address target, bytes4 selector);
  error SESSION_TRANSFER_POLICY_VIOLATED(address target);
  error SESSION_MAX_VALUE_EXCEEDED(uint256 usedValue, uint256 maxValuePerUse);

  // Misc
  error BATCH_MSG_VALUE_MISMATCH(uint256 actualValue, uint256 expectedValue);
  error WEBAUTHN_KEY_EXISTS();
  error ACCOUNT_ALREADY_EXISTS(address account);
  error NO_TIMESTAMP_ASSERTER(uint256 chainId);
  error ADDRESS_CAST_OVERFLOW(uint256 value);
  error INVALID_PAYMASTER_INPUT(bytes input);
}
