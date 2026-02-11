// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { ReentrancyGuardTransient } from '@oz/utils/ReentrancyGuardTransient.sol';
import { Checkpoints } from '@oz/utils/structs/Checkpoints.sol';
import { Time } from '@oz/utils/types/Time.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { SafeTransferLib } from '@solady/utils/SafeTransferLib.sol';

import { IValidatorManager } from '../../interfaces/hub/validator/IValidatorManager.sol';
import { IValidatorStaking } from '../../interfaces/hub/validator/IValidatorStaking.sol';
import { IValidatorStakingHub } from '../../interfaces/hub/validator/IValidatorStakingHub.sol';
import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { LibQueue } from '../../lib/LibQueue.sol';
import { StdError } from '../../lib/StdError.sol';

contract ValidatorStakingStorageV1 {
  using ERC7201Utils for string;

  struct StorageV1 {
    // configs
    uint48 unstakeCooldown;
    uint48 redelegationCooldown;
    uint256 minStakingAmount;
    uint256 minUnstakingAmount;
    // states
    Checkpoints.Trace208 totalStaked;
    Checkpoints.Trace208 totalUnstaking;
    mapping(address staker => LibQueue.Trace208OffsetQueue) unstakeQueue;
    mapping(address staker => Checkpoints.Trace208) stakerTotal;
    mapping(address valAddr => Checkpoints.Trace208) validatorTotal;
    mapping(address valAddr => mapping(address staker => Checkpoints.Trace208)) staked;
    mapping(address staker => mapping(address valAddr => uint256)) lastRedelegationTime;
  }

  string private constant _NAMESPACE = 'mitosis.storage.ValidatorStaking.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }
}

