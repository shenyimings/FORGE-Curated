// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenV1} from "src/ZkTokenV1.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

/// @dev This is a "fake" version 2 of the ZkToken, used only for testing that an upgrade fails when the
/// clock mode changes.
/// @custom:oz-upgrades-from ZkTokenV1
contract ZkTokenFakeV2ClockChange is ZkTokenV1 {
  function initializeFakeV2(uint256 _initialValue) public reinitializer(2) {}

  function clock() public view virtual override returns (uint48) {
    return SafeCastUpgradeable.toUint48(block.number);
  }
}
