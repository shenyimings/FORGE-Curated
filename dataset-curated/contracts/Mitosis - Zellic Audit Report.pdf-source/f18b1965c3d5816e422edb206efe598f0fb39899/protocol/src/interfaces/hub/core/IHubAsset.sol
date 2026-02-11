// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';

/**
 * @title IHubAsset
 * @dev Common interface for {HubAsset}. Extends IERC20 with minting and burning capabilities.
 */
interface IHubAsset is IERC20Metadata {
  /**
   * @notice Mints new tokens to a specified account.
   * @dev This function should only be callable by authorized entities.
   * @param account The address of the account to receive the minted tokens.
   * @param value The amount of tokens to mint.
   */
  function mint(address account, uint256 value) external;

  /**
   * @notice Burns tokens from a specified account.
   * @dev This function should only be callable by authorized entities.
   * @param account The address of the account from which tokens will be burned.
   * @param value The amount of tokens to burn.
   */
  function burn(address account, uint256 value) external;
}
