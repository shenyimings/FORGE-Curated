// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { StandardHookMetadata } from '@hpl/hooks/libs/StandardHookMetadata.sol';
import { IMessageRecipient } from '@hpl/interfaces/IMessageRecipient.sol';

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { GasRouter } from '../external/hyperlane/GasRouter.sol';
import { IMitosisVault } from '../interfaces/branch/IMitosisVault.sol';
import { IMitosisVaultEntrypoint } from '../interfaces/branch/IMitosisVaultEntrypoint.sol';
import { Conv } from '../lib/Conv.sol';
import { StdError } from '../lib/StdError.sol';
import { Versioned } from '../lib/Versioned.sol';
import '../message/Message.sol';

contract MitosisVaultEntrypoint is
  IMitosisVaultEntrypoint,
  IMessageRecipient,
  Ownable2StepUpgradeable,
  GasRouter,
  UUPSUpgradeable,
  Versioned
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
    __UUPSUpgradeable_init();

    __Ownable_init(_msgSender());
    __Ownable2Step_init();

    _MailboxClient_initialize(hook, ism);
    _transferOwnership(owner_);
    _enrollRemoteRouter(_mitosisDomain, _mitosisAddr);
  }

  function vault() external view returns (IMitosisVault) {
    return _vault;
  }

  function mitosisDomain() external view returns (uint32) {
    return _mitosisDomain;
  }

  function mitosisAddr() external view returns (bytes32) {
    return _mitosisAddr;
  }

  function quoteDeposit(address asset, address to, uint256 amount) external view returns (uint256) {
    bytes memory enc = MsgDeposit({ asset: asset.toBytes32(), to: to.toBytes32(), amount: amount }).encode();
    return _quoteToMitosis(enc, MsgType.MsgDeposit);
  }

  function quoteDepositWithSupplyVLF(address asset, address to, address hubVLFVault, uint256 amount)
    external
    view
    returns (uint256)
  {
    bytes memory enc = MsgDepositWithSupplyVLF({
      asset: asset.toBytes32(),
      to: to.toBytes32(),
      vlfVault: hubVLFVault.toBytes32(),
      amount: amount
    }).encode();
    return _quoteToMitosis(enc, MsgType.MsgDepositWithSupplyVLF);
  }

  function quoteDeallocateVLF(address hubVLFVault, uint256 amount) external view returns (uint256) {
    bytes memory enc = MsgDeallocateVLF({ vlfVault: hubVLFVault.toBytes32(), amount: amount }).encode();
    return _quoteToMitosis(enc, MsgType.MsgDeallocateVLF);
  }

  function quoteSettleVLFYield(address hubVLFVault, uint256 amount) external view returns (uint256) {
    bytes memory enc = MsgSettleVLFYield({ vlfVault: hubVLFVault.toBytes32(), amount: amount }).encode();
    return _quoteToMitosis(enc, MsgType.MsgSettleVLFYield);
  }

  function quoteSettleVLFLoss(address hubVLFVault, uint256 amount) external view returns (uint256) {
    bytes memory enc = MsgSettleVLFLoss({ vlfVault: hubVLFVault.toBytes32(), amount: amount }).encode();
    return _quoteToMitosis(enc, MsgType.MsgSettleVLFLoss);
  }

  function quoteSettleVLFExtraRewards(address hubVLFVault, address reward, uint256 amount)
    external
    view
    returns (uint256)
  {
    bytes memory enc = MsgSettleVLFExtraRewards({
      vlfVault: hubVLFVault.toBytes32(),
      reward: reward.toBytes32(),
      amount: amount
    }).encode();
    return _quoteToMitosis(enc, MsgType.MsgSettleVLFExtraRewards);
  }

  function _quoteToMitosis(bytes memory enc, MsgType msgType) internal view returns (uint256) {
    uint96 action = uint96(msgType);
    uint256 fee = _GasRouter_quoteDispatch(_mitosisDomain, action, enc, address(hook()));
    return fee;
  }

  //=========== NOTE: VAULT FUNCTIONS ===========//

  function deposit(address asset, address to, uint256 amount, address refundTo) external payable onlyVault {
    bytes memory enc = MsgDeposit({ asset: asset.toBytes32(), to: to.toBytes32(), amount: amount }).encode();
    _dispatchToMitosis(enc, MsgType.MsgDeposit, refundTo);
  }

  function depositWithSupplyVLF(address asset, address to, address hubVLFVault, uint256 amount, address refundTo)
    external
    payable
    onlyVault
  {
    bytes memory enc = MsgDepositWithSupplyVLF({
      asset: asset.toBytes32(),
      to: to.toBytes32(),
      vlfVault: hubVLFVault.toBytes32(),
      amount: amount
    }).encode();
    _dispatchToMitosis(enc, MsgType.MsgDepositWithSupplyVLF, refundTo);
  }

  function deallocateVLF(address hubVLFVault, uint256 amount, address refundTo) external payable onlyVault {
    bytes memory enc = MsgDeallocateVLF({ vlfVault: hubVLFVault.toBytes32(), amount: amount }).encode();
    _dispatchToMitosis(enc, MsgType.MsgDeallocateVLF, refundTo);
  }

  function settleVLFYield(address hubVLFVault, uint256 amount, address refundTo) external payable onlyVault {
    bytes memory enc = MsgSettleVLFYield({ vlfVault: hubVLFVault.toBytes32(), amount: amount }).encode();
    _dispatchToMitosis(enc, MsgType.MsgSettleVLFYield, refundTo);
  }

  function settleVLFLoss(address hubVLFVault, uint256 amount, address refundTo) external payable onlyVault {
    bytes memory enc = MsgSettleVLFLoss({ vlfVault: hubVLFVault.toBytes32(), amount: amount }).encode();
    _dispatchToMitosis(enc, MsgType.MsgSettleVLFLoss, refundTo);
  }

  function settleVLFExtraRewards(address hubVLFVault, address reward, uint256 amount, address refundTo)
    external
    payable
    onlyVault
  {
    bytes memory enc = MsgSettleVLFExtraRewards({
      vlfVault: hubVLFVault.toBytes32(),
      reward: reward.toBytes32(),
      amount: amount
    }).encode();
    _dispatchToMitosis(enc, MsgType.MsgSettleVLFExtraRewards, refundTo);
  }

  function _dispatchToMitosis(bytes memory enc, MsgType msgType, address refundTo) internal {
    uint96 action = uint96(msgType);

    uint256 gasLimit = _getHplGasRouterStorage().destinationGas[_mitosisDomain][action];
    require(gasLimit > 0, GasRouter__GasLimitNotSet(_mitosisDomain, action));

    uint256 fee = _GasRouter_quoteDispatch(_mitosisDomain, action, enc, address(hook()));
    _Router_dispatch(
      _mitosisDomain,
      fee,
      enc,
      StandardHookMetadata.formatMetadata(uint256(0), gasLimit, refundTo, bytes('')),
      address(hook())
    );
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

    if (msgType == MsgType.MsgInitializeVLF) {
      MsgInitializeVLF memory decoded = msg_.decodeInitializeVLF();
      _vault.initializeVLF(decoded.vlfVault.toAddress(), decoded.asset.toAddress());
    }

    if (msgType == MsgType.MsgAllocateVLF) {
      MsgAllocateVLF memory decoded = msg_.decodeAllocateVLF();
      _vault.allocateVLF(decoded.vlfVault.toAddress(), decoded.amount);
    }
  }

  //=========== NOTE: OWNABLE FUNCTIONS ===========//

  function _authorizeUpgrade(address) internal override onlyOwner { }

  function _authorizeConfigureGas(address) internal override onlyOwner { }

  function _authorizeConfigureRoute(address) internal override onlyOwner { }

  function _authorizeManageMailbox(address) internal override onlyOwner { }
}
