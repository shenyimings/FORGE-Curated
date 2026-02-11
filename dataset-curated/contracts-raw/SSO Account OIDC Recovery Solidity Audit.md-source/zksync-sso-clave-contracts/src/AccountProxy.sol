// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";
import { EfficientProxy } from "./EfficientProxy.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/// @title AccountProxy
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice This contract is modification of OpenZeppelin `BeaconProxy` with optimisation for
/// cheap delegate calls on ZKsync.
contract AccountProxy is BeaconProxy, EfficientProxy {
  constructor(address beacon) BeaconProxy(beacon, bytes("")) {}

  function _delegate(address implementation) internal override(EfficientProxy, Proxy) {
    EfficientProxy._delegate(implementation);
  }
}
