// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.23 <0.9.0;

import { UpgradeableBeacon } from '@solady/utils/UpgradeableBeacon.sol';

import { BeaconProxy } from '@oz/proxy/beacon/BeaconProxy.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { BeaconBase } from '../../lib/proxy/BeaconBase.sol';
import { Versioned } from '../../lib/Versioned.sol';
import { HubAsset } from './HubAsset.sol';

contract HubAssetFactory is BeaconBase, Ownable2StepUpgradeable, UUPSUpgradeable, Versioned {
  constructor() {
    _disableInitializers();
  }

  function initialize(address owner_, address initialImpl) external initializer {
    __Ownable2Step_init();
    __Ownable_init(owner_);
    __UUPSUpgradeable_init();
    __BeaconBase_init(new UpgradeableBeacon(address(this), address(initialImpl)));
  }

  function create(address owner_, address supplyManager, string memory name, string memory symbol, uint8 decimals)
    external
    onlyOwner
    returns (address)
  {
    bytes memory args = abi.encodeCall(HubAsset.initialize, (owner_, supplyManager, name, symbol, decimals));
    address instance = address(new BeaconProxy(address(beacon()), args));

    _pushInstance(instance);

    return instance;
  }

  function callBeacon(bytes calldata data) external onlyOwner returns (bytes memory) {
    return _callBeacon(data);
  }

  function _authorizeUpgrade(address) internal override onlyOwner { }
}
