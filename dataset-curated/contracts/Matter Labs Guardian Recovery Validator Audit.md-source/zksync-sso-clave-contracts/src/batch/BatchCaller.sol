// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { EfficientCall } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/EfficientCall.sol";
import { Utils } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/Utils.sol";
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
  /// @notice Emits information about a failed call.
  /// @param index The index of the failed call in the batch.
  /// @param revertData The return data of the failed call.
  event BatchCallFailure(uint256 indexed index, bytes revertData);

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
      uint32 gas = Utils.safeCastToU32(gasleft());

      if (_calls[i].target == address(DEPLOYER_SYSTEM_CONTRACT)) {
        bytes4 selector = bytes4(_calls[i].callData[:4]);
        // Check that called function is the deployment method,
        // the other deployer methods are not supposed to be called from the account.
        // NOTE: DefaultAccount has the same behavior.
        bool isSystemCall = selector == DEPLOYER_SYSTEM_CONTRACT.create.selector ||
          selector == DEPLOYER_SYSTEM_CONTRACT.create2.selector ||
          selector == DEPLOYER_SYSTEM_CONTRACT.createAccount.selector ||
          selector == DEPLOYER_SYSTEM_CONTRACT.create2Account.selector;
        // Note, that the deployer contract can only be called with a "isSystemCall" flag.
        success = EfficientCall.rawCall({
          _gas: gas,
          _address: _calls[i].target,
          _value: _calls[i].value,
          _data: _calls[i].callData,
          _isSystem: isSystemCall
        });
      } else {
        success = EfficientCall.rawCall(gas, _calls[i].target, _calls[i].value, _calls[i].callData, false);
      }

      if (!success) {
        emit BatchCallFailure(i, getReturnData());
        if (!_calls[i].allowFailure) {
          EfficientCall.propagateRevert();
        }
      }
    }

    if (totalValue != msg.value) {
      revert Errors.BATCH_MSG_VALUE_MISMATCH(msg.value, totalValue);
    }
  }

  function getReturnData() private pure returns (bytes memory data) {
    assembly {
      let size := returndatasize()
      data := mload(0x40)
      mstore(data, size)
      returndatacopy(add(data, 0x20), 0, size)
    }
  }
}
