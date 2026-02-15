// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.23 <0.9.0;

import { IBeacon } from '@oz/proxy/beacon/IBeacon.sol';
import { ERC1967Utils } from '@oz/proxy/ERC1967/ERC1967Utils.sol';
import { Proxy } from '@oz/proxy/Proxy.sol';

/**
 * @dev ownable Interface of the BeaconProxy.
 */
interface IBeaconProxy {
  error IBeaconProxy_BeaconNotOwned();
  error IBeaconProxy_InvalidFunctionCall();

  function upgradeBeaconToAndCall(address newBeacon, bytes memory data) external;
}

/**
 * @dev BeaconProxy is a proxy contract that is upgradeable using an EIP1967 beacon.
 * To make a fit to our cases like using various vault implementations, it is modified to migrate beacon contract to a new implementation.
 */
contract BeaconProxy is Proxy {
  /**
   * @dev Initializes the proxy with `beacon`.
   *
   * If `data` is nonempty, it's used as data in a delegate call to the implementation returned by the beacon. This
   * will typically be an encoded function call, and allows initializing the storage of the proxy like a Solidity
   * constructor.
   *
   * Requirements:
   *
   * - `beacon` must be a contract with the interface {IBeacon}.
   * - If `data` is empty, `msg.value` must be zero.
   */
  constructor(address beacon, bytes memory data) payable {
    ERC1967Utils.upgradeBeaconToAndCall(beacon, data);
    _getBeaconOwner(); // check if the beacon is owned
  }

  /**
   * @dev Returns the current implementation address of the associated beacon.
   */
  function _implementation() internal view virtual override returns (address) {
    return IBeacon(_getBeacon()).implementation();
  }

  /**
   * @dev Returns the beacon.
   */
  function _getBeacon() internal view virtual returns (address) {
    return ERC1967Utils.getBeacon();
  }

  function _getBeaconOwner() internal view returns (address) {
    address beacon = _getBeacon();
    (bool ok, bytes memory ret) = beacon.staticcall(abi.encodeWithSignature('owner()'));
    require(ok, IBeaconProxy.IBeaconProxy_BeaconNotOwned());

    address owner = abi.decode(ret, (address));
    return owner;
  }

  /**
   * @dev Change the beacon and trigger a setup call if data is nonempty.
   */
  function _dispatchUpgradeBeaconToAndCall() internal {
    (address newBeacon, bytes memory data) = abi.decode(msg.data[4:], (address, bytes));
    ERC1967Utils.upgradeBeaconToAndCall(newBeacon, data);
  }

  /**
   * @dev If caller is the admin process the call internally, otherwise transparently fallback to the proxy behavior.
   */
  function _fallback() internal virtual override {
    if (msg.sender == _getBeaconOwner()) {
      require(msg.sig == IBeaconProxy.upgradeBeaconToAndCall.selector, IBeaconProxy.IBeaconProxy_InvalidFunctionCall());

      _dispatchUpgradeBeaconToAndCall();
    } else {
      super._fallback();
    }
  }
}