contract ValidatorStaking is
  IValidatorStaking,
  ValidatorStakingStorageV1,
  Ownable2StepUpgradeable,
  ReentrancyGuardTransient,
  UUPSUpgradeable
{
  using SafeCast for uint256;
  using SafeTransferLib for address;
  using Checkpoints for Checkpoints.Trace208;
  using LibQueue for LibQueue.Trace208OffsetQueue;

  address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  address private immutable _baseAsset;
  IValidatorManager private immutable _manager;
  IValidatorStakingHub private immutable _hub;

  constructor(address baseAsset_, IValidatorManager manager_, IValidatorStakingHub hub_) {
    _baseAsset = baseAsset_ == address(0) ? NATIVE_TOKEN : baseAsset_;
    _manager = manager_;
    _hub = hub_;

    _disableInitializers();
  }

  function initialize(
    address initialOwner,
    uint256 initialMinStakingAmount,
    uint256 initialMinUnstakingAmount,
    uint48 unstakeCooldown_,
    uint48 redelegationCooldown_
  ) public virtual initializer {
    __Ownable_init(initialOwner);
    __Ownable2Step_init();
    __UUPSUpgradeable_init();

    StorageV1 storage $ = _getStorageV1();
    _setMinStakingAmount($, initialMinStakingAmount);
    _setMinUnstakingAmount($, initialMinUnstakingAmount);
    _setUnstakeCooldown($, unstakeCooldown_);
    _setRedelegationCooldown($, redelegationCooldown_);
  }

  // ===================================== VIEW FUNCTIONS ===================================== //

  /// @inheritdoc IValidatorStaking
  function baseAsset() external view returns (address) {
    return _baseAsset;
  }

  function manager() external view returns (IValidatorManager) {
    return _manager;
  }

  /// @inheritdoc IValidatorStaking
  function hub() external view returns (IValidatorStakingHub) {
    return _hub;
  }

  /// @inheritdoc IValidatorStaking
  function totalStaked(uint48 timestamp) external view virtual returns (uint256) {
    return _getStorageV1().totalStaked.upperLookupRecent(timestamp);
  }

  /// @inheritdoc IValidatorStaking
  function totalUnstaking(uint48 timestamp) external view virtual returns (uint256) {
    return _getStorageV1().totalUnstaking.upperLookupRecent(timestamp);
  }

  /// @inheritdoc IValidatorStaking
  function staked(address valAddr, address staker, uint48 timestamp) external view virtual returns (uint256) {
    return _getStorageV1().staked[valAddr][staker].upperLookupRecent(timestamp);
  }

  /// @inheritdoc IValidatorStaking
  function stakerTotal(address staker, uint48 timestamp) public view virtual returns (uint256) {
    return _getStorageV1().stakerTotal[staker].upperLookupRecent(timestamp);
  }

  /// @inheritdoc IValidatorStaking
  function validatorTotal(address valAddr, uint48 timestamp) external view virtual returns (uint256) {
    return _getStorageV1().validatorTotal[valAddr].upperLookupRecent(timestamp);
  }

  /// @inheritdoc IValidatorStaking
  function unstaking(address staker, uint48 timestamp) public view virtual returns (uint256, uint256) {
    StorageV1 storage $ = _getStorageV1();
    return $.unstakeQueue[staker].pending(timestamp - $.unstakeCooldown);
  }

  /// @inheritdoc IValidatorStaking
  function unstakingQueueOffset(address staker) external view returns (uint256) {
    return _getStorageV1().unstakeQueue[staker].offset();
  }

  /// @inheritdoc IValidatorStaking
  function unstakingQueueSize(address staker) external view returns (uint256) {
    return _getStorageV1().unstakeQueue[staker].size();
  }

  /// @inheritdoc IValidatorStaking
  function unstakingQueueRequestByIndex(address staker, uint32 pos) external view returns (uint48, uint208) {
    return _getStorageV1().unstakeQueue[staker].itemAt(pos);
  }

  /// @inheritdoc IValidatorStaking
  function unstakingQueueRequestByTime(address staker, uint48 time) external view returns (uint48, uint208) {
    return _getStorageV1().unstakeQueue[staker].recentItemAt(time);
  }

  /// @inheritdoc IValidatorStaking
  function minStakingAmount() external view virtual returns (uint256) {
    return _getStorageV1().minStakingAmount;
  }

  /// @inheritdoc IValidatorStaking
  function minUnstakingAmount() external view virtual returns (uint256) {
    return _getStorageV1().minUnstakingAmount;
  }

  /// @inheritdoc IValidatorStaking
  function unstakeCooldown() external view virtual returns (uint48) {
    return _getStorageV1().unstakeCooldown;
  }

  /// @inheritdoc IValidatorStaking
  function redelegationCooldown() external view virtual returns (uint48) {
    return _getStorageV1().redelegationCooldown;
  }

  /// @inheritdoc IValidatorStaking
  function lastRedelegationTime(address staker, address valAddr) external view virtual returns (uint256) {
    return _getStorageV1().lastRedelegationTime[staker][valAddr];
  }

  // ===================================== MUTATIVE FUNCTIONS ===================================== //

  /// @inheritdoc IValidatorStaking
  function stake(address valAddr, address recipient, uint256 amount) external payable returns (uint256) {
    return _stake(_getStorageV1(), valAddr, _msgSender(), recipient, amount);
  }

  /// @inheritdoc IValidatorStaking
  function requestUnstake(address valAddr, address receiver, uint256 amount) external returns (uint256) {
    return _requestUnstake(_getStorageV1(), valAddr, _msgSender(), receiver, amount);
  }

  /// @inheritdoc IValidatorStaking
  function claimUnstake(address receiver) external nonReentrant returns (uint256) {
    return _claimUnstake(_getStorageV1(), receiver);
  }

  /// @inheritdoc IValidatorStaking
  function redelegate(address fromValAddr, address toValAddr, uint256 amount) external returns (uint256) {
    return _redelegate(_getStorageV1(), _msgSender(), fromValAddr, toValAddr, amount);
  }

  /// @inheritdoc IValidatorStaking
  function setMinStakingAmount(uint256 minAmount) external onlyOwner {
    _setMinStakingAmount(_getStorageV1(), minAmount);
  }

  /// @inheritdoc IValidatorStaking
  function setMinUnstakingAmount(uint256 minAmount) external onlyOwner {
    _setMinUnstakingAmount(_getStorageV1(), minAmount);
  }

  /// @inheritdoc IValidatorStaking
  function setUnstakeCooldown(uint48 unstakeCooldown_) external onlyOwner {
    _setUnstakeCooldown(_getStorageV1(), unstakeCooldown_);
  }

  /// @inheritdoc IValidatorStaking
  function setRedelegationCooldown(uint48 redelegationCooldown_) external onlyOwner {
    _setRedelegationCooldown(_getStorageV1(), redelegationCooldown_);
  }

  // ===================================== INTERNAL FUNCTIONS ===================================== //

  function _assertUnstakeAmountCondition(StorageV1 storage $, address valAddr, address staker, uint256 amount)
    internal
    view
  {
    uint256 currentStaked = $.staked[valAddr][staker].latest();
    uint256 minUnstaking = $.minUnstakingAmount;

    if (amount != currentStaked) {
      require(amount >= minUnstaking, IValidatorStaking__InsufficientMinimumAmount(minUnstaking));
    }
  }

  function _stake(StorageV1 storage $, address valAddr, address payer, address recipient, uint256 amount)
    internal
    virtual
    returns (uint256)
  {
    require(amount > 0, StdError.ZeroAmount());
    require(amount >= $.minStakingAmount, IValidatorStaking__InsufficientMinimumAmount($.minStakingAmount));

    require(_baseAsset != NATIVE_TOKEN || msg.value == amount, StdError.InvalidParameter('amount'));
    require(recipient != address(0), StdError.InvalidParameter('recipient'));
    require(_manager.isValidator(valAddr), IValidatorStaking__NotValidator(valAddr));

    // If the base asset is not native, we need to transfer from the sender to the contract
    if (_baseAsset != NATIVE_TOKEN) _baseAsset.safeTransferFrom(payer, address(this), amount);

    uint48 now_ = Time.timestamp();

    // apply to state
    {
      uint208 amount208 = amount.toUint208();
      _push($.totalStaked, now_, amount208, _opAdd);
      _storeStake($, now_, valAddr, recipient, amount208);
    }

    _hub.notifyStake(valAddr, recipient, amount);

    emit Staked(valAddr, payer, recipient, amount);

    return amount;
  }

  function _requestUnstake(StorageV1 storage $, address valAddr, address payer, address recipient, uint256 amount)
    internal
    virtual
    returns (uint256)
  {
    require(amount > 0, StdError.ZeroAmount());
    require(_manager.isValidator(valAddr), IValidatorStaking__NotValidator(valAddr));

    _assertUnstakeAmountCondition($, valAddr, payer, amount);

    uint48 now_ = Time.timestamp();
    uint208 amount208 = amount.toUint208();
    uint256 reqId = $.unstakeQueue[recipient].append(now_, amount208);

    // apply to state
    {
      _push($.totalStaked, now_, amount208, _opSub);
      _push($.totalUnstaking, now_, amount208, _opAdd);
      _storeUnstake($, now_, valAddr, payer, amount208);
    }

    _hub.notifyUnstake(valAddr, payer, amount);

    emit UnstakeRequested(valAddr, payer, recipient, amount, reqId);

    return reqId;
  }

  function _claimUnstake(StorageV1 storage $, address receiver) internal virtual returns (uint256) {
    LibQueue.Trace208OffsetQueue storage queue = $.unstakeQueue[receiver];

    uint48 now_ = Time.timestamp();
    (uint32 reqIdFrom, uint32 reqIdTo) = queue.solveByKey(now_ - $.unstakeCooldown);
    uint256 claimed;
    {
      uint256 fromValue = reqIdFrom == 0 ? 0 : queue.valueAt(reqIdFrom - 1);
      uint256 toValue = queue.valueAt(reqIdTo - 1);
      claimed = toValue - fromValue;
    }

    if (_baseAsset == NATIVE_TOKEN) receiver.safeTransferETH(claimed);
    else _baseAsset.safeTransfer(receiver, claimed);

    // apply to state
    _push($.totalUnstaking, now_, claimed.toUint208(), _opSub);

    emit UnstakeClaimed(receiver, claimed, reqIdFrom, reqIdTo);

    return claimed;
  }

  function _checkRedelegationCooldown(StorageV1 storage $, uint48 now_, address delegator, address valAddr)
    internal
    view
  {
    uint256 lastRedelegationTime_ = $.lastRedelegationTime[delegator][valAddr];

    if (lastRedelegationTime_ > 0) {
      uint48 cooldown = $.redelegationCooldown;
      uint48 lasttime = lastRedelegationTime_.toUint48();
      require(
        now_ >= lasttime + cooldown, //
        IValidatorStaking__CooldownNotPassed(lasttime, now_, (lasttime + cooldown) - now_)
      );
    }
  }

  function _redelegate(StorageV1 storage $, address delegator, address fromValAddr, address toValAddr, uint256 amount)
    internal
    virtual
    returns (uint256)
  {
    require(amount > 0, StdError.ZeroAmount());
    require(fromValAddr != toValAddr, IValidatorStaking__RedelegateToSameValidator(fromValAddr));

    _assertUnstakeAmountCondition($, fromValAddr, delegator, amount);

    require(_manager.isValidator(fromValAddr), IValidatorStaking__NotValidator(fromValAddr));
    require(_manager.isValidator(toValAddr), IValidatorStaking__NotValidator(toValAddr));

    uint48 now_ = Time.timestamp();

    _checkRedelegationCooldown($, now_, delegator, fromValAddr);
    _checkRedelegationCooldown($, now_, delegator, toValAddr);

    $.lastRedelegationTime[delegator][fromValAddr] = now_;
    $.lastRedelegationTime[delegator][toValAddr] = now_;

    // apply to state
    {
      uint208 amount208 = amount.toUint208();
      _storeUnstake($, now_, fromValAddr, delegator, amount208);
      _storeStake($, now_, toValAddr, delegator, amount208);
    }

    _hub.notifyRedelegation(fromValAddr, toValAddr, delegator, amount);

    emit Redelegated(fromValAddr, toValAddr, delegator, amount);

    return amount;
  }

  function _storeStake(StorageV1 storage $, uint48 now_, address valAddr, address staker, uint208 amount)
    internal
    virtual
  {
    _push($.staked[valAddr][staker], now_, amount, _opAdd);
    _push($.stakerTotal[staker], now_, amount, _opAdd);
    _push($.validatorTotal[valAddr], now_, amount, _opAdd);
  }

  function _storeUnstake(StorageV1 storage $, uint48 now_, address valAddr, address staker, uint208 amount)
    internal
    virtual
  {
    _push($.staked[valAddr][staker], now_, amount, _opSub);
    _push($.stakerTotal[staker], now_, amount, _opSub);
    _push($.validatorTotal[valAddr], now_, amount, _opSub);
  }

  function _push(
    Checkpoints.Trace208 storage $,
    uint48 time,
    uint208 amount,
    function (uint208,uint208) pure returns (uint208) op
  ) private {
    $.push(time, op($.latest(), amount));
  }

  function _opSub(uint208 x, uint208 y) private pure returns (uint208) {
    unchecked {
      return x - y;
    }
  }

  function _opAdd(uint208 x, uint208 y) private pure returns (uint208) {
    unchecked {
      return x + y;
    }
  }

  // ========== ADMIN ACTIONS ========== //

  function _setMinStakingAmount(StorageV1 storage $, uint256 minAmount) internal virtual {
    uint256 previous = $.minStakingAmount;
    $.minStakingAmount = minAmount;
    emit MinimumStakingAmountSet(previous, minAmount);
  }

  function _setMinUnstakingAmount(StorageV1 storage $, uint256 minAmount) internal virtual {
    uint256 previous = $.minUnstakingAmount;
    $.minUnstakingAmount = minAmount;
    emit MinimumUnstakingAmountSet(previous, minAmount);
  }

  function _setUnstakeCooldown(StorageV1 storage $, uint48 unstakeCooldown_) internal virtual {
    require(unstakeCooldown_ > 0, StdError.InvalidParameter('unstakeCooldown'));

    $.unstakeCooldown = unstakeCooldown_;

    emit UnstakeCooldownUpdated(unstakeCooldown_);
  }

  function _setRedelegationCooldown(StorageV1 storage $, uint48 redelegationCooldown_) internal virtual {
    require(redelegationCooldown_ > 0, StdError.InvalidParameter('redelegationCooldown'));

    $.redelegationCooldown = redelegationCooldown_;

    emit RedelegationCooldownUpdated(redelegationCooldown_);
  }

  //============ UUPS ============ //

  function _authorizeUpgrade(address) internal override onlyOwner { }
}
