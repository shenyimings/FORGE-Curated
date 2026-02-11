// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/**
 * @title Interface of the manager contract for owners
 * @author https://getclave.io
 */
interface IOwnerManager {
  /**
   * @notice Event emitted when a k1 owner is added
   * @param addr address - k1 owner that has been added
   */
  event K1AddOwner(address indexed addr);

  /**
   * @notice Event emitted when a k1 owner is removed
   * @param addr address - k1 owner that has been removed
   */
  event K1RemoveOwner(address indexed addr);

  /**
   * @notice Adds a k1 owner to the list of k1 owners
   * @dev Can only be called by self or a whitelisted module
   * @dev Address can not be the zero address
   * @param addr address - Address to add to the list of k1 owners
   */
  function k1AddOwner(address addr) external;

  /**
   * @notice Removes a k1 owner from the list of k1 owners
   * @dev Can only be called by self or a whitelisted module
   * @param addr address - Address to remove from the list of k1 owners
   */
  function k1RemoveOwner(address addr) external;

  /**
   * @notice Checks if an address is in the list of k1 owners
   * @param addr address - Address to check
   * @return bool - True if the address is in the list, false otherwise
   */
  function k1IsOwner(address addr) external view returns (bool);

  /**
   * @notice Returns the list of k1 owners
   * @return k1OwnerList address[] memory - Array of k1 owner addresses
   */
  function k1ListOwners() external view returns (address[] memory k1OwnerList);
}
