// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/// @title SsoBeacon
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @dev This beacon stores the implementation address of SsoAccount contract,
/// which every SSO account delegates to. This beacon's address is immutably stored
/// in AAFactory contract, as it is required for deploying new SSO accounts.
contract SsoBeacon is UpgradeableBeacon {
  constructor(address _implementation) UpgradeableBeacon(_implementation) {}
}
