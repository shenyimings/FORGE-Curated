// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenV1} from "src/ZkTokenV1.sol";

/// @dev This is a "fake" version 2 of the ZkToken, used only for testing that the upgrade functionality is
/// behaving as expected.
/// @custom:oz-upgrades-from ZkTokenV1
contract ZkTokenFakeV2 is ZkTokenV1 {
  event FakeStateVarSet(uint256 oldValue, uint256 newValue);

  uint256 public fakeStateVar;

  function initializeFakeV2(uint256 _initialValue) public reinitializer(2) {
    fakeStateVar = _initialValue;
    emit FakeStateVarSet(0, _initialValue);
  }

  function setFakeStateVar(uint256 _newValue) public onlyRole(MINTER_ROLE) {
    emit FakeStateVarSet(fakeStateVar, _newValue);
    fakeStateVar = _newValue;
  }
}
