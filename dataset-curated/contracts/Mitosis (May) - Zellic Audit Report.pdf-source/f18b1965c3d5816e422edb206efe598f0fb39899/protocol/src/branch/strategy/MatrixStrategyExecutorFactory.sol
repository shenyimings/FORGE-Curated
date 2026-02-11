// SPDX-License-Identifier: MIT
pragma solidity >=0.8.23 <0.9.0;

import { BeaconProxy } from '@oz/proxy/beacon/BeaconProxy.sol';
import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { UpgradeableBeacon } from '@solady/utils/UpgradeableBeacon.sol';

import { IMitosisVault } from '../../interfaces/branch/IMitosisVault.sol';
import { BeaconBase } from '../../lib/proxy/BeaconBase.sol';
import { MatrixStrategyExecutor } from './MatrixStrategyExecutor.sol';

contract MatrixStrategyExecutorFactory is BeaconBase, Ownable2StepUpgradeable, UUPSUpgradeable {
  constructor() {
    _disableInitializers();
  }

  function initialize(address owner_, address initialImpl) external initializer {
    __Ownable2Step_init();
    __Ownable_init(owner_);
    __BeaconBase_init(new UpgradeableBeacon(address(this), address(initialImpl)));
    __UUPSUpgradeable_init();
  }

  function create(IMitosisVault vault_, IERC20 asset_, address hubMatrixVault_, address owner_)
    external
    onlyOwner
    returns (address)
  {
    bytes memory args = abi.encodeCall(MatrixStrategyExecutor.initialize, (vault_, asset_, hubMatrixVault_, owner_));
    address instance = address(new BeaconProxy(address(beacon()), args));

    _pushInstance(instance);

    return instance;
  }

  function callBeacon(bytes calldata data) external onlyOwner returns (bytes memory) {
    return _callBeacon(data);
  }

  function _authorizeUpgrade(address) internal override onlyOwner { }
}
