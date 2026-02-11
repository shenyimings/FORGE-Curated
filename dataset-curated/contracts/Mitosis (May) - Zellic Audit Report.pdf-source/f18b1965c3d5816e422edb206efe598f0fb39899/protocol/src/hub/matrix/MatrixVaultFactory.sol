// SPDX-License-Identifier: MIT
pragma solidity >=0.8.23 <0.9.0;

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { UpgradeableBeacon } from '@solady/utils/UpgradeableBeacon.sol';

import { IMatrixVaultFactory } from '../../interfaces/hub/matrix/IMatrixVaultFactory.sol';
import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { BeaconProxy, IBeaconProxy } from '../../lib/proxy/BeaconProxy.sol';
import { MatrixVaultBasic } from './MatrixVaultBasic.sol';
import { MatrixVaultCapped } from './MatrixVaultCapped.sol';

contract MatrixVaultFactory is IMatrixVaultFactory, Ownable2StepUpgradeable, UUPSUpgradeable {
  using ERC7201Utils for string;

  struct BeaconInfo {
    bool initialized;
    address beacon;
    address[] instances;
    mapping(address => uint256) instanceIndex;
  }

  struct Storage {
    mapping(address instance => bool) isInstance;
    mapping(VaultType vaultType => BeaconInfo) infos;
  }

  string private constant _NAMESPACE = 'mitosis.storage.MatrixVaultFactory';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorage() private view returns (Storage storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(address owner_) external initializer {
    __Ownable2Step_init();
    __Ownable_init(owner_);
    __UUPSUpgradeable_init();
  }

  function beacon(VaultType t) external view returns (address) {
    return address(_getStorage().infos[t].beacon);
  }

  function isInstance(address instance) external view returns (bool) {
    return _getStorage().isInstance[instance];
  }

  function isInstance(VaultType t, address instance) external view returns (bool) {
    return _isInstance(_getStorage(), t, instance);
  }

  function instances(VaultType t, uint256 index) external view returns (address) {
    return _getStorage().infos[t].instances[index];
  }

  function instances(VaultType t, uint256[] memory indexes) external view returns (address[] memory) {
    BeaconInfo storage info = _getStorage().infos[t];

    address[] memory result = new address[](indexes.length);
    for (uint256 i = 0; i < indexes.length; i++) {
      result[i] = info.instances[indexes[i]];
    }
    return result;
  }

  function instancesLength(VaultType t) external view returns (uint256) {
    return _getStorage().infos[t].instances.length;
  }

  function initVaultType(VaultType vaultType, address initialImpl) external onlyOwner {
    require(vaultType != VaultType.Unset, IMatrixVaultFactory__InvalidVaultType());

    Storage storage $ = _getStorage();
    require(!$.infos[vaultType].initialized, IMatrixVaultFactory__AlreadyInitialized());

    $.infos[vaultType].initialized = true;
    $.infos[vaultType].beacon = address(new UpgradeableBeacon(address(this), initialImpl));

    emit VaultTypeInitialized(vaultType, address($.infos[vaultType].beacon));
  }

  function vaultTypeInitialized(VaultType t) external view returns (bool) {
    return _getStorage().infos[t].initialized;
  }

  /**
   * @dev used to migrate the beacon implementation - see `UpgradeableBeacon.upgradeTo`
   */
  function callBeacon(VaultType t, bytes calldata data) external onlyOwner returns (bytes memory) {
    Storage storage $ = _getStorage();
    require($.infos[t].initialized, IMatrixVaultFactory__NotInitialized());

    (bool success, bytes memory result) = address($.infos[t].beacon).call(data);
    require(success, IMatrixVaultFactory__CallBeaconFailed(result));

    emit BeaconCalled(_msgSender(), t, data, success, result);

    return result;
  }

  function create(VaultType t, bytes calldata args) external onlyOwner returns (address) {
    Storage storage $ = _getStorage();
    require($.infos[t].initialized, IMatrixVaultFactory__NotInitialized());

    address instance;

    if (t == VaultType.Basic) instance = _create($, abi.decode(args, (BasicVaultInitArgs)));
    else if (t == VaultType.Capped) instance = _create($, abi.decode(args, (CappedVaultInitArgs)));
    else revert IMatrixVaultFactory__InvalidVaultType();

    $.isInstance[instance] = true;

    emit MatrixVaultCreated(t, instance, args);
    return instance;
  }

  function migrate(VaultType from, VaultType to, address instance, bytes calldata data) external onlyOwner {
    Storage storage $ = _getStorage();
    require($.infos[from].initialized, IMatrixVaultFactory__NotInitialized());
    require($.infos[to].initialized, IMatrixVaultFactory__NotInitialized());
    require(_isInstance($, from, instance), IMatrixVaultFactory__NotAnInstance());

    // Remove instance from 'from' type's tracking
    uint256 index = $.infos[from].instanceIndex[instance];
    if ($.infos[from].instances.length > 1) {
      // Move last element to the removed index and update its index mapping
      address last = $.infos[from].instances[$.infos[from].instances.length - 1];
      $.infos[from].instances[index] = last;
      $.infos[from].instanceIndex[last] = index;
    }
    $.infos[from].instances.pop();
    delete $.infos[from].instanceIndex[instance]; // Use delete instead of setting to 0

    $.infos[to].instances.push(instance);
    IBeaconProxy(instance).upgradeBeaconToAndCall($.infos[to].beacon, data);

    emit MatrixVaultMigrated(from, to, instance);
  }

  function _isInstance(Storage storage $, VaultType t, address instance) private view returns (bool) {
    if (!$.infos[t].initialized) return false;
    if ($.infos[t].instances.length == 0) return false;
    uint256 index = $.infos[t].instanceIndex[instance];
    return !(index == 0 && $.infos[t].instances[index] != instance);
  }

  function _create(Storage storage $, BasicVaultInitArgs memory args) private returns (address) {
    BeaconInfo storage info = $.infos[VaultType.Basic];

    bytes memory data = abi.encodeCall(
      MatrixVaultBasic.initialize, //
      (args.owner, args.assetManager, args.asset, args.name, args.symbol)
    );
    address instance = address(new BeaconProxy(address(info.beacon), data));

    info.instances.push(instance);
    info.instanceIndex[instance] = info.instances.length - 1;

    return instance;
  }

  function _create(Storage storage $, CappedVaultInitArgs memory args) private returns (address) {
    BeaconInfo storage info = $.infos[VaultType.Capped];

    bytes memory data = abi.encodeCall(
      MatrixVaultCapped.initialize, //
      (args.owner, args.assetManager, args.asset, args.name, args.symbol)
    );
    address instance = address(new BeaconProxy(address(info.beacon), data));

    info.instances.push(instance);
    info.instanceIndex[instance] = info.instances.length - 1;

    return instance;
  }

  function _authorizeUpgrade(address) internal override onlyOwner { }
}
