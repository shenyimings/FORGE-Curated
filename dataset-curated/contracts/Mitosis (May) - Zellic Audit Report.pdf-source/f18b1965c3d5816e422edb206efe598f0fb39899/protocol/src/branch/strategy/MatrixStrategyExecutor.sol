// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { Address } from '@oz/utils/Address.sol';
import { ReentrancyGuardTransient } from '@oz/utils/ReentrancyGuardTransient.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';

import { IMitosisVault } from '../../interfaces/branch/IMitosisVault.sol';
import { IMatrixStrategyExecutor } from '../../interfaces/branch/strategy/IMatrixStrategyExecutor.sol';
import { IStrategyExecutor } from '../../interfaces/branch/strategy/IStrategyExecutor.sol';
import { ITally } from '../../interfaces/branch/strategy/tally/ITally.sol';
import { StdError } from '../../lib/StdError.sol';
import { MatrixStrategyExecutorStorageV1 } from './MatrixStrategyExecutorStorageV1.sol';

contract MatrixStrategyExecutor is
  IStrategyExecutor,
  IMatrixStrategyExecutor,
  Ownable2StepUpgradeable,
  ReentrancyGuardTransient,
  MatrixStrategyExecutorStorageV1
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
    revert StdError.NotSupported();
  }

  function initialize(IMitosisVault vault_, IERC20 asset_, address hubMatrixVault_, address owner_) public initializer {
    __Ownable2Step_init();
    __Ownable_init(owner_);

    StorageV1 storage $ = _getStorageV1();

    $.vault = vault_;
    $.asset = asset_;
    $.hubMatrixVault = hubMatrixVault_;
  }

  //=========== NOTE: VIEW FUNCTIONS ===========//

  function vault() external view returns (IMitosisVault) {
    return _getStorageV1().vault;
  }

  function asset() external view returns (IERC20) {
    return _getStorageV1().asset;
  }

  function hubMatrixVault() external view returns (address) {
    return _getStorageV1().hubMatrixVault;
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

  //=========== NOTE: STRATEGIST FUNCTIONS ===========//

  function deallocateLiquidity(uint256 amount) external {
    require(amount > 0, StdError.ZeroAmount());

    StorageV1 memory $ = _getStorageV1();

    _assertOnlyStrategist($);

    $.vault.deallocateMatrix($.hubMatrixVault, amount);
  }

  function fetchLiquidity(uint256 amount) external {
    require(amount > 0, StdError.ZeroAmount());

    StorageV1 storage $ = _getStorageV1();

    _assertOnlyStrategist($);

    $.vault.fetchMatrix($.hubMatrixVault, amount);
    $.storedTotalBalance += amount;
  }

  function returnLiquidity(uint256 amount) external {
    require(amount > 0, StdError.ZeroAmount());

    StorageV1 storage $ = _getStorageV1();

    _assertOnlyStrategist($);

    $.asset.approve(address($.vault), amount);
    $.vault.returnMatrix($.hubMatrixVault, amount);
    $.storedTotalBalance -= amount;
  }

  function settle() external nonReentrant {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyStrategist($);

    uint256 totalBalance_ = _totalBalance($);
    uint256 storedTotalBalance_ = $.storedTotalBalance;

    $.storedTotalBalance = totalBalance_;

    if (totalBalance_ >= storedTotalBalance_) {
      $.vault.settleMatrixYield($.hubMatrixVault, totalBalance_ - storedTotalBalance_);
    } else {
      $.vault.settleMatrixLoss($.hubMatrixVault, storedTotalBalance_ - totalBalance_);
    }
  }

  function settleExtraRewards(address reward, uint256 amount) external {
    require(amount > 0, StdError.ZeroAmount());

    StorageV1 memory $ = _getStorageV1();

    _assertOnlyStrategist($);
    require(reward != address($.asset), StdError.InvalidAddress('reward'));

    IERC20(reward).approve(address($.vault), amount);
    $.vault.settleMatrixExtraRewards($.hubMatrixVault, reward, amount);
  }

  //=========== NOTE: EXECUTOR FUNCTIONS ===========//

  function execute(address target, bytes calldata data, uint256 value)
    external
    nonReentrant
    returns (bytes memory result)
  {
    StorageV1 memory $ = _getStorageV1();
    _assertOnlyExecutor($);
    _assertOnlyTallyRegisteredProtocol($, target);

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
    _assertOnlyTallyRegisteredProtocol($, targets);

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
      IMatrixStrategyExecutor.IMatrixStrategyExecutor__TallyTotalBalanceNotZero(implementation)
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
    require(strategist_ != address(0), IMatrixStrategyExecutor.IMatrixStrategyExecutor__StrategistNotSet());
    require(_msgSender() == strategist_, StdError.Unauthorized());
  }

  function _assertOnlyExecutor(StorageV1 memory $) internal view {
    address executor_ = $.executor;
    require(executor_ != address(0), IMatrixStrategyExecutor.IMatrixStrategyExecutor__ExecutorNotSet());
    require(_msgSender() == executor_, StdError.Unauthorized());
  }

  function _assertOnlyTallyRegisteredProtocol(StorageV1 memory $, address target) internal view {
    require($.tally.protocolAddress() == target, IMatrixStrategyExecutor__TallyNotSet(target));
  }

  function _assertOnlyTallyRegisteredProtocol(StorageV1 memory $, address[] memory targets) internal view {
    address expected = $.tally.protocolAddress();
    for (uint256 i = 0; i < targets.length; i++) {
      address target = targets[i];
      require(expected == target, IMatrixStrategyExecutor__TallyNotSet(target));
    }
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
