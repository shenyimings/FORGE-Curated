// SPDX-License-Identifier: MIT
pragma solidity >=0.8.23 <0.9.0;

import { ContextUpgradeable } from '@ozu/utils/ContextUpgradeable.sol';

import { UpgradeableBeacon } from '@solady/utils/UpgradeableBeacon.sol';

import { IBeaconBase } from '../../interfaces/lib/proxy/IBeaconBase.sol';
import { ERC7201Utils } from '../ERC7201Utils.sol';
import { StdError } from '../StdError.sol';

abstract contract BeaconBase is IBeaconBase, ContextUpgradeable {
  using ERC7201Utils for string;

  struct BeaconBaseStorage {
    UpgradeableBeacon beacon;
    address[] instances;
    mapping(address => uint256) instanceIndex;
  }

  string private constant _NAMESPACE = 'mitosis.storage.BeaconBase';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getBeaconBaseStorage() private view returns (BeaconBaseStorage storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  function __BeaconBase_init(UpgradeableBeacon beacon_) internal {
    require(address(beacon_).code.length > 0, StdError.InvalidAddress('beacon'));

    __Context_init();

    BeaconBaseStorage storage $ = _getBeaconBaseStorage();

    $.beacon = beacon_;
  }

  function beacon() public view returns (address) {
    return address(_getBeaconBaseStorage().beacon);
  }

  function isInstance(address instance) external view returns (bool) {
    BeaconBaseStorage storage $ = _getBeaconBaseStorage();
    if ($.instances.length == 0) return false;

    uint256 index = $.instanceIndex[instance];
    if (index == 0 && $.instances[0] != instance) return false;

    return true;
  }

  function instances(uint256 index) external view returns (address) {
    BeaconBaseStorage storage $ = _getBeaconBaseStorage();

    uint256 instancesLen = $.instances.length;
    require(index < instancesLen, IBeaconBase__IndexOutOfBounds(instancesLen, index));

    return $.instances[index];
  }

  function instances(uint256[] calldata indexes) external view returns (address[] memory) {
    BeaconBaseStorage storage $ = _getBeaconBaseStorage();

    address[] memory result = new address[](indexes.length);
    uint256 instancesLen = $.instances.length;
    uint256 indexesLen = indexes.length;
    for (uint256 i = 0; i < indexesLen; i++) {
      uint256 index = indexes[i];
      require(index < instancesLen, IBeaconBase__IndexOutOfBounds(instancesLen, index));
      result[i] = $.instances[index];
    }
    return result;
  }

  function instancesLength() external view returns (uint256) {
    return _getBeaconBaseStorage().instances.length;
  }

  function _callBeacon(bytes calldata data) internal returns (bytes memory) {
    (bool success, bytes memory result) = address(beacon()).call(data);
    require(success, IBeaconBase__BeaconCallFailed(result));

    emit BeaconExecuted(_msgSender(), data, success, result);

    return result;
  }

  function _pushInstance(address instance) internal {
    BeaconBaseStorage storage $ = _getBeaconBaseStorage();
    $.instances.push(instance);
    $.instanceIndex[instance] = $.instances.length - 1;

    emit InstanceAdded(instance);
  }
}
