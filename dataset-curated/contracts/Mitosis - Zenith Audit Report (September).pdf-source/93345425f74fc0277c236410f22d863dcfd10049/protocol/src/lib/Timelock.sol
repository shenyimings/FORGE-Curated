// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { AccessControlUpgradeable } from '@ozu/access/AccessControlUpgradeable.sol';
import { AccessControlEnumerableUpgradeable } from '@ozu/access/extensions/AccessControlEnumerableUpgradeable.sol';
import { TimelockControllerUpgradeable } from '@ozu/governance/TimelockControllerUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { Versioned } from './Versioned.sol';

contract Timelock is TimelockControllerUpgradeable, AccessControlEnumerableUpgradeable, UUPSUpgradeable, Versioned {
  constructor() {
    _disableInitializers();
  }

  function initialize(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
    public
    override
    initializer
  {
    __UUPSUpgradeable_init();
    __TimelockController_init(minDelay, proposers, executors, admin);
    __AccessControlEnumerable_init();
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override(TimelockControllerUpgradeable, AccessControlEnumerableUpgradeable)
    returns (bool)
  {
    return TimelockControllerUpgradeable.supportsInterface(interfaceId)
      || AccessControlEnumerableUpgradeable.supportsInterface(interfaceId);
  }

  function _grantRole(bytes32 role, address account)
    internal
    override(AccessControlEnumerableUpgradeable, AccessControlUpgradeable)
    returns (bool)
  {
    return AccessControlEnumerableUpgradeable._grantRole(role, account);
  }

  function _revokeRole(bytes32 role, address account)
    internal
    override(AccessControlEnumerableUpgradeable, AccessControlUpgradeable)
    returns (bool)
  {
    return AccessControlEnumerableUpgradeable._revokeRole(role, account);
  }

  function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }
}
