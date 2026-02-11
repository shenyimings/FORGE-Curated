// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { SystemContractsCaller } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/SystemContractsCaller.sol";
import { EfficientCall } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/EfficientCall.sol";
import { DEPLOYER_SYSTEM_CONTRACT } from "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import { Errors } from "../libraries/Errors.sol";
import { SelfAuth } from "../auth/SelfAuth.sol";

/// @dev Represents an external call data.
/// @param target The address to which the call will be made.
/// @param allowFailure Flag that represents whether to revert the whole batch if the call fails.
/// @param value The amount of Ether (in wei) to be sent along with the call.
/// @param callData The calldata to be executed on the `target` address.
struct Call {
  address target;
  bool allowFailure;
  uint256 value;
  bytes callData;
}

/// @title SSO Account
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice Make multiple calls from Account in a single transaction.
/// @notice The implementation is inspired by Clave wallet.
abstract contract BatchCaller is SelfAuth {
  /// @notice Make multiple calls, ensure success if required.
  /// @dev The total Ether sent across all calls must be equal to `msg.value` to maintain the invariant
  /// that `msg.value` + `tx.fee` is the maximum amount of Ether that can be spent on the transaction.
  /// @param _calls Array of Call structs, each representing an individual external call to be made.
  function batchCall(Call[] calldata _calls) external payable onlySelf {
    uint256 totalValue;
    uint256 len = _calls.length;
    for (uint256 i = 0; i < len; ++i) {
      totalValue += _calls[i].value;
      bool success;
      if (_calls[i].target == address(DEPLOYER_SYSTEM_CONTRACT)) {
        // Note, that the deployer contract can only be called with a "systemCall" flag.
        success = SystemContractsCaller.systemCall(
          uint32(gasleft()),
          _calls[i].target,
          _calls[i].value,
          _calls[i].callData
        );
      } else {
        success = EfficientCall.rawCall(gasleft(), _calls[i].target, _calls[i].value, _calls[i].callData, false);
      }

      if (!_calls[i].allowFailure && !success) {
        revert Errors.CALL_FAILED(i);
      }
    }

    if (totalValue != msg.value) {
      revert Errors.MSG_VALUE_MISMATCH(msg.value, totalValue);
    }
  }
}
