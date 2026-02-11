// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IConcentratorBase {
  /**********
   * Events *
   **********/

  /// @notice Emitted when the treasury contract is updated.
  ///
  /// @param oldTreasury The address of the previous treasury contract.
  /// @param newTreasury The address of the current treasury contract.
  event UpdateTreasury(address indexed oldTreasury, address indexed newTreasury);

  /// @notice Emitted when the harvester contract is updated.
  ///
  /// @param oldHarvester The address of the previous harvester contract.
  /// @param newHarvester The address of the current harvester contract.
  event UpdateHarvester(address indexed oldHarvester, address indexed newHarvester);

  /// @notice Emitted when the ratio for treasury is updated.
  /// @param oldRatio The value of the previous ratio, multiplied by 1e9.
  /// @param newRatio The value of the current ratio, multiplied by 1e9.
  event UpdateExpenseRatio(uint256 oldRatio, uint256 newRatio);

  /// @notice Emitted when the ratio for harvester is updated.
  /// @param oldRatio The value of the previous ratio, multiplied by 1e9.
  /// @param newRatio The value of the current ratio, multiplied by 1e9.
  event UpdateHarvesterRatio(uint256 oldRatio, uint256 newRatio);

  /*************************
   * Public View Functions *
   *************************/

  /// @notice The address of protocol revenue holder.
  function treasury() external view returns (address);

  /// @notice The address of harvester contract.
  function harvester() external view returns (address);

  /// @notice Return the fee ratio distributed to treasury, multiplied by 1e9.
  function getExpenseRatio() external view returns (uint256);

  /// @notice Return the fee ratio distributed to harvester, multiplied by 1e9.
  function getHarvesterRatio() external view returns (uint256);
}
