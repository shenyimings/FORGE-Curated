// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { Address } from '@oz/utils/Address.sol';
import { ReentrancyGuard } from '@oz/utils/ReentrancyGuard.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';

import { IMitosisVault } from '../../interfaces/branch/IMitosisVault.sol';
import { IStrategyExecutor } from '../../interfaces/branch/strategy/IStrategyExecutor.sol';
import { IVLFStrategyExecutor } from '../../interfaces/branch/strategy/IVLFStrategyExecutor.sol';
import { ITally } from '../../interfaces/branch/strategy/tally/ITally.sol';
import { StdError } from '../../lib/StdError.sol';
import { Versioned } from '../../lib/Versioned.sol';
import { VLFStrategyExecutorStorageV1 } from './VLFStrategyExecutorStorageV1.sol';

contract VLFStrategyExecutor is
  IStrategyExecutor,
  IVLFStrategyExecutor,
  Ownable2StepUpgradeable,
  ReentrancyGuard,
  VLFStrategyExecutorStorageV1,
  Versioned
{
  using SafeERC20 for IERC20;
  using Address for address;

  //=========== NOTE: INITIALIZATION FUNCTIONS ===========//

  constructor() {
    _disableInitializers();
  }

  fallback() external payable {
    revert StdError.NotSupported();
  }

  receive() external payable {
    Address.sendValue(payable(_getStorageV1().strategist), msg.value);
  }

  function initialize(IMitosisVault vault_, IERC20 asset_, address hubVLFVault_, address owner_) public initializer {
    __Ownable2Step_init();
    __Ownable_init(owner_);

    StorageV1 storage $ = _getStorageV1();

    $.vault = vault_;
    $.asset = asset_;
    $.hubVLFVault = hubVLFVault_;
  }

  //=========== NOTE: VIEW FUNCTIONS ===========//

  function vault() external view returns (IMitosisVault) {
    return _getStorageV1().vault;
  }

  function asset() external view returns (IERC20) {
    return _getStorageV1().asset;
  }

  function hubVLFVault() external view returns (address) {
    return _getStorageV1().hubVLFVault;
  }

  function strategist() external view returns (address) {
    return _getStorageV1().strategist;
  }

  function executor() external view returns (address) {
    return _getStorageV1().executor;
  }

  function tally() external view returns (ITally) {
    return _getStorageV1().tally;
  }

  function totalBalance() external view returns (uint256) {
    return _totalBalance(_getStorageV1());
  }

  function storedTotalBalance() external view returns (uint256) {
    return _getStorageV1().storedTotalBalance;
  }

  function quoteDeallocateLiquidity(uint256 amount) external view returns (uint256) {
    StorageV1 memory $ = _getStorageV1();
    return $.vault.quoteDeallocateVLF($.hubVLFVault, amount);
  }

  function quoteSettleYield(uint256 amount) external view returns (uint256) {
    StorageV1 memory $ = _getStorageV1();
    return $.vault.quoteSettleVLFYield($.hubVLFVault, amount);
  }

  function quoteSettleLoss(uint256 amount) external view returns (uint256) {
    StorageV1 memory $ = _getStorageV1();
    return $.vault.quoteSettleVLFLoss($.hubVLFVault, amount);
  }

  function quoteSettleExtraRewards(address reward, uint256 amount) external view returns (uint256) {
    StorageV1 memory $ = _getStorageV1();
    return $.vault.quoteSettleVLFExtraRewards($.hubVLFVault, reward, amount);
  }

  //=========== NOTE: STRATEGIST FUNCTIONS ===========//

  function deallocateLiquidity(uint256 amount) external payable {
    require(amount > 0, StdError.ZeroAmount());

    StorageV1 memory $ = _getStorageV1();

    _assertOnlyStrategist($);

    $.vault.deallocateVLF{ value: msg.value }($.hubVLFVault, amount);
  }

  function fetchLiquidity(uint256 amount) external {
    require(amount > 0, StdError.ZeroAmount());

    StorageV1 storage $ = _getStorageV1();

    _assertOnlyStrategist($);

    $.vault.fetchVLF($.hubVLFVault, amount);
    $.storedTotalBalance += amount;
  }

  function returnLiquidity(uint256 amount) external {
    require(amount > 0, StdError.ZeroAmount());

    StorageV1 storage $ = _getStorageV1();

    _assertOnlyStrategist($);

    $.asset.approve(address($.vault), amount);
    $.vault.returnVLF($.hubVLFVault, amount);
    $.storedTotalBalance -= amount;
  }

  function settle() external payable nonReentrant {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyStrategist($);

    uint256 totalBalance_ = _totalBalance($);
    uint256 storedTotalBalance_ = $.storedTotalBalance;

    $.storedTotalBalance = totalBalance_;

    if (totalBalance_ >= storedTotalBalance_) {
      $.vault.settleVLFYield{ value: msg.value }($.hubVLFVault, totalBalance_ - storedTotalBalance_);
    } else {
      $.vault.settleVLFLoss{ value: msg.value }($.hubVLFVault, storedTotalBalance_ - totalBalance_);
    }
  }

  function settleExtraRewards(address reward, uint256 amount) external payable {
    require(amount > 0, StdError.ZeroAmount());

    StorageV1 memory $ = _getStorageV1();

    _assertOnlyStrategist($);
    require(reward != address($.asset), StdError.InvalidAddress('reward'));

    IERC20(reward).approve(address($.vault), amount);
    $.vault.settleVLFExtraRewards{ value: msg.value }($.hubVLFVault, reward, amount);
  }

  //=========== NOTE: EXECUTOR FUNCTIONS ===========//

  function execute(address target, bytes calldata data, uint256 value)
    external
    nonReentrant
    returns (bytes memory result)
  {
    StorageV1 memory $ = _getStorageV1();
    _assertOnlyExecutor($);

    result = target.functionCallWithValue(data, value);
  }

  function execute(address[] calldata targets, bytes[] calldata data, uint256[] calldata values)
    external
    nonReentrant
    returns (bytes[] memory results)
  {
    require(targets.length == data.length && data.length == values.length, StdError.InvalidParameter('executeData'));

    StorageV1 memory $ = _getStorageV1();
    _assertOnlyExecutor($);

    uint256 targetsLength = targets.length;
    results = new bytes[](targetsLength);
    for (uint256 i; i < targetsLength; ++i) {
      results[i] = targets[i].functionCallWithValue(data[i], values[i]);
    }
  }

  //=========== NOTE: OWNABLE FUNCTIONS ===========//

  function setTally(address implementation) external onlyOwner {
    require(implementation.code.length > 0, StdError.InvalidAddress('implementation'));

    StorageV1 storage $ = _getStorageV1();
    require(
      address($.tally) == address(0) || _tallyTotalBalance($) == 0,
      IVLFStrategyExecutor.IVLFStrategyExecutor__TallyTotalBalanceNotZero(implementation)
    );

    $.tally = ITally(implementation);
    emit TallySet(implementation);
  }

  function setStrategist(address strategist_) external onlyOwner {
    require(strategist_ != address(0), StdError.InvalidAddress('strategist'));
    _getStorageV1().strategist = strategist_;
    emit StrategistSet(strategist_);
  }

  function setExecutor(address executor_) external onlyOwner {
    require(executor_ != address(0), StdError.InvalidAddress('executor'));
    _getStorageV1().executor = executor_;
    emit ExecutorSet(executor_);
  }

  function unsetStrategist() external onlyOwner {
    _getStorageV1().strategist = address(0);
    emit StrategistSet(address(0));
  }

  function unsetExecutor() external onlyOwner {
    _getStorageV1().executor = address(0);
    emit ExecutorSet(address(0));
  }

  //=========== NOTE: INTERNAL FUNCTIONS ===========//

  function _assertOnlyStrategist(StorageV1 memory $) internal view {
    address strategist_ = $.strategist;
    require(strategist_ != address(0), IVLFStrategyExecutor.IVLFStrategyExecutor__StrategistNotSet());
    require(_msgSender() == strategist_, StdError.Unauthorized());
  }

  function _assertOnlyExecutor(StorageV1 memory $) internal view {
    address executor_ = $.executor;
    require(executor_ != address(0), IVLFStrategyExecutor.IVLFStrategyExecutor__ExecutorNotSet());
    require(_msgSender() == executor_, StdError.Unauthorized());
  }

  function _tallyTotalBalance(StorageV1 storage $) internal view returns (uint256) {
    bytes memory context;
    return
      $.tally.pendingDepositBalance(context) + $.tally.totalBalance(context) + $.tally.pendingWithdrawBalance(context);
  }

  function _totalBalance(StorageV1 storage $) internal view returns (uint256) {
    return $.asset.balanceOf(address(this)) + _tallyTotalBalance($);
  }
}
