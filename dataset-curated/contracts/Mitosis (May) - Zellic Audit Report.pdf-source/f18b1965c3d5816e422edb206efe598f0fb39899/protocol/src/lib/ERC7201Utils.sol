// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library ERC7201Utils {
  function storageSlot(string memory namespace) internal pure returns (bytes32 slot) {
    /// @solidity memory-safe-assembly
    assembly {
      mstore(0x00, sub(keccak256(add(namespace, 0x20), mload(namespace)), 1))
      slot := and(keccak256(0x00, 0x20), not(0xff))
    }
  }
}
