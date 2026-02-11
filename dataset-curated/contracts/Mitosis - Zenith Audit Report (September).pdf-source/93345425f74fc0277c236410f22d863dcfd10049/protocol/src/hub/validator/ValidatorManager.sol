// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Math } from '@oz/utils/math/Math.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { ReentrancyGuard } from '@oz/utils/ReentrancyGuard.sol';
import { Checkpoints } from '@oz/utils/structs/Checkpoints.sol';
import { EnumerableSet } from '@oz/utils/structs/EnumerableSet.sol';
import { Time } from '@oz/utils/types/Time.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { SafeTransferLib } from '@solady/utils/SafeTransferLib.sol';

import { IConsensusValidatorEntrypoint } from '../../interfaces/hub/consensus-layer/IConsensusValidatorEntrypoint.sol';
import { IEpochFeeder } from '../../interfaces/hub/validator/IEpochFeeder.sol';
import { IValidatorManager } from '../../interfaces/hub/validator/IValidatorManager.sol';
import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { LibSecp256k1 } from '../../lib/LibSecp256k1.sol';
import { StdError } from '../../lib/StdError.sol';
import { Versioned } from '../../lib/Versioned.sol';

/// @notice Storage layout for ValidatorManager
/// @dev Uses ERC7201 for storage slot management
contract ValidatorManagerStorageV1 {
  using ERC7201Utils for string;

  struct GlobalValidatorConfig {
    uint256 initialValidatorDeposit; // used on creation of the validator
    uint256 collateralWithdrawalDelaySeconds;
    Checkpoints.Trace160 minimumCommissionRates;
    uint96 commissionRateUpdateDelayEpoch;
  }

  struct ValidatorRewardConfig {
    uint128 pendingCommissionRate; // bp ex) 10000 = 100%
    uint128 pendingCommissionRateUpdateEpoch; // current epoch + 2
    Checkpoints.Trace160 commissionRates; // bp ex) 10000 = 100%
  }

  struct Validator {
    address valAddr;
    address operator;
    address rewardManager;
    bytes pubKey;
    ValidatorRewardConfig rewardConfig;
    bytes metadata;
    EnumerableSet.AddressSet permittedCollateralOwners;
  }

  struct StorageV1 {
    uint256 fee; // Fee for methods that need to communicate with the consensus layer.
    GlobalValidatorConfig globalValidatorConfig;
    // validator
    uint256 validatorCount;
    mapping(uint256 index => Validator) validators;
    mapping(address valAddr => uint256 index) indexByValAddr;
  }

  string private constant _NAMESPACE = 'mitosis.storage.ValidatorManagerStorage.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }
}

