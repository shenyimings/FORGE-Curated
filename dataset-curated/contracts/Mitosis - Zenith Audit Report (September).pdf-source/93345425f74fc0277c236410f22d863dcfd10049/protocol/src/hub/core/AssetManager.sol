// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Time } from '@oz/utils/types/Time.sol';
import { AccessControlEnumerableUpgradeable } from '@ozu/access/extensions/AccessControlEnumerableUpgradeable.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IAssetManager } from '../../interfaces/hub/core/IAssetManager.sol';
import { IAssetManagerEntrypoint } from '../../interfaces/hub/core/IAssetManagerEntrypoint.sol';
import { IHubAsset } from '../../interfaces/hub/core/IHubAsset.sol';
import { ITreasury } from '../../interfaces/hub/reward/ITreasury.sol';
import { IVLFVault } from '../../interfaces/hub/vlf/IVLFVault.sol';
import { IVLFVaultFactory } from '../../interfaces/hub/vlf/IVLFVaultFactory.sol';
import { Pausable } from '../../lib/Pausable.sol';
import { StdError } from '../../lib/StdError.sol';
import { Versioned } from '../../lib/Versioned.sol';
import { AssetManagerStorageV1 } from './AssetManagerStorageV1.sol';

contract AssetManager is
  IAssetManager,
  Pausable,
  AccessControlEnumerableUpgradeable,
  UUPSUpgradeable,
  AssetManagerStorageV1,
  Versioned
{
  // ============================ NOTE: ROLE DEFINITIONS ============================ //

  /// @dev Role for managing liquidity thresholds and caps
  bytes32 public constant LIQUIDITY_MANAGER_ROLE = keccak256('LIQUIDITY_MANAGER_ROLE');

  modifier onlyOwner() {
    _checkRole(DEFAULT_ADMIN_ROLE);
    _;
  }

  //=========== NOTE: INITIALIZATION FUNCTIONS ===========//

  constructor() {
    _disableInitializers();
  }

  function initialize(address owner_, address treasury_) public initializer {
    __Pausable_init();
    __AccessControl_init();
    __AccessControlEnumerable_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, owner_);

    _setTreasury(_getStorageV1(), treasury_);
  }

  //=========== NOTE: VIEW FUNCTIONS ===========//

  function isOwner(address account) external view returns (bool) {
    return hasRole(DEFAULT_ADMIN_ROLE, account);
  }

  function isLiquidityManager(address account) external view returns (bool) {
    return hasRole(LIQUIDITY_MANAGER_ROLE, account);
  }

  //=========== NOTE: QUOTE FUNCTIONS ===========//

  function quoteInitializeAsset(uint256 chainId, address branchAsset) external view returns (uint256) {
    StorageV1 storage $ = _getStorageV1();
    return $.entrypoint.quoteInitializeAsset(chainId, branchAsset);
  }

  function quoteInitializeVLF(uint256 chainId, address vlfVault, address branchAsset) external view returns (uint256) {
    StorageV1 storage $ = _getStorageV1();
    return $.entrypoint.quoteInitializeVLF(chainId, vlfVault, branchAsset);
  }

  function quoteWithdraw(uint256 chainId, address branchAsset, address to, uint256 amount)
    external
    view
    returns (uint256)
  {
    StorageV1 storage $ = _getStorageV1();
    return $.entrypoint.quoteWithdraw(chainId, branchAsset, to, amount);
  }

  function quoteAllocateVLF(uint256 chainId, address vlfVault, uint256 amount) external view returns (uint256) {
    StorageV1 storage $ = _getStorageV1();
    return $.entrypoint.quoteAllocateVLF(chainId, vlfVault, amount);
  }

  //=========== NOTE: ASSET FUNCTIONS ===========//

  function deposit(uint256 chainId, address branchAsset, address to, uint256 amount) external whenNotPaused {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyEntrypoint($);
    _assertBranchAssetPairExist($, chainId, branchAsset);

    address hubAsset = _branchAssetState($, chainId, branchAsset).hubAsset;
    amount = _scaleToHubDecimals(
      amount, _hubAssetState($, hubAsset, chainId).branchAssetDecimals, IHubAsset(hubAsset).decimals()
    );

    _mint($, chainId, hubAsset, to, amount);

    emit Deposited(chainId, hubAsset, to, amount);
  }

  function depositWithSupplyVLF(uint256 chainId, address branchAsset, address to, address vlfVault, uint256 amount)
    external
    whenNotPaused
  {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyEntrypoint($);
    _assertBranchAssetPairExist($, chainId, branchAsset);
    _assertVLFInitialized($, chainId, vlfVault);

    // NOTE: We don't need to check if the vlfVault is registered instance of VLFVaultFactory

    address hubAsset = _branchAssetState($, chainId, branchAsset).hubAsset;

    amount = _scaleToHubDecimals(
      amount, _hubAssetState($, hubAsset, chainId).branchAssetDecimals, IHubAsset(hubAsset).decimals()
    );

    uint256 supplyAmount = 0;

    if (hubAsset != IVLFVault(vlfVault).asset()) {
      // just transfer hubAsset if it's not the same as the VLFVault's asset
      _mint($, chainId, hubAsset, to, amount);
    } else {
      _mint($, chainId, hubAsset, address(this), amount);

      uint256 maxAssets = IVLFVault(vlfVault).maxDepositFromChainId(to, chainId);
      supplyAmount = amount < maxAssets ? amount : maxAssets;

      IHubAsset(hubAsset).approve(vlfVault, supplyAmount);
      IVLFVault(vlfVault).depositFromChainId(supplyAmount, to, chainId);

      // transfer remaining hub assets to `to` because there could be remaining hub assets due to the cap of VLFVault.
      if (supplyAmount < amount) IHubAsset(hubAsset).transfer(to, amount - supplyAmount);
    }

    emit DepositedWithSupplyVLF(chainId, hubAsset, to, vlfVault, amount, supplyAmount);
  }

  function withdraw(uint256 chainId, address hubAsset, address to, uint256 amount) external payable whenNotPaused {
    StorageV1 storage $ = _getStorageV1();

    require(to != address(0), StdError.ZeroAddress('to'));
    require(amount != 0, StdError.ZeroAmount());

    address branchAsset = _hubAssetState($, hubAsset, chainId).branchAsset;
    _assertBranchAssetPairExist($, chainId, branchAsset);

    uint256 amountBranchUnit;
    (amountBranchUnit, amount) = _scaleToBranchDecimals(
      amount, _hubAssetState($, hubAsset, chainId).branchAssetDecimals, IHubAsset(hubAsset).decimals()
    );

    _assertBranchAvailableLiquiditySufficient($, hubAsset, chainId, amount);
    _assertBranchLiquidityThresholdSatisfied($, hubAsset, chainId, amount);

    _burn($, chainId, hubAsset, _msgSender(), amount);
    $.entrypoint.withdraw{ value: msg.value }(chainId, branchAsset, to, amountBranchUnit);

    emit Withdrawn(chainId, hubAsset, to, amount, amountBranchUnit);
  }

  //=========== NOTE: VLF FUNCTIONS ===========//

  /// @dev only strategist
  function allocateVLF(uint256 chainId, address vlfVault, uint256 amount) external payable whenNotPaused {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyStrategist($, vlfVault);
    _assertVLFInitialized($, chainId, vlfVault);

    address hubAsset = IVLFVault(vlfVault).asset();
    HubAssetState storage hubAssetState = _hubAssetState($, hubAsset, chainId);

    uint256 amountBranchUnit;
    (amountBranchUnit, amount) =
      _scaleToBranchDecimals(amount, hubAssetState.branchAssetDecimals, IHubAsset(hubAsset).decimals());

    uint256 idle = _vlfIdle($, vlfVault);
    require(amount <= idle, IAssetManager__VLFLiquidityInsufficient(vlfVault));

    $.entrypoint.allocateVLF{ value: msg.value }(chainId, vlfVault, amountBranchUnit);

    _assertBranchAvailableLiquiditySufficient($, hubAsset, chainId, amount);
    hubAssetState.branchAllocated += amount;
    $.vlfStates[vlfVault].allocation += amount;

    emit VLFAllocated(_msgSender(), chainId, vlfVault, amount, amountBranchUnit);
  }

  /// @dev only entrypoint
  function deallocateVLF(uint256 chainId, address vlfVault, uint256 amount) external whenNotPaused {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyEntrypoint($);

    address hubAsset = IVLFVault(vlfVault).asset();
    HubAssetState storage hubAssetState = _hubAssetState($, hubAsset, chainId);

    amount = _scaleToHubDecimals(amount, hubAssetState.branchAssetDecimals, IHubAsset(hubAsset).decimals());

    hubAssetState.branchAllocated -= amount;
    $.vlfStates[vlfVault].allocation -= amount;

    emit VLFDeallocated(chainId, vlfVault, amount);
  }

  /// @dev only strategist
  function reserveVLF(address vlfVault, uint256 claimCount) external whenNotPaused {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyStrategist($, vlfVault);

    uint256 idle = _vlfIdle($, vlfVault);
    (, uint256 simulatedTotalReservedAssets) = $.reclaimQueue.previewSync(vlfVault, claimCount);
    require(simulatedTotalReservedAssets > 0, IAssetManager__NothingToVLFReserve(vlfVault));
    require(simulatedTotalReservedAssets <= idle, IAssetManager__VLFLiquidityInsufficient(vlfVault));

    (uint256 totalReservedShares, uint256 totalReservedAssets) = $.reclaimQueue.sync(_msgSender(), vlfVault, claimCount);

    emit VLFReserved(_msgSender(), vlfVault, claimCount, totalReservedShares, totalReservedAssets);
  }

  /// @dev only entrypoint
  function settleVLFYield(uint256 chainId, address vlfVault, uint256 amount) external whenNotPaused {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyEntrypoint($);

    // Increase VLFVault's shares value.
    address hubAsset = IVLFVault(vlfVault).asset();
    HubAssetState storage hubAssetState = _hubAssetState($, hubAsset, chainId);

    amount = _scaleToHubDecimals(amount, hubAssetState.branchAssetDecimals, IHubAsset(hubAsset).decimals());

    _mint($, chainId, hubAsset, address(vlfVault), amount);

    hubAssetState.branchAllocated += amount;
    $.vlfStates[vlfVault].allocation += amount;

    emit VLFRewardSettled(chainId, vlfVault, hubAsset, amount);
  }

  /// @dev only entrypoint
  function settleVLFLoss(uint256 chainId, address vlfVault, uint256 amount) external whenNotPaused {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyEntrypoint($);

    // Decrease VLFVault's shares value.
    address hubAsset = IVLFVault(vlfVault).asset();
    HubAssetState storage hubAssetState = _hubAssetState($, hubAsset, chainId);

    amount = _scaleToHubDecimals(amount, hubAssetState.branchAssetDecimals, IHubAsset(hubAsset).decimals());

    _burn($, chainId, hubAsset, vlfVault, amount);

    hubAssetState.branchAllocated -= amount;
    $.vlfStates[vlfVault].allocation -= amount;

    emit VLFLossSettled(chainId, vlfVault, hubAsset, amount);
  }

  /// @dev only entrypoint
  function settleVLFExtraRewards(uint256 chainId, address vlfVault, address branchReward, uint256 amount)
    external
    whenNotPaused
  {
    StorageV1 storage $ = _getStorageV1();

    _assertOnlyEntrypoint($);
    _assertBranchAssetPairExist($, chainId, branchReward);
    _assertTreasurySet($);

    address hubAsset = _branchAssetState($, chainId, branchReward).hubAsset;
    HubAssetState storage hubAssetState = _hubAssetState($, hubAsset, chainId);

    amount = _scaleToHubDecimals(amount, hubAssetState.branchAssetDecimals, IHubAsset(hubAsset).decimals());

    _mint($, chainId, hubAsset, address(this), amount);
    emit VLFRewardSettled(chainId, vlfVault, hubAsset, amount);

    IHubAsset(hubAsset).approve(address($.treasury), amount);
    $.treasury.storeRewards(vlfVault, hubAsset, amount);
  }

  function setBranchLiquidityThreshold(uint256 chainId, address hubAsset, uint256 threshold)
    external
    onlyRole(LIQUIDITY_MANAGER_ROLE)
  {
    _setBranchLiquidityThreshold(_getStorageV1(), hubAsset, chainId, threshold);
  }

  function setBranchLiquidityThreshold(
    uint256[] calldata chainIds,
    address[] calldata hubAssets,
    uint256[] calldata thresholds
  ) external onlyRole(LIQUIDITY_MANAGER_ROLE) {
    require(chainIds.length == hubAssets.length, StdError.InvalidParameter('hubAssets'));
    require(chainIds.length == thresholds.length, StdError.InvalidParameter('thresholds'));

    StorageV1 storage $ = _getStorageV1();
    for (uint256 i = 0; i < chainIds.length; i++) {
      _setBranchLiquidityThreshold($, hubAssets[i], chainIds[i], thresholds[i]);
    }
  }

  //=========== NOTE: OWNABLE FUNCTIONS ===========//

  function _authorizeUpgrade(address) internal override onlyOwner { }

  function _authorizePause(address) internal view override onlyOwner { }

  function initializeAsset(uint256 chainId, address hubAsset) external payable onlyOwner whenNotPaused {
    _assertOnlyContract(hubAsset, 'hubAsset');

    StorageV1 storage $ = _getStorageV1();

    HubAssetState storage hubAssetState = _hubAssetState($, hubAsset, chainId);
    address branchAsset = hubAssetState.branchAsset;
    uint8 branchAssetDecimals = hubAssetState.branchAssetDecimals;
    _assertBranchAssetPairExist($, chainId, branchAsset);

    $.entrypoint.initializeAsset{ value: msg.value }(chainId, branchAsset);
    emit AssetInitialized(hubAsset, chainId, branchAsset, branchAssetDecimals);
  }

  function initializeVLF(uint256 chainId, address vlfVault) external payable onlyOwner whenNotPaused {
    StorageV1 storage $ = _getStorageV1();
    _assertVLFVaultFactorySet($);
    _assertVLFVaultInstance($, vlfVault);

    address hubAsset = IVLFVault(vlfVault).asset();
    address branchAsset = _hubAssetState($, hubAsset, chainId).branchAsset;
    _assertBranchAssetPairExist($, chainId, branchAsset);

    _assertVLFNotInitialized($, chainId, vlfVault);
    $.vlfInitialized[chainId][vlfVault] = true;

    $.entrypoint.initializeVLF{ value: msg.value }(chainId, vlfVault, branchAsset);
    emit VLFInitialized(hubAsset, chainId, vlfVault, branchAsset);
  }

  function setAssetPair(address hubAsset, uint256 branchChainId, address branchAsset, uint8 branchAssetDecimals)
    external
    onlyOwner
  {
    StorageV1 storage $ = _getStorageV1();
    _assertHubAssetFactorySet($);
    _assertHubAssetInstance($, hubAsset);
    _assertBranchAssetPairNotExist($, branchChainId, branchAsset);

    require(IHubAsset(hubAsset).decimals() >= branchAssetDecimals, StdError.InvalidParameter('branchAssetDecimals'));

    HubAssetState storage hubAssetState = _hubAssetState($, hubAsset, branchChainId);
    hubAssetState.branchAsset = branchAsset;
    hubAssetState.branchAssetDecimals = branchAssetDecimals;
    _branchAssetState($, branchChainId, branchAsset).hubAsset = hubAsset;
    emit AssetPairSet(hubAsset, branchChainId, branchAsset, branchAssetDecimals);
  }

  function setEntrypoint(address entrypoint_) external onlyOwner {
    _setEntrypoint(_getStorageV1(), entrypoint_);
  }

  function setReclaimQueue(address reclaimQueue_) external onlyOwner {
    _setReclaimQueue(_getStorageV1(), reclaimQueue_);
  }

  function setTreasury(address treasury_) external onlyOwner {
    _setTreasury(_getStorageV1(), treasury_);
  }

  function setHubAssetFactory(address hubAssetFactory_) external onlyOwner {
    _setHubAssetFactory(_getStorageV1(), hubAssetFactory_);
  }

  function setVLFVaultFactory(address vlfVaultFactory_) external onlyOwner {
    _setVLFVaultFactory(_getStorageV1(), vlfVaultFactory_);
  }

  function setStrategist(address vlfVault, address strategist) external onlyOwner {
    _setStrategist(_getStorageV1(), vlfVault, strategist);
  }

  //=========== NOTE: INTERNAL FUNCTIONS ===========//

  function _scaleToHubDecimals(uint256 amountBranchUnit, uint8 branchAssetDecimals, uint8 hubAssetDecimals)
    internal
    pure
    returns (uint256)
  {
    require(hubAssetDecimals >= branchAssetDecimals, StdError.NotSupported());
    return amountBranchUnit * (10 ** (hubAssetDecimals - branchAssetDecimals));
  }

  function _scaleToBranchDecimals(uint256 amountHubUnit, uint8 branchAssetDecimals, uint8 hubAssetDecimals)
    internal
    pure
    returns (uint256 amountBranchUnit, uint256 adjustedAmountHubUnit)
  {
    require(hubAssetDecimals >= branchAssetDecimals, StdError.NotSupported());
    amountBranchUnit = amountHubUnit / (10 ** (hubAssetDecimals - branchAssetDecimals));
    // Convert back to hub decimals for precision loss detection.
    adjustedAmountHubUnit = amountBranchUnit * (10 ** (hubAssetDecimals - branchAssetDecimals));
  }

  function _mint(StorageV1 storage $, uint256 chainId, address asset, address account, uint256 amount) internal {
    IHubAsset(asset).mint(account, amount);
    _hubAssetState($, asset, chainId).branchLiquidity += amount;
  }

  function _burn(StorageV1 storage $, uint256 chainId, address asset, address account, uint256 amount) internal {
    IHubAsset(asset).burn(account, amount);
    _hubAssetState($, asset, chainId).branchLiquidity -= amount;
  }

  //=========== NOTE: ASSERTIONS ===========//

  function _assertOnlyContract(address addr, string memory paramName) internal view {
    require(addr.code.length > 0, StdError.InvalidParameter(paramName));
  }

  function _assertBranchAssetPairNotExist(StorageV1 storage $, uint256 chainId, address branchAsset) internal view {
    require(
      _branchAssetState($, chainId, branchAsset).hubAsset == address(0),
      IAssetManagerStorageV1__BranchAssetPairNotExist(chainId, branchAsset)
    );
  }
}
