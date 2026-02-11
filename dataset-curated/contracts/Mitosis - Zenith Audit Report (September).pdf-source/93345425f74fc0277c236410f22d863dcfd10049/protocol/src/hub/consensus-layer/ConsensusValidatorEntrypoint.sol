// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IConsensusValidatorEntrypoint } from '../../interfaces/hub/consensus-layer/IConsensusValidatorEntrypoint.sol';
import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { LibSecp256k1 } from '../../lib/LibSecp256k1.sol';
import { StdError } from '../../lib/StdError.sol';
import { Versioned } from '../../lib/Versioned.sol';

contract ConsensusValidatorEntrypoint is
  IConsensusValidatorEntrypoint,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  Versioned
{
  using ERC7201Utils for string;

  /// @custom:storage-location mitosis.storage.ConsensusValidatorEntrypoint
  struct Storage {
    mapping(address caller => bool) isPermittedCaller;
  }

  modifier onlyPermittedCaller() {
    require(_getStorage().isPermittedCaller[_msgSender()], StdError.Unauthorized());
    _;
  }

  /**
   * @notice Verifies that the given validator key is valid format which is a compressed 33-byte secp256k1 public key.
   */
  modifier verifyPubKey(bytes memory pubKey) {
    LibSecp256k1.verifyCmpPubkey(pubKey);
    _;
  }

  /**
   * @notice Verifies that the given validator key is valid format and corresponds to the expected address.
   */
  modifier verifyPubKeyWithAddress(bytes memory pubKey, address expectedAddress) {
    LibSecp256k1.verifyCmpPubkeyWithAddress(pubKey, expectedAddress);
    _;
  }

  // =========================== NOTE: STORAGE DEFINITIONS =========================== //

  string private constant _NAMESPACE = 'mitosis.storage.ConsensusValidatorEntrypoint';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorage() private view returns (Storage storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  // ============================ NOTE: INITIALIZATION FUNCTIONS ============================ //

  constructor() {
    _disableInitializers();
  }

  fallback() external payable {
    revert StdError.NotSupported();
  }

  receive() external payable {
    revert StdError.NotSupported();
  }

  function initialize(address owner_) external initializer {
    __Ownable2Step_init();
    __Ownable_init(owner_);
    __UUPSUpgradeable_init();
  }

  // ============================ NOTE: VIEW FUNCTIONS ============================ //

  function isPermittedCaller(address caller) external view returns (bool) {
    return _getStorage().isPermittedCaller[caller];
  }

  // ============================ NOTE: MUTATIVE FUNCTIONS ============================ //

  function registerValidator(address valAddr, bytes calldata pubKey, address initialCollateralOwner)
    external
    payable
    onlyPermittedCaller
    verifyPubKeyWithAddress(pubKey, valAddr)
  {
    require(initialCollateralOwner != address(0), StdError.ZeroAddress('initialCollateralOwner'));
    require(msg.value > 0, StdError.InvalidParameter('msg.value'));
    require(msg.value % 1 gwei == 0, StdError.InvalidParameter('msg.value'));

    emit MsgRegisterValidator(valAddr, pubKey, initialCollateralOwner, msg.value / 1 gwei);

    payable(address(0)).transfer(msg.value);
  }

  function depositCollateral(address valAddr, address collateralOwner) external payable onlyPermittedCaller {
    require(collateralOwner != address(0), StdError.ZeroAddress('collateralOwner'));
    require(msg.value > 0, StdError.InvalidParameter('msg.value'));
    require(msg.value % 1 gwei == 0, StdError.InvalidParameter('msg.value'));

    emit MsgDepositCollateral(valAddr, collateralOwner, msg.value / 1 gwei);

    payable(address(0)).transfer(msg.value);
  }

  function withdrawCollateral(
    address valAddr,
    address collateralOwner,
    address receiver,
    uint256 amount,
    uint48 maturesAt
  ) external onlyPermittedCaller {
    require(collateralOwner != address(0), StdError.ZeroAddress('collateralOwner'));
    require(amount > 0, StdError.InvalidParameter('amount'));
    require(amount % 1 gwei == 0, StdError.InvalidParameter('amount'));

    emit MsgWithdrawCollateral(valAddr, collateralOwner, receiver, amount / 1 gwei, maturesAt);
  }

  function transferCollateralOwnership(address valAddr, address prevOwner, address newOwner)
    external
    onlyPermittedCaller
  {
    require(newOwner != address(0), StdError.ZeroAddress('newOwner'));

    emit MsgTransferCollateralOwnership(valAddr, prevOwner, newOwner);
  }

  function unjail(address valAddr) external onlyPermittedCaller {
    emit MsgUnjail(valAddr);
  }

  function updateExtraVotingPower(address valAddr, uint256 extraVotingPower) external onlyPermittedCaller {
    emit MsgUpdateExtraVotingPower(valAddr, extraVotingPower);
  }

  // ============================ NOTE: OWNABLE FUNCTIONS ============================ //

  function _authorizeUpgrade(address) internal override onlyOwner { }

  function setPermittedCaller(address caller, bool isPermitted) external onlyOwner {
    _getStorage().isPermittedCaller[caller] = isPermitted;
    emit PermittedCallerSet(caller, isPermitted);
  }
}
