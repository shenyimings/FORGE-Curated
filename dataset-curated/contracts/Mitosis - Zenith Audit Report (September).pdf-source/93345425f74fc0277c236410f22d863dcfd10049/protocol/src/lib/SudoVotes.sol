// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IVotes } from '@oz/governance/utils/IVotes.sol';
import { VotesUpgradeable } from '@ozu/governance/utils/VotesUpgradeable.sol';

import { ISudoVotes } from '../interfaces/lib/ISudoVotes.sol';
import { ERC7201Utils } from './ERC7201Utils.sol';
import { StdError } from './StdError.sol';

abstract contract SudoVotes is VotesUpgradeable, ISudoVotes {
  using ERC7201Utils for string;

  struct SudoVotesStorageV1 {
    address delegationManager;
  }

  string private constant _NAMESPACE = 'mitosis.storage.SudoVotes.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getSudoVotesStorageV1() internal view returns (SudoVotesStorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  //============================ VIRTUAL FUNCTIONS ============================ //

  function owner() public view virtual returns (address);

  //============================ OVERRIDE FUNCTIONS ============================ //

  /// @dev Disabled: make only the delegation manager can delegate
  function delegate(address) public pure virtual override(IVotes, VotesUpgradeable) {
    revert StdError.NotSupported();
  }

  /// @dev Disabled: make only the delegation manager can delegate
  function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32)
    public
    pure
    virtual
    override(IVotes, VotesUpgradeable)
  {
    revert StdError.NotSupported();
  }

  //============================ EXTERNAL FUNCTIONS ============================ //

  function delegationManager() external view returns (address) {
    return _delegationManager();
  }

  /// @dev Only the delegation manager can perform delegate
  function sudoDelegate(address account, address delegatee) external {
    _sudoDelegate(account, delegatee);
  }

  /// @dev Only the owner can set the delegation manager
  function setDelegationManager(address delegationManager_) external {
    _setDelegationManager(delegationManager_);
  }

  //============================ INTERNAL VIRTUAL FUNCTIONS ============================ //

  function _delegationManager() internal view virtual returns (address) {
    return _getSudoVotesStorageV1().delegationManager;
  }

  function _sudoDelegate(address account, address delegatee) internal virtual {
    require(_delegationManager() == _msgSender(), StdError.Unauthorized());

    _delegate(account, delegatee);
  }

  function _setDelegationManager(address delegationManager_) internal virtual {
    require(owner() == _msgSender(), StdError.Unauthorized());

    address previous = _getSudoVotesStorageV1().delegationManager;
    _getSudoVotesStorageV1().delegationManager = delegationManager_;

    emit DelegationManagerSet(previous, delegationManager_);
  }
}
