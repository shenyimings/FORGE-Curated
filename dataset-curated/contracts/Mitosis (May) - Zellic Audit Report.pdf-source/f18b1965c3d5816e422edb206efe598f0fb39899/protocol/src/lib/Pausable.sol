// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ContextUpgradeable } from '@ozu/utils/ContextUpgradeable.sol';

import { ERC7201Utils } from './ERC7201Utils.sol';
import { StdError } from './StdError.sol';

abstract contract Pausable is ContextUpgradeable {
  using ERC7201Utils for string;

  /// @custom:storage-location mitosis.storage.Pausable
  struct PausableStorage {
    bool global_;
    mapping(bytes4 sig => bool isPaused) paused;
  }

  error Pausable__Paused(bytes4 sig);
  error Pausable__NotPaused(bytes4 sig);

  // =========================== NOTE: STORAGE DEFINITIONS =========================== //

  string private constant _NAMESPACE = 'mitosis.storage.Pausable';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getPausableStorage() private view returns (PausableStorage storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  // =========================== NOTE: INITIALIZE HELPERS =========================== //

  function __Pausable_init() internal {
    PausableStorage storage $ = _getPausableStorage();

    $.global_ = false;
  }

  // =========================== NOTE: MODIFIERS =========================== //

  modifier whenNotPaused() {
    require(!_isPaused(msg.sig), Pausable__Paused(msg.sig));
    _;
  }

  modifier whenPaused() {
    require(_isPaused(msg.sig), Pausable__NotPaused(msg.sig));
    _;
  }

  modifier onlyPauseManager() {
    _authorizePause(_msgSender());
    _;
  }

  // =========================== NOTE: VIRTUAL FUNCTIONS =========================== //

  function _authorizePause(address) internal view virtual;

  // =========================== NOTE: MAIN FUNCTIONS =========================== //

  function isPaused(bytes4 sig) external view returns (bool) {
    return _isPaused(sig);
  }

  function isPausedGlobally() external view returns (bool) {
    return _isPausedGlobally();
  }

  function pause() external onlyPauseManager {
    _pause();
  }

  function pause(bytes4 sig) external onlyPauseManager {
    _pause(sig);
  }

  function unpause() external onlyPauseManager {
    _unpause();
  }

  function unpause(bytes4 sig) external onlyPauseManager {
    _unpause(sig);
  }

  // =========================== NOTE: INTERNAL FUNCTIONS =========================== //

  function _pause() internal virtual {
    _getPausableStorage().global_ = true;
  }

  function _pause(bytes4 sig) internal virtual {
    _getPausableStorage().paused[sig] = true;
  }

  function _unpause() internal virtual {
    _getPausableStorage().global_ = false;
  }

  function _unpause(bytes4 sig) internal virtual {
    _getPausableStorage().paused[sig] = false;
  }

  function _isPaused(bytes4 sig) internal view virtual returns (bool) {
    PausableStorage storage $ = _getPausableStorage();

    return $.global_ || $.paused[sig];
  }

  function _isPausedGlobally() internal view virtual returns (bool) {
    return _getPausableStorage().global_;
  }
}
