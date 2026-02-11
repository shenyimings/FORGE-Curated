// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

library SsoStorage {
  // keccak256('zksync-sso.contracts.SsoStorage') - 1
  bytes32 private constant SSO_STORAGE_SLOT = 0x996e49e905bb2c30d677a2ad554e4b964a479b19a0509deafafca5126b88ba23;

  struct Layout {
    // Ownership Data
    EnumerableSet.AddressSet k1Owners;
    // Validation
    EnumerableSet.AddressSet moduleValidators;
    // Hooks
    EnumerableSet.AddressSet validationHooks;
    EnumerableSet.AddressSet executionHooks;
    // Storage slots reserved for future upgrades
    uint256[256] __RESERVED;
  }

  function layout() internal pure returns (Layout storage l) {
    bytes32 slot = SSO_STORAGE_SLOT;
    assembly {
      l.slot := slot
    }
  }

  function validators() internal view returns (EnumerableSet.AddressSet storage) {
    return layout().moduleValidators;
  }

  function validationHooks() internal view returns (EnumerableSet.AddressSet storage) {
    return layout().validationHooks;
  }

  function executionHooks() internal view returns (EnumerableSet.AddressSet storage) {
    return layout().executionHooks;
  }
}
