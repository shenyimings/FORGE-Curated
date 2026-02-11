// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { WordCodec } from "../codec/WordCodec.sol";

import { IHarvesterCallback } from "../../helpers/interfaces/IHarvesterCallback.sol";
import { IConcentratorBase } from "./IConcentratorBase.sol";

// solhint-disable func-name-mixedcase
// solhint-disable no-inline-assembly

abstract contract ConcentratorBase is AccessControlUpgradeable, IConcentratorBase, IHarvesterCallback {
  using WordCodec for bytes32;

  /**********
   * Errors *
   **********/

  /// @dev Thrown when the address is zero.
  error ErrorZeroAddress();

  /// @dev Thrown when the expense ratio exceeds `MAX_EXPENSE_RATIO`.
  error ErrorExpenseRatioTooLarge();

  /// @dev Thrown when the harvester ratio exceeds `MAX_HARVESTER_RATIO`.
  error ErrorHarvesterRatioTooLarge();

  /// @dev Thrown when caller is not harvester and try to call some harvester only functions.
  error ErrorCallerNotHarvester();

  /*************
   * Constants *
   *************/

  /// @dev The fee denominator used for rate calculation.
  uint256 internal constant FEE_PRECISION = 1e9;

  /// @dev The maximum expense ratio.
  uint256 private constant MAX_EXPENSE_RATIO = 5e8; // 50%

  /// @dev The maximum harvester ratio.
  uint256 private constant MAX_HARVESTER_RATIO = 1e8; // 10%

  /// @dev The number of bits for fee ratios.
  uint256 private constant RATIO_BITS = 30;

  /// @dev The offset of expense ratio in `_miscData`.
  uint256 private constant EXPENSE_RATIO_OFFSET = 0;

  /// @dev The offset of harvester ratio in `_miscData`.
  uint256 private constant HARVESTER_RATIO_OFFSET = 30;

  /*************
   * Variables *
   *************/

  /// @inheritdoc IConcentratorBase
  address public treasury;

  /// @inheritdoc IConcentratorBase
  address public harvester;

  /// @dev `_miscData` is a storage slot that can be used to store unrelated pieces of information.
  /// All pools store the *expense ratio*, *harvester ratio* and *withdraw fee percentage*, but
  /// the `miscData`can be extended to store more pieces of information.
  ///
  /// The *expense ratio* is stored in the first most significant 32 bits, and the *harvester ratio* is
  /// stored in the next most significant 32 bits, and the *withdraw fee percentage* is stored in the
  /// next most significant 32 bits, leaving the remaining 160 bits free to store any other information
  /// derived pools might need.
  ///
  /// - The *expense ratio* and *harvester ratio* are charged each time when harvester harvest the pool revenue.
  ///
  /// [ expense ratio | harvester ratio | available ]
  /// [    30 bits    |     30 bits     |  196 bits ]
  /// [ MSB                                     LSB ]
  bytes32 internal _miscData;

  /// @dev reserved slots.
  uint256[47] private __gap;

  /***************
   * Constructor *
   ***************/

  function __ConcentratorBase_init(address _treasury, address _harvester) internal onlyInitializing {
    _updateTreasury(_treasury);
    _updateHarvester(_harvester);
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @inheritdoc IConcentratorBase
  function getExpenseRatio() public view override returns (uint256) {
    return _miscData.decodeUint(EXPENSE_RATIO_OFFSET, RATIO_BITS);
  }

  /// @inheritdoc IConcentratorBase
  function getHarvesterRatio() public view override returns (uint256) {
    return _miscData.decodeUint(HARVESTER_RATIO_OFFSET, RATIO_BITS);
  }

  /// @inheritdoc IHarvesterCallback
  function onHarvest(address token, uint256 amount) external override {
    if (_msgSender() != harvester) revert ErrorCallerNotHarvester();

    _onHarvest(token, amount);
  }

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Update the address of treasury contract.
  ///
  /// @param _newTreasury The address of the new treasury contract.
  function updateTreasury(address _newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateTreasury(_newTreasury);
  }

  /// @notice Update the address of harvester contract.
  ///
  /// @param _newHarvester The address of the new harvester contract.
  function updateHarvester(address _newHarvester) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateHarvester(_newHarvester);
  }

  /// @notice Update the fee ratio distributed to treasury.
  /// @param _newRatio The new ratio to update, multiplied by 1e9.
  function updateExpenseRatio(uint32 _newRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (uint256(_newRatio) > MAX_EXPENSE_RATIO) {
      revert ErrorExpenseRatioTooLarge();
    }

    bytes32 _data = _miscData;
    uint256 _oldRatio = _miscData.decodeUint(EXPENSE_RATIO_OFFSET, RATIO_BITS);
    _miscData = _data.insertUint(_newRatio, EXPENSE_RATIO_OFFSET, RATIO_BITS);

    emit UpdateExpenseRatio(_oldRatio, _newRatio);
  }

  /// @notice Update the fee ratio distributed to harvester.
  /// @param _newRatio The new ratio to update, multiplied by 1e9.
  function updateHarvesterRatio(uint32 _newRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (uint256(_newRatio) > MAX_HARVESTER_RATIO) {
      revert ErrorHarvesterRatioTooLarge();
    }

    bytes32 _data = _miscData;
    uint256 _oldRatio = _miscData.decodeUint(HARVESTER_RATIO_OFFSET, RATIO_BITS);
    _miscData = _data.insertUint(_newRatio, HARVESTER_RATIO_OFFSET, RATIO_BITS);

    emit UpdateHarvesterRatio(_oldRatio, _newRatio);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to update the address of treasury contract.
  ///
  /// @param _newTreasury The address of the new treasury contract.
  function _updateTreasury(address _newTreasury) private {
    if (_newTreasury == address(0)) revert ErrorZeroAddress();

    address _oldTreasury = treasury;
    treasury = _newTreasury;

    emit UpdateTreasury(_oldTreasury, _newTreasury);
  }

  /// @dev Internal function to update the address of harvester contract.
  ///
  /// @param _newHarvester The address of the new harvester contract.
  function _updateHarvester(address _newHarvester) private {
    address _oldHarvester = harvester;
    harvester = _newHarvester;

    emit UpdateHarvester(_oldHarvester, _newHarvester);
  }

  /// @dev Actual logic of onHarvest callback.
  function _onHarvest(address token, uint256 amount) internal virtual;
}
