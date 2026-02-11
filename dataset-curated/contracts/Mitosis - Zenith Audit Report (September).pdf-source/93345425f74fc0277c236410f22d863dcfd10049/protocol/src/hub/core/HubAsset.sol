// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';

import { ERC20 } from '@solady/tokens/ERC20.sol';

import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { StdError } from '../../lib/StdError.sol';
import { Versioned } from '../../lib/Versioned.sol';
import { HubAssetStorageV1 } from './HubAssetStorageV1.sol';

contract HubAsset is Ownable2StepUpgradeable, ERC20, HubAssetStorageV1, Versioned {
  event SupplyManagerUpdated(address indexed previousSupplyManager, address indexed newSupplyManager);

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address owner_,
    address supplyManager_,
    string memory name_,
    string memory symbol_,
    uint8 decimals_
  ) external initializer {
    __Ownable2Step_init();
    __Ownable_init(owner_);

    StorageV1 storage $ = _getStorageV1();
    $.name = name_;
    $.symbol = symbol_;
    $.decimals = decimals_;
    $.supplyManager = supplyManager_;
  }

  modifier onlySupplyManager() {
    require(_msgSender() == _getStorageV1().supplyManager, StdError.Unauthorized());
    _;
  }

  function name() public view override returns (string memory) {
    return _getStorageV1().name;
  }

  function symbol() public view override returns (string memory) {
    return _getStorageV1().symbol;
  }

  function decimals() public view override returns (uint8) {
    return _getStorageV1().decimals;
  }

  function supplyManager() external view returns (address) {
    return _getStorageV1().supplyManager;
  }

  function mint(address account, uint256 value) external onlySupplyManager {
    require(value > 0, StdError.ZeroAmount());

    _mint(account, value);
  }

  function burn(address account, uint256 value) external onlySupplyManager {
    require(value > 0, StdError.ZeroAmount());

    _burn(account, value);
  }

  function setSupplyManager(address supplyManager_) external onlyOwner {
    StorageV1 storage $ = _getStorageV1();

    address oldSupplyManager = $.supplyManager;
    $.supplyManager = supplyManager_;

    emit SupplyManagerUpdated(oldSupplyManager, supplyManager_);
  }
}
