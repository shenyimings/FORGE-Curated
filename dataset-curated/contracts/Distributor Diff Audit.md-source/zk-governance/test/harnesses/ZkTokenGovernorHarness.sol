// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenGovernor} from "src/ZkTokenGovernor.sol";

contract ZkTokenGovernorHarness is ZkTokenGovernor {
  constructor(ConstructorParams memory params) ZkTokenGovernor(params) {}

  function exposed_setIsGuardianPropose(bool _isProposeGuarded) external {
    _setIsProposeGuarded(_isProposeGuarded);
  }
}
