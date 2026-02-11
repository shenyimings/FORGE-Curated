// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IMessageRecipient } from '@hpl/interfaces/IMessageRecipient.sol';

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { OwnableUpgradeable } from '@ozu/access/OwnableUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { GasRouter } from '../external/hyperlane/GasRouter.sol';
import { IMitosisVault } from '../interfaces/branch/IMitosisVault.sol';
import { IMitosisVaultEntrypoint } from '../interfaces/branch/IMitosisVaultEntrypoint.sol';
import { Conv } from '../lib/Conv.sol';
import { StdError } from '../lib/StdError.sol';
import '../message/Message.sol';

contract MitosisVaultEntrypoint is
  IMitosisVaultEntrypoint,
  IMessageRecipient,
  GasRouter,
  Ownable2StepUpgradeable,
  UUPSUpgradeable
{
  using Message for *;
  using Conv for *;

  IMitosisVault internal immutable _vault;
  uint32 internal immutable _mitosisDomain;
  bytes32 internal immutable _mitosisAddr; // Hub.AssetManagerEntrypoint

  modifier onlyVault() {
    require(_msgSender() == address(_vault), StdError.InvalidAddress('vault'));
    _;
  }

  constructor(address mailbox, address vault_, uint32 mitosisDomain_, bytes32 mitosisAddr_)
    GasRouter(mailbox)
    initializer
  {
    _vault = IMitosisVault(vault_);
    _mitosisDomain = mitosisDomain_;
    _mitosisAddr = mitosisAddr_;
  }

  function initialize(address owner_, address hook, address ism) public initializer {
    _MailboxClient_initialize(hook, ism, owner_);
    __Ownable2Step_init();
    __UUPSUpgradeable_init();

    _enrollRemoteRouter(_mitosisDomain, _mitosisAddr);
  }

  receive() external payable { }

  function vault() external view returns (IMitosisVault) {
    return _vault;
  }

  function mitosisDomain() external view returns (uint32) {
    return _mitosisDomain;
  }

  function mitosisAddr() external view returns (bytes32) {
    return _mitosisAddr;
  }

  //=========== NOTE: VAULT FUNCTIONS ===========//

  function deposit(address asset, address to, uint256 amount) external onlyVault {
    bytes memory enc = MsgDeposit({ asset: asset.toBytes32(), to: to.toBytes32(), amount: amount }).encode();
    _dispatchToMitosis(enc);
  }

  function depositWithSupplyMatrix(address asset, address to, address hubMatrixVault, uint256 amount)
    external
    onlyVault
  {
    bytes memory enc = MsgDepositWithSupplyMatrix({
      asset: asset.toBytes32(),
      to: to.toBytes32(),
      matrixVault: hubMatrixVault.toBytes32(),
      amount: amount
    }).encode();
    _dispatchToMitosis(enc);
  }

  function depositWithSupplyEOL(address asset, address to, address hubEOLVault, uint256 amount) external onlyVault {
    bytes memory enc = MsgDepositWithSupplyEOL({
      asset: asset.toBytes32(),
      to: to.toBytes32(),
      eolVault: hubEOLVault.toBytes32(),
      amount: amount
    }).encode();
    _dispatchToMitosis(enc);
  }

  function deallocateMatrix(address hubMatrixVault, uint256 amount) external onlyVault {
    bytes memory enc = MsgDeallocateMatrix({ matrixVault: hubMatrixVault.toBytes32(), amount: amount }).encode();
    _dispatchToMitosis(enc);
  }

  function settleMatrixYield(address hubMatrixVault, uint256 amount) external onlyVault {
    bytes memory enc = MsgSettleMatrixYield({ matrixVault: hubMatrixVault.toBytes32(), amount: amount }).encode();
    _dispatchToMitosis(enc);
  }

  function settleMatrixLoss(address hubMatrixVault, uint256 amount) external onlyVault {
    bytes memory enc = MsgSettleMatrixLoss({ matrixVault: hubMatrixVault.toBytes32(), amount: amount }).encode();
    _dispatchToMitosis(enc);
  }

  function settleMatrixExtraRewards(address hubMatrixVault, address reward, uint256 amount) external onlyVault {
    bytes memory enc = MsgSettleMatrixExtraRewards({
      matrixVault: hubMatrixVault.toBytes32(),
      reward: reward.toBytes32(),
      amount: amount
    }).encode();
    _dispatchToMitosis(enc);
  }

  function _dispatchToMitosis(bytes memory enc) internal {
    uint256 fee = _GasRouter_quoteDispatch(_mitosisDomain, enc, address(hook()));
    _GasRouter_dispatch(_mitosisDomain, fee, enc, address(hook()));
  }

  //=========== NOTE: HANDLER FUNCTIONS ===========//

  function _handle(uint32 origin, bytes32 sender, bytes calldata msg_) internal override {
    require(origin == _mitosisDomain && sender == _mitosisAddr, StdError.Unauthorized());

    MsgType msgType = msg_.msgType();

    if (msgType == MsgType.MsgInitializeAsset) {
      MsgInitializeAsset memory decoded = msg_.decodeInitializeAsset();
      _vault.initializeAsset(decoded.asset.toAddress());
    }

    if (msgType == MsgType.MsgWithdraw) {
      MsgWithdraw memory decoded = msg_.decodeWithdraw();
      _vault.withdraw(decoded.asset.toAddress(), decoded.to.toAddress(), decoded.amount);
    }

    if (msgType == MsgType.MsgInitializeMatrix) {
      MsgInitializeMatrix memory decoded = msg_.decodeInitializeMatrix();
      _vault.initializeMatrix(decoded.matrixVault.toAddress(), decoded.asset.toAddress());
    }

    if (msgType == MsgType.MsgAllocateMatrix) {
      MsgAllocateMatrix memory decoded = msg_.decodeAllocateMatrix();
      _vault.allocateMatrix(decoded.matrixVault.toAddress(), decoded.amount);
    }

    if (msgType == MsgType.MsgInitializeEOL) {
      MsgInitializeEOL memory decoded = msg_.decodeInitializeEOL();
      _vault.initializeEOL(decoded.eolVault.toAddress(), decoded.asset.toAddress());
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
