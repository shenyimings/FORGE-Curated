// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/// @title Errors
/// @notice Errors used by ZKsync SSO and its components
/// @author getclave.io
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
  error NOT_FROM_HOOK(address notHook);
  error NOT_FROM_SELF(address notSelf);

  // Batch caller errors
  error CALL_FAILED(uint256 batchCallIndex);
  error MSG_VALUE_MISMATCH(uint256 actualValue, uint256 expectedValue);
}
