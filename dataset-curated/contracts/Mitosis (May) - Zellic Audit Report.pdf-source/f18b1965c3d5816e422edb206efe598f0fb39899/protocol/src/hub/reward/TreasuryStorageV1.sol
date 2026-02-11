// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ITreasuryStorageV1 } from '../../interfaces/hub/reward/ITreasury.sol';
import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';

/**
 * @title TreasuryStorageV1
 * @notice A storage, getter definition for the Treasury (version 1)
 */
contract TreasuryStorageV1 is ITreasuryStorageV1 {
  using ERC7201Utils for string;

  struct Log {
    uint48 timestamp;
    uint208 amount;
    bool sign;
  }

  struct StorageV1 {
    mapping(address vault => mapping(address reward => uint256 balance)) balances;
    mapping(address vault => mapping(address reward => Log[] logs)) history;
  }

  string private constant _NAMESPACE = 'mitosis.storage.TreasuryStorage.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  // ============================ NOTE: VIEW FUNCTIONS ============================ //

  /**
   * @inheritdoc ITreasuryStorageV1
   */
  function balances(address vault, address reward) external view returns (uint256) {
    return _balances(_getStorageV1(), vault, reward);
  }

  /**
   * @inheritdoc ITreasuryStorageV1
   */
  function history(address vault, address reward, uint256 offset, uint256 size)
    external
    view
    returns (HistoryResponse[] memory)
  {
    StorageV1 storage $ = _getStorageV1();

    uint256 historyLength = $.history[vault][reward].length;
    if (offset + size > historyLength) size = historyLength - offset;

    HistoryResponse[] memory history_ = new HistoryResponse[](size);
    for (uint256 i = 0; i < size; i++) {
      Log memory log = $.history[vault][reward][offset + i];
      history_[i] = HistoryResponse(log.timestamp, log.amount, log.sign);
    }

    return history_;
  }

  // ============================ NOTE: INTERNAL FUNCTIONS ============================ //

  function _balances(StorageV1 storage $, address vault, address reward) internal view returns (uint256) {
    return $.balances[vault][reward];
  }
}
