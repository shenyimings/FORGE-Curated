// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { EfficientCall } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/EfficientCall.sol";

/// @title EfficientProxy
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice This contract implement ultra-efficient way for executing delegate calls. It is compatible with
/// OpenZeppelin proxy implementations.
abstract contract EfficientProxy {
  function _delegate(address implementation) internal virtual {
    // Use the EfficientCall library to forward calldata to the implementation contract,
    // instead of copying it from calldata to memory.
    bytes memory data = EfficientCall.delegateCall(gasleft(), implementation, msg.data);
    assembly {
      return(add(data, 0x20), mload(data))
    }
  }
}
