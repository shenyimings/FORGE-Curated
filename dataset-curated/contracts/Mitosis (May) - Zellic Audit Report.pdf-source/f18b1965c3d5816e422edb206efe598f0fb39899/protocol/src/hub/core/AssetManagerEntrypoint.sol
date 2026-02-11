// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IMessageRecipient } from '@hpl/interfaces/IMessageRecipient.sol';

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { OwnableUpgradeable } from '@ozu/access/OwnableUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { GasRouter } from '../../external/hyperlane/GasRouter.sol';
import { IAssetManager } from '../../interfaces/hub/core/IAssetManager.sol';
import { IAssetManagerEntrypoint } from '../../interfaces/hub/core/IAssetManagerEntrypoint.sol';
import { ICrossChainRegistry } from '../../interfaces/hub/cross-chain/ICrossChainRegistry.sol';
import { Conv } from '../../lib/Conv.sol';
import { StdError } from '../../lib/StdError.sol';
import '../../message/Message.sol';
import { AssetManager } from './AssetManager.sol';

contract AssetManagerEntrypoint is
  IAssetManagerEntrypoint,
  IMessageRecipient,
  GasRouter,
  Ownable2StepUpgradeable,
  UUPSUpgradeable
{
  using Message for *;
  using Conv for *;

  IAssetManager internal immutable _assetManager;
  ICrossChainRegistry internal immutable _ccRegistry;

  modifier onlyAssetManager() {
    require(_msgSender() == address(_assetManager), StdError.InvalidAddress('AssetManager'));
    _;
  }

  modifier onlyDispatchable(uint256 chainId) {
    require(_ccRegistry.isRegisteredChain(chainId), ICrossChainRegistry.ICrossChainRegistry__NotRegistered());
    require(
      _ccRegistry.mitosisVaultEntrypointEnrolled(chainId),
      ICrossChainRegistry.ICrossChainRegistry__MitosisVaultEntrypointNotEnrolled()
    );
    _;
  }

  constructor(address mailbox, address assetManager_, address ccRegistry_) GasRouter(mailbox) initializer {
    _assetManager = IAssetManager(assetManager_);
    _ccRegistry = ICrossChainRegistry(ccRegistry_);
  }

  function initialize(address owner_, address hook, address ism) public initializer {
    _MailboxClient_initialize(hook, ism, owner_);
    __Ownable2Step_init();
    __UUPSUpgradeable_init();
  }

  receive() external payable { }

  function assetManager() external view returns (IAssetManager) {
    return _assetManager;
  }

  function branchDomain(uint256 chainId) external view returns (uint32) {
    return _ccRegistry.hyperlaneDomain(chainId);
  }

  function branchMitosisVault(uint256 chainId) external view returns (address) {
    return _ccRegistry.mitosisVault(chainId);
  }

  function branchMitosisVaultEntrypoint(uint256 chainId) external view returns (address) {
    return _ccRegistry.mitosisVaultEntrypoint(chainId);
  }

  //=========== NOTE: ROUTER OVERRIDES ============//

  function enrollRemoteRouter(uint32 domain_, bytes32 router_) external override {
    require(_msgSender() == owner() || _msgSender() == address(_ccRegistry), StdError.Unauthorized());
    _enrollRemoteRouter(domain_, router_);
  }

  function enrollRemoteRouters(uint32[] calldata domain_, bytes32[] calldata addresses_) external override {
    require(_msgSender() == owner() || _msgSender() == address(_ccRegistry), StdError.Unauthorized());
    require(domain_.length == addresses_.length, '!length');
    uint256 length = domain_.length;
    for (uint256 i = 0; i < length; i += 1) {
      _enrollRemoteRouter(domain_[i], addresses_[i]);
    }
  }

  function unenrollRemoteRouter(uint32 domain_) external override {
    require(_msgSender() == owner() || _msgSender() == address(_ccRegistry), StdError.Unauthorized());
    _unenrollRemoteRouter(domain_);
  }

  function unenrollRemoteRouters(uint32[] calldata domains_) external override {
    require(_msgSender() == owner() || _msgSender() == address(_ccRegistry), StdError.Unauthorized());
    uint256 length = domains_.length;
    for (uint256 i = 0; i < length; i += 1) {
      _unenrollRemoteRouter(domains_[i]);
    }
  }

  function setDestGas(GasRouterConfig[] calldata gasConfigs) external {
    require(_msgSender() == owner() || _msgSender() == address(_ccRegistry), StdError.Unauthorized());
    for (uint256 i = 0; i < gasConfigs.length; i += 1) {
      _setDestinationGas(gasConfigs[i].domain, gasConfigs[i].gas);
    }
  }

  function setDestGas(uint32 domain, uint256 gas) external {
    require(_msgSender() == owner() || _msgSender() == address(_ccRegistry), StdError.Unauthorized());
    _setDestinationGas(domain, gas);
  }

  //=========== NOTE: ASSETMANAGER FUNCTIONS ===========//

  function initializeAsset(uint256 chainId, address branchAsset) external onlyAssetManager onlyDispatchable(chainId) {
    bytes memory enc = MsgInitializeAsset({ asset: branchAsset.toBytes32() }).encode();
    _dispatchToBranch(chainId, enc);
  }

  function initializeMatrix(uint256 chainId, address matrixVault, address branchAsset)
    external
    onlyAssetManager
    onlyDispatchable(chainId)
  {
    bytes memory enc =
      MsgInitializeMatrix({ matrixVault: matrixVault.toBytes32(), asset: branchAsset.toBytes32() }).encode();
    _dispatchToBranch(chainId, enc);
  }

  function initializeEOL(uint256 chainId, address eolVault, address branchAsset)
    external
    onlyAssetManager
    onlyDispatchable(chainId)
  {
    bytes memory enc = MsgInitializeEOL({ eolVault: eolVault.toBytes32(), asset: branchAsset.toBytes32() }).encode();
    _dispatchToBranch(chainId, enc);
  }

  function withdraw(uint256 chainId, address branchAsset, address to, uint256 amount)
    external
    onlyAssetManager
    onlyDispatchable(chainId)
  {
    bytes memory enc = MsgWithdraw({ asset: branchAsset.toBytes32(), to: to.toBytes32(), amount: amount }).encode();
    _dispatchToBranch(chainId, enc);
  }

  function allocateMatrix(uint256 chainId, address matrixVault, uint256 amount)
    external
    onlyAssetManager
    onlyDispatchable(chainId)
  {
    bytes memory enc = MsgAllocateMatrix({ matrixVault: matrixVault.toBytes32(), amount: amount }).encode();
    _dispatchToBranch(chainId, enc);
  }

  function _dispatchToBranch(uint256 chainId, bytes memory enc) internal {
    uint32 hplDomain = _ccRegistry.hyperlaneDomain(chainId);

    uint256 fee = _GasRouter_quoteDispatch(hplDomain, enc, address(hook()));
    _GasRouter_dispatch(hplDomain, fee, enc, address(hook()));
  }

  //=========== NOTE: HANDLER FUNCTIONS ===========//

  function _handle(uint32 origin, bytes32 sender, bytes calldata msg_) internal override {
    uint256 chainId = _ccRegistry.chainId(origin);
    require(chainId != 0, ICrossChainRegistry.ICrossChainRegistry__NotRegistered());

    address entrypoint = _ccRegistry.mitosisVaultEntrypoint(chainId);
    require(sender.toAddress() == entrypoint, ICrossChainRegistry.ICrossChainRegistry__NotRegistered());

    MsgType msgType = msg_.msgType();

    if (msgType == MsgType.MsgDeposit) {
      MsgDeposit memory decoded = msg_.decodeDeposit();
      _assetManager.deposit(chainId, decoded.asset.toAddress(), decoded.to.toAddress(), decoded.amount);
      return;
    }

    if (msgType == MsgType.MsgDepositWithSupplyMatrix) {
      MsgDepositWithSupplyMatrix memory decoded = msg_.decodeDepositWithSupplyMatrix();
      _assetManager.depositWithSupplyMatrix(
        chainId, decoded.asset.toAddress(), decoded.to.toAddress(), decoded.matrixVault.toAddress(), decoded.amount
      );
      return;
    }

    if (msgType == MsgType.MsgDepositWithSupplyEOL) {
      MsgDepositWithSupplyEOL memory decoded = msg_.decodeDepositWithSupplyEOL();
      _assetManager.depositWithSupplyEOL(
        chainId, decoded.asset.toAddress(), decoded.to.toAddress(), decoded.eolVault.toAddress(), decoded.amount
      );
      return;
    }

    if (msgType == MsgType.MsgDeallocateMatrix) {
      MsgDeallocateMatrix memory decoded = msg_.decodeDeallocateMatrix();
      _assetManager.deallocateMatrix(chainId, decoded.matrixVault.toAddress(), decoded.amount);
      return;
    }

    if (msgType == MsgType.MsgSettleMatrixYield) {
      MsgSettleMatrixYield memory decoded = msg_.decodeSettleMatrixYield();
      _assetManager.settleMatrixYield(chainId, decoded.matrixVault.toAddress(), decoded.amount);
      return;
    }

    if (msgType == MsgType.MsgSettleMatrixLoss) {
      MsgSettleMatrixLoss memory decoded = msg_.decodeSettleMatrixLoss();
      _assetManager.settleMatrixLoss(chainId, decoded.matrixVault.toAddress(), decoded.amount);
      return;
    }

    if (msgType == MsgType.MsgSettleMatrixExtraRewards) {
      MsgSettleMatrixExtraRewards memory decoded = msg_.decodeSettleMatrixExtraRewards();
      _assetManager.settleMatrixExtraRewards(
        chainId, decoded.matrixVault.toAddress(), decoded.reward.toAddress(), decoded.amount
      );
      return;
    }
  }

  //=========== NOTE: OWNABLE FUNCTIONS ===========//

  function _authorizeUpgrade(address) internal override onlyOwner { }

  //=========== NOTE: OwnableUpgradeable & Ownable2StepUpgradeable

  function transferOwnership(address owner) public override(Ownable2StepUpgradeable, OwnableUpgradeable) {
    Ownable2StepUpgradeable.transferOwnership(owner);
  }

  function _transferOwnership(address owner) internal override(Ownable2StepUpgradeable, OwnableUpgradeable) {
    Ownable2StepUpgradeable._transferOwnership(owner);
  }
}
