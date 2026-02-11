// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/interfaces/IERC20.sol';
import { IERC5805 } from '@oz/interfaces/IERC5805.sol';

interface IGovMITO is IERC20, IERC5805 {
  /**
   * @notice Emitted when tokens are minted.
   * @param to The address that received the tokens
   * @param amount The amount of tokens minted
   */
  event Minted(address indexed to, uint256 amount);

  /**
   * @notice Emitted when a withdraw request is made.
   * @param requester The address that made the request
   * @param receiver The address that will receive the assets
   * @param amount The amount of tokens to withdraw
   * @param reqId The ID of the withdraw request
   */
  event WithdrawRequested(address indexed requester, address indexed receiver, uint256 amount, uint256 reqId);

  /**
   * @notice Emitted when a withdraw request is claimed.
   * @param receiver The address that received the assets
   * @param claimed The amount of assets claimed
   * @param reqIdFrom The ID of the first request in the claim
   * @param reqIdTo The ID of the last request in the claim
   */
  event WithdrawRequestClaimed(address indexed receiver, uint256 claimed, uint256 reqIdFrom, uint256 reqIdTo);

  /**
   * @notice Emitted when the minter is set.
   * @param minter The address of the new minter
   */
  event MinterSet(address indexed minter);

  /**
   * @notice Emitted when a module is enabled or disabled.
   * @param module The address of the module
   * @param enabled Whether the module is enabled
   */
  event ModuleSet(address indexed module, bool indexed enabled);

  /**
   * @notice Emitted when a whitelist status for a sender is set.
   * @param sender The address of the sender
   * @param whitelisted Whether the sender is whitelisted
   */
  event WhitelistedSenderSet(address indexed sender, bool whitelisted);

  /**
   * @notice Emitted when the withdraw period is set.
   * @param withdrawalPeriod The new withdraw period
   */
  event WithdrawalPeriodSet(uint256 withdrawalPeriod);

  /**
   * @notice Returns the address of the minter.
   * @return The address of the minter
   */
  function minter() external view returns (address);

  /**
   * @notice Checks if a module is enabled.
   * @param module The address to check
   * @return Whether the module is enabled
   */
  function isModule(address module) external view returns (bool);

  /**
   * @notice Checks if an address is a whitelisted sender.
   * @param sender The address to check
   * @return Whether the address is a whitelisted sender
   */
  function isWhitelistedSender(address sender) external view returns (bool);

  /**
   * @notice Returns the withdraw period.
   * @return withdrawalPeriod The withdraw period
   */
  function withdrawalPeriod() external view returns (uint256);

  /**
   * @notice Returns the offset of a receiver's withdrawal queue.
   * @param receiver The address to check the offset for
   * @return offset The offset of the withdrawal queue
   */
  function withdrawalQueueOffset(address receiver) external view returns (uint256);

  /**
   * @notice Returns the size of a receiver's withdrawal queue.
   * @param receiver The address to check the queue size for
   * @return size The size of the withdrawal queue
   */
  function withdrawalQueueSize(address receiver) external view returns (uint256);

  /**
   * @notice Returns a withdrawal request by its index in the queue.
   * @param receiver The address to check the request for
   * @param pos The index of the request in the queue
   * @return timestamp The timestamp of the request
   * @return amount The amount requested
   */
  function withdrawalQueueRequestByIndex(address receiver, uint32 pos) external view returns (uint48, uint208);

  /**
   * @notice Returns a withdrawal request by timestamp.
   * @param receiver The address to check the request for
   * @param time The timestamp to look up
   * @return timestamp The timestamp of the request
   * @return amount The amount requested
   */
  function withdrawalQueueRequestByTime(address receiver, uint48 time) external view returns (uint48, uint208);

  /**
   * @notice Preview the amount that can be claimed from a withdraw request.
   * @param receiver The address to check the claimable amount for
   * @return amount The amount of assets that can be claimed
   */
  function previewClaimWithdraw(address receiver) external view returns (uint256);

  /**
   * @notice Mint tokens to an address with corresponding MITO.
   * @dev Only the minter can call this function.
   * @param to The address to mint tokens to
   */
  function mint(address to) external payable;

  /**
   * @notice Request to withdraw tokens for assets.
   * @dev The requester must have enough tokens to withdraw.
   * @param receiver The address to receive the assets
   * @param amount The amount of tokens to withdraw
   * @return reqId The ID of the withdraw request
   */
  function requestWithdraw(address receiver, uint256 amount) external returns (uint256 reqId);

  /**
   * @notice Claim a withdraw request.
   * @dev The receiver must have a withdraw request to claim.
   * @param receiver The address to claim the withdraw request for
   * @return claimed The amount of assets claimed
   */
  function claimWithdraw(address receiver) external returns (uint256 claimed);

  /**
   * @notice Set the minter.
   * @param minter The address of the new minter
   */
  function setMinter(address minter) external;

  /**
   * @notice Set the whitelist status for a module.
   * @param addr The address of the module
   * @param isModule Whether the module is enabled
   */
  function setModule(address addr, bool isModule) external;

  /**
   * @notice Set the whitelist status for a sender.
   * @param sender The address of the sender
   * @param isWhitelisted Whether the sender is whitelisted
   */
  function setWhitelistedSender(address sender, bool isWhitelisted) external;

  /**
   * @notice Set the withdraw period.
   * @param withdrawalPeriod The new withdraw period
   */
  function setWithdrawalPeriod(uint256 withdrawalPeriod) external;
}
