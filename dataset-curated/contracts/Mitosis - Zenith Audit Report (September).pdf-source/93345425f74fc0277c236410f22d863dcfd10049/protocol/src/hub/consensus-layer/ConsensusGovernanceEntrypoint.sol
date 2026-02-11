// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IConsensusGovernanceEntrypoint } from '../../interfaces/hub/consensus-layer/IConsensusGovernanceEntrypoint.sol';
import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { LibSecp256k1 } from '../../lib/LibSecp256k1.sol';
import { StdError } from '../../lib/StdError.sol';
import { Versioned } from '../../lib/Versioned.sol';

contract ConsensusGovernanceEntrypoint is
  IConsensusGovernanceEntrypoint,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  Versioned
{
  using ERC7201Utils for string;

  /// @custom:storage-location mitosis.storage.ConsensusGovernanceEntrypoint
  struct Storage {
    mapping(address caller => bool) isPermittedCaller;
  }

  modifier onlyPermittedCaller() {
    require(_getStorage().isPermittedCaller[_msgSender()], StdError.Unauthorized());
    _;
  }

  // =========================== NOTE: STORAGE DEFINITIONS =========================== //

  string private constant _NAMESPACE = 'mitosis.storage.ConsensusGovernanceEntrypoint';
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

  function execute(string[] calldata messages) external onlyPermittedCaller {
    emit MsgExecute(messages);
  }

  // ============================ NOTE: OWNABLE FUNCTIONS ============================ //

  function _authorizeUpgrade(address) internal override onlyOwner { }

  function setPermittedCaller(address caller, bool isPermitted) external onlyOwner {
    _getStorage().isPermittedCaller[caller] = isPermitted;
    emit PermittedCallerSet(caller, isPermitted);
  }
}