contract ValidatorManager is
  IValidatorManager,
  ValidatorManagerStorageV1,
  Ownable2StepUpgradeable,
  ReentrancyGuard,
  UUPSUpgradeable,
  Versioned
{
  using SafeCast for uint256;
  using LibSecp256k1 for bytes;
  using Checkpoints for Checkpoints.Trace160;
  using EnumerableSet for EnumerableSet.AddressSet;

  IEpochFeeder private immutable _epochFeeder;
  IConsensusValidatorEntrypoint private immutable _entrypoint;

  /// @notice Maximum commission rate in basis points (10000 = 100%)
  uint256 public constant MAX_COMMISSION_RATE = 10000;

  constructor(IEpochFeeder epochFeeder_, IConsensusValidatorEntrypoint entrypoint_) {
    _disableInitializers();

    _epochFeeder = epochFeeder_;
    _entrypoint = entrypoint_;
  }

  function initialize(
    address initialOwner,
    uint256 initialFee,
    SetGlobalValidatorConfigRequest memory initialGlobalValidatorConfig,
    GenesisValidatorSet[] memory genesisValidators
  ) external initializer {
    __UUPSUpgradeable_init();
    __Ownable_init(initialOwner);
    __Ownable2Step_init();

    StorageV1 storage $ = _getStorageV1();

    _setFee($, initialFee);
    _setGlobalValidatorConfig($, initialGlobalValidatorConfig);

    for (uint256 i = 0; i < genesisValidators.length; i++) {
      GenesisValidatorSet memory genVal = genesisValidators[i];

      bytes memory uncmpPubKey = genVal.pubKey.uncompressPubkey();
      uncmpPubKey.verifyUncmpPubkey();
      address valAddr = uncmpPubKey.deriveAddressFromUncmpPubkey();

      Validator storage validator = _createValidator(
        $,
        valAddr,
        genVal.pubKey,
        genVal.value,
        CreateValidatorRequest({
          operator: genVal.operator,
          rewardManager: genVal.rewardManager,
          commissionRate: genVal.commissionRate,
          metadata: genVal.metadata
        })
      );

      for (uint256 j = 0; j < genVal.permittedCollateralOwners.length; j++) {
        _setPermittedCollateralOwner(validator, genVal.permittedCollateralOwners[j], true);
      }
    }
  }

  /// @inheritdoc IValidatorManager
  function entrypoint() external view returns (IConsensusValidatorEntrypoint) {
    return _entrypoint;
  }

  /// @inheritdoc IValidatorManager
  function epochFeeder() external view returns (IEpochFeeder) {
    return _epochFeeder;
  }

  /// @inheritdoc IValidatorManager
  function fee() external view returns (uint256) {
    return _getStorageV1().fee;
  }

  /// @inheritdoc IValidatorManager
  function globalValidatorConfig() external view returns (GlobalValidatorConfigResponse memory) {
    StorageV1 storage $ = _getStorageV1();
    GlobalValidatorConfig storage config = $.globalValidatorConfig;

    return GlobalValidatorConfigResponse({
      initialValidatorDeposit: config.initialValidatorDeposit,
      collateralWithdrawalDelaySeconds: config.collateralWithdrawalDelaySeconds,
      minimumCommissionRate: config.minimumCommissionRates.latest(),
      commissionRateUpdateDelayEpoch: config.commissionRateUpdateDelayEpoch
    });
  }

  /// @inheritdoc IValidatorManager
  function validatorPubKeyToAddress(bytes calldata pubKey) external pure returns (address) {
    bytes memory uncmpPubKey = pubKey.uncompressPubkey();
    uncmpPubKey.verifyUncmpPubkey();
    return uncmpPubKey.deriveAddressFromUncmpPubkey();
  }

  /// @inheritdoc IValidatorManager
  function validatorCount() external view returns (uint256) {
    return _getStorageV1().validatorCount;
  }

  /// @inheritdoc IValidatorManager
  function validatorAt(uint256 index) external view returns (address) {
    return _getStorageV1().validators[index].valAddr;
  }

  /// @inheritdoc IValidatorManager
  function isValidator(address valAddr) external view returns (bool) {
    return _getStorageV1().indexByValAddr[valAddr] != 0;
  }

  /// @inheritdoc IValidatorManager
  function validatorInfo(address valAddr) external view returns (ValidatorInfoResponse memory) {
    return _validatorInfoAt(_getStorageV1(), valAddr, _epochFeeder.epoch());
  }

  /// @inheritdoc IValidatorManager
  function validatorInfoAt(uint256 epoch, address valAddr) external view returns (ValidatorInfoResponse memory) {
    return _validatorInfoAt(_getStorageV1(), valAddr, epoch);
  }

  /// @inheritdoc IValidatorManager
  function permittedCollateralOwnerSize(address valAddr) external view returns (uint256) {
    return _validator(_getStorageV1(), valAddr).permittedCollateralOwners.length();
  }

  /// @inheritdoc IValidatorManager
  function permittedCollateralOwnerAt(address valAddr, uint256 index) external view returns (address) {
    return _validator(_getStorageV1(), valAddr).permittedCollateralOwners.at(index);
  }

  /// @inheritdoc IValidatorManager
  function isPermittedCollateralOwner(address valAddr, address collateralOwner) external view returns (bool) {
    Validator storage validator = _validator(_getStorageV1(), valAddr);
    return validator.permittedCollateralOwners.contains(collateralOwner);
  }

  /// @inheritdoc IValidatorManager
  function createValidator(bytes calldata pubKey, CreateValidatorRequest calldata request)
    external
    payable
    nonReentrant
  {
    require(pubKey.length > 0, StdError.InvalidParameter('pubKey'));

    address valAddr = _msgSender();

    // verify the pubKey is valid and corresponds to the caller
    pubKey.verifyCmpPubkeyWithAddress(valAddr);

    StorageV1 storage $ = _getStorageV1();

    uint256 netMsgValue = _burnFee($);
    Validator storage validator = _createValidator($, valAddr, pubKey, netMsgValue, request);

    // operator becomes an initial collateral owner
    _setPermittedCollateralOwner(validator, request.operator, true);

    _entrypoint.registerValidator{ value: netMsgValue }(valAddr, pubKey, request.operator);
  }

  /// @inheritdoc IValidatorManager
  function depositCollateral(address valAddr) external payable nonReentrant {
    StorageV1 storage $ = _getStorageV1();

    uint256 netMsgValue = _burnFee($);
    require(netMsgValue > 0, StdError.ZeroAmount());

    Validator storage validator = _validator($, valAddr);
    require(validator.permittedCollateralOwners.contains(_msgSender()), StdError.Unauthorized());

    _entrypoint.depositCollateral{ value: netMsgValue }(valAddr, _msgSender());

    emit CollateralDeposited(valAddr, _msgSender(), netMsgValue);
  }

  /// @inheritdoc IValidatorManager
  function withdrawCollateral(address valAddr, address receiver, uint256 amount) external payable nonReentrant {
    require(amount > 0, StdError.ZeroAmount());

    StorageV1 storage $ = _getStorageV1();

    _burnFee($);
    _validator($, valAddr);

    _entrypoint.withdrawCollateral(
      valAddr,
      _msgSender(),
      receiver,
      amount,
      Time.timestamp() + $.globalValidatorConfig.collateralWithdrawalDelaySeconds.toUint48()
    );

    emit CollateralWithdrawn(valAddr, _msgSender(), receiver, amount);
  }

  /// @inheritdoc IValidatorManager
  function transferCollateralOwnership(address valAddr, address newOwner) external payable nonReentrant {
    StorageV1 storage $ = _getStorageV1();

    _burnFee($);

    Validator storage validator = _validator($, valAddr);
    require(validator.permittedCollateralOwners.contains(newOwner), StdError.InvalidParameter('newOwner'));

    _entrypoint.transferCollateralOwnership(valAddr, _msgSender(), newOwner);

    emit CollateralOwnershipTransferred(valAddr, _msgSender(), newOwner);
  }

  /// @inheritdoc IValidatorManager
  function unjailValidator(address valAddr) external payable nonReentrant {
    StorageV1 storage $ = _getStorageV1();

    _burnFee($);

    Validator storage validator = _validator($, valAddr);
    _assertOperatorOrValidator(validator);

    _entrypoint.unjail(valAddr);

    emit ValidatorUnjailed(valAddr);
  }

  /// @inheritdoc IValidatorManager
  function updateOperator(address valAddr, address operator) external {
    require(operator != address(0), StdError.InvalidParameter('operator'));

    StorageV1 storage $ = _getStorageV1();
    Validator storage validator = _validator($, valAddr);
    _assertOperator(validator);

    $.validators[$.indexByValAddr[valAddr]].operator = operator;

    emit OperatorUpdated(valAddr, operator);
  }

  /// @inheritdoc IValidatorManager
  function updateRewardManager(address valAddr, address rewardManager) external {
    require(rewardManager != address(0), StdError.InvalidParameter('rewardManager'));

    StorageV1 storage $ = _getStorageV1();
    Validator storage validator = _validator($, valAddr);
    _assertOperator(validator);

    $.validators[$.indexByValAddr[valAddr]].rewardManager = rewardManager;

    emit RewardManagerUpdated(valAddr, _msgSender(), rewardManager);
  }

  /// @inheritdoc IValidatorManager
  function updateMetadata(address valAddr, bytes calldata metadata) external {
    require(metadata.length > 0, StdError.InvalidParameter('metadata'));

    StorageV1 storage $ = _getStorageV1();
    Validator storage validator = _validator($, valAddr);
    _assertOperator(validator);

    $.validators[$.indexByValAddr[valAddr]].metadata = metadata;

    emit MetadataUpdated(valAddr, _msgSender(), metadata);
  }

  /// @inheritdoc IValidatorManager
  function updateRewardConfig(address valAddr, UpdateRewardConfigRequest calldata request) external {
    StorageV1 storage $ = _getStorageV1();
    Validator storage validator = _validator($, valAddr);
    _assertOperator(validator);

    GlobalValidatorConfig storage globalConfig = $.globalValidatorConfig;
    require(
      globalConfig.minimumCommissionRates.latest() <= request.commissionRate
        && request.commissionRate <= MAX_COMMISSION_RATE,
      StdError.InvalidParameter('commissionRate')
    );
    uint256 currentEpoch = _epochFeeder.epoch();

    // update previous pending rate
    if (validator.rewardConfig.pendingCommissionRateUpdateEpoch >= currentEpoch) {
      validator.rewardConfig.commissionRates.push(
        uint256(validator.rewardConfig.pendingCommissionRateUpdateEpoch).toUint96(),
        // check for global minimum commission rate modified
        Math.max(
          uint256(globalConfig.minimumCommissionRates.upperLookup(currentEpoch.toUint96())),
          validator.rewardConfig.pendingCommissionRate
        ).toUint160()
      );
    }

    uint256 epochToUpdate = currentEpoch + globalConfig.commissionRateUpdateDelayEpoch;

    // update pending commission rate
    validator.rewardConfig.pendingCommissionRate = request.commissionRate.toUint128();
    validator.rewardConfig.pendingCommissionRateUpdateEpoch = epochToUpdate.toUint128();

    emit RewardConfigUpdated(
      valAddr,
      _msgSender(),
      UpdateRewardConfigResult({
        pendingCommissionRate: validator.rewardConfig.pendingCommissionRate,
        pendingCommissionRateUpdateEpoch: validator.rewardConfig.pendingCommissionRateUpdateEpoch
      })
    );
  }

  /// @inheritdoc IValidatorManager
  function setPermittedCollateralOwner(address valAddr, address collateralOwner, bool isPermitted) external {
    require(collateralOwner != address(0), StdError.InvalidParameter('collateralOwner'));

    StorageV1 storage $ = _getStorageV1();
    Validator storage validator = _validator($, valAddr);
    _assertOperator(validator);

    _setPermittedCollateralOwner(validator, collateralOwner, isPermitted);
  }

  /// @inheritdoc IValidatorManager
  function setFee(uint256 fee_) external onlyOwner {
    _setFee(_getStorageV1(), fee_);
  }

  /// @inheritdoc IValidatorManager
  function setGlobalValidatorConfig(SetGlobalValidatorConfigRequest calldata request) external onlyOwner {
    _setGlobalValidatorConfig(_getStorageV1(), request);
  }

  // ===================================== INTERNAL FUNCTIONS ===================================== //

  function _validatorInfoAt(StorageV1 storage $, address valAddr, uint256 epoch)
    internal
    view
    returns (ValidatorInfoResponse memory)
  {
    Validator storage info = _validator($, valAddr);

    uint256 commissionRate = info.rewardConfig.commissionRates.upperLookup(epoch.toUint96());

    ValidatorInfoResponse memory response = ValidatorInfoResponse({
      valAddr: info.valAddr,
      pubKey: info.pubKey,
      operator: info.operator,
      rewardManager: info.rewardManager,
      commissionRate: commissionRate,
      pendingCommissionRate: 0,
      pendingCommissionRateUpdateEpoch: 0,
      metadata: info.metadata
    });

    // apply pending rate
    if (info.rewardConfig.pendingCommissionRateUpdateEpoch <= epoch) {
      response.commissionRate = info.rewardConfig.pendingCommissionRate;
    } else {
      response.pendingCommissionRate = info.rewardConfig.pendingCommissionRate;
      response.pendingCommissionRateUpdateEpoch = info.rewardConfig.pendingCommissionRateUpdateEpoch;
    }

    // hard limit
    response.commissionRate =
      Math.max(response.commissionRate, $.globalValidatorConfig.minimumCommissionRates.upperLookup(epoch.toUint96()));

    return response;
  }

  function _setPermittedCollateralOwner(Validator storage validator, address collateralOwner, bool isPermitted)
    internal
  {
    require(collateralOwner != address(0), StdError.ZeroAddress('collateralOwner'));

    if (isPermitted) validator.permittedCollateralOwners.add(collateralOwner);
    else validator.permittedCollateralOwners.remove(collateralOwner);

    emit PermittedCollateralOwnerSet(validator.valAddr, collateralOwner, isPermitted);
  }

  function _setFee(StorageV1 storage $, uint256 fee_) internal {
    uint256 previousFee = $.fee;
    $.fee = fee_;
    emit FeeSet(previousFee, fee_);
  }

  function _setGlobalValidatorConfig(StorageV1 storage $, SetGlobalValidatorConfigRequest memory request) internal {
    require(
      0 <= request.minimumCommissionRate && request.minimumCommissionRate <= MAX_COMMISSION_RATE,
      StdError.InvalidParameter('minimumCommissionRate')
    );

    uint256 epoch = _epochFeeder.epoch();
    $.globalValidatorConfig.minimumCommissionRates.push(epoch.toUint96(), request.minimumCommissionRate.toUint160());
    $.globalValidatorConfig.commissionRateUpdateDelayEpoch = request.commissionRateUpdateDelayEpoch;
    $.globalValidatorConfig.initialValidatorDeposit = request.initialValidatorDeposit;
    $.globalValidatorConfig.collateralWithdrawalDelaySeconds = request.collateralWithdrawalDelaySeconds;

    emit GlobalValidatorConfigUpdated(request);
  }

  function _validator(StorageV1 storage $, address valAddr) internal view returns (Validator storage) {
    uint256 index = $.indexByValAddr[valAddr];
    require(index != 0, StdError.InvalidParameter('valAddr'));
    return $.validators[index];
  }

  function _createValidator(
    StorageV1 storage $,
    address valAddr,
    bytes memory pubKey,
    uint256 value,
    CreateValidatorRequest memory request
  ) internal returns (Validator storage) {
    _assertValidatorNotExists($, valAddr);

    GlobalValidatorConfig storage globalConfig = $.globalValidatorConfig;

    require(globalConfig.initialValidatorDeposit <= value, StdError.InvalidParameter('value'));
    require(
      globalConfig.minimumCommissionRates.latest() <= request.commissionRate
        && request.commissionRate <= MAX_COMMISSION_RATE,
      StdError.InvalidParameter('commissionRate')
    );

    // start from 1
    uint256 valIndex = ++$.validatorCount;

    uint256 epoch = _epochFeeder.epoch();

    Validator storage validator = $.validators[valIndex];
    validator.valAddr = valAddr;
    validator.operator = request.operator;
    validator.rewardManager = request.rewardManager;
    validator.pubKey = pubKey;
    validator.rewardConfig.commissionRates.push(epoch.toUint96(), request.commissionRate.toUint160());
    validator.metadata = request.metadata;

    $.indexByValAddr[valAddr] = valIndex;

    emit ValidatorCreated(valAddr, request.operator, pubKey, value, request);

    return validator;
  }

  /// @notice Burns the fee amount of ETH
  /// @param $ The storage pointer
  /// @return netMsgValue The remaining ETH after fee burn
  function _burnFee(StorageV1 storage $) internal returns (uint256 netMsgValue) {
    uint256 fee_ = $.fee;
    require(msg.value >= fee_, IValidatorManager__InsufficientFee());

    if (fee_ > 0) {
      SafeTransferLib.safeTransferETH(payable(address(0)), fee_);
      emit FeePaid(fee_);
    }

    unchecked {
      return msg.value - fee_;
    }
  }

  function _assertValidatorNotExists(StorageV1 storage $, address valAddr) internal view {
    require($.indexByValAddr[valAddr] == 0, StdError.InvalidParameter('valAddr'));
  }

  function _assertOperator(Validator storage validator) internal view {
    require(validator.operator == _msgSender(), StdError.Unauthorized());
  }

  function _assertOperatorOrValidator(Validator storage validator) internal view {
    require(validator.operator == _msgSender() || validator.valAddr == _msgSender(), StdError.Unauthorized());
  }

  // ========== UUPS ========== //

  function _authorizeUpgrade(address) internal override onlyOwner { }
}
