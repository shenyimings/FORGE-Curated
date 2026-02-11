// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IAccessControlEnumerable } from '@oz/access/extensions/IAccessControlEnumerable.sol';

/**
 * @title ITreasuryStorageV1
 * @notice Interface definition for the TreasuryStorageV1
 */
interface ITreasuryStorageV1 {
  struct HistoryResponse {
    uint48 timestamp;
    uint208 amount;
    bool sign;
  }

  /**
   * @notice Returns the current holdings of the reward token for the vault
   * @param vault The vault address
   * @param reward The reward token address
   */
  function balances(address vault, address reward) external view returns (uint256);

  /**
   * @notice Returns the management log histories of the reward token for the vault
   * @param vault The vault address
   * @param reward The reward token address
   * @param offset The offset to start from
   * @param size The number of logs to return
   */
  function history(address vault, address reward, uint256 offset, uint256 size)
    external
    view
    returns (HistoryResponse[] memory);
}

/**
 * @title ITreasury
 * @notice Interface for the Treasury reward handler
 */
interface ITreasury is IAccessControlEnumerable, ITreasuryStorageV1 {
  event RewardDispatched(address indexed vault, address indexed reward, address indexed from, uint256 amount);
  event RewardStored(address indexed vault, address indexed reward, address indexed from, uint256 amount);

  error ITreasury__InsufficientBalance();

  /**
   * @notice Stores the distribution of rewards for the specified vault and reward
   * @dev This method can only be called by the account that is allowed to dispatch rewards by `isDispatchable`
   */
  function storeRewards(address vault, address reward, uint256 amount) external;

  /**
   * @notice Dispatches reward distribution with stacked rewards
   * @param vault The vault address
   * @param reward The reward token address
   * @param amount The reward amount
   * @param handler The reward handler address
   */
  function dispatch(address vault, address reward, uint256 amount, address handler) external;
}
