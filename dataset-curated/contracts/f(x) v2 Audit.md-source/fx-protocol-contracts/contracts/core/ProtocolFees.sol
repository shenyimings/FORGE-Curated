// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { IPool } from "../interfaces/IPool.sol";
import { IProtocolFees } from "../interfaces/IProtocolFees.sol";

import { WordCodec } from "../common/codec/WordCodec.sol";

abstract contract ProtocolFees is AccessControlUpgradeable, PausableUpgradeable, IProtocolFees {
  using SafeERC20 for IERC20;
  using WordCodec for bytes32;

  /**********
   * Errors *
   **********/

  /// @dev Thrown when the given address is zero.
  error ErrorZeroAddress();

  /// @dev Thrown when the expense ratio exceeds `MAX_EXPENSE_RATIO`.
  error ErrorExpenseRatioTooLarge();

  /// @dev Thrown when the harvester ratio exceeds `MAX_HARVESTER_RATIO`.
  error ErrorHarvesterRatioTooLarge();

  /// @dev Thrown when the flash loan fee ratio exceeds `MAX_FLASH_LOAN_FEE_RATIO`.
  error ErrorFlashLoanFeeRatioTooLarge();

  /// @dev Thrown when the redeem fee ratio exceeds `MAX_REDEEM_FEE_RATIO`.
  error ErrorRedeemFeeRatioTooLarge();

  /*************
   * Constants *
   *************/

  /// @dev The maximum expense ratio.
  uint256 private constant MAX_EXPENSE_RATIO = 5e8; // 50%

  /// @dev The maximum harvester ratio.
  uint256 private constant MAX_HARVESTER_RATIO = 2e8; // 20%

  /// @dev The maximum flash loan fee ratio.
  uint256 private constant MAX_FLASH_LOAN_FEE_RATIO = 1e8; // 10%

  /// @dev The maximum redeem fee ratio.
  uint256 private constant MAX_REDEEM_FEE_RATIO = 1e8; // 10%

  /// @dev The offset of general expense ratio in `_miscData`.
  uint256 private constant REWARDS_EXPENSE_RATIO_OFFSET = 0;

  /// @dev The offset of harvester ratio in `_miscData`.
  uint256 private constant HARVESTER_RATIO_OFFSET = 30;

  /// @dev The offset of flash loan ratio in `_miscData`.
  uint256 private constant FLASH_LOAN_RATIO_OFFSET = 60;

  /// @dev The offset of redeem fee ratio in `_miscData`.
  uint256 private constant REDEEM_FEE_RATIO_OFFSET = 90;

  /// @dev The offset of funding expense ratio in `_miscData`.
  uint256 private constant FUNDING_EXPENSE_RATIO_OFFSET = 120;

  /// @dev The offset of liquidation expense ratio in `_miscData`.
  uint256 private constant LIQUIDATION_EXPENSE_RATIO_OFFSET = 150;

  /// @dev The precision used to compute fees.
  uint256 internal constant FEE_PRECISION = 1e9;

  /*************
   * Variables *
   *************/

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
  /// - The *withdraw fee percentage* is charged each time when user try to withdraw assets from the pool.
  ///
  /// [ rewards expense ratio | harvester ratio | flash loan ratio | redeem ratio | funding expense ratio | liquidation expense ratio | available ]
  /// [        30 bits        |     30 bits     |     30  bits     |   30  bits   |        30 bits        |          30 bits          |  76 bits  ]
  /// [ MSB                                                                                                                                   LSB ]
  bytes32 internal _miscData;

  /// @inheritdoc IProtocolFees
  address public treasury;

  /// @inheritdoc IProtocolFees
  /// @dev Hold fees including open.
  address public openRevenuePool;

  /// @inheritdoc IProtocolFees
  address public reservePool;

  /// @inheritdoc IProtocolFees
  mapping(address => uint256) public accumulatedPoolOpenFees;

  /// @inheritdoc IProtocolFees
  /// @dev Hold fees including close
  address public closeRevenuePool;

  /// @inheritdoc IProtocolFees
  mapping(address => uint256) public accumulatedPoolCloseFees;

  /// @inheritdoc IProtocolFees
  /// @dev Hold fees including redeem, liquidation and rebalance.
  address public miscRevenuePool;

  /// @inheritdoc IProtocolFees
  mapping(address => uint256) public accumulatedPoolMiscFees;

  /***************
   * Constructor *
   ***************/

  function __ProtocolFees_init(
    uint256 _expenseRatio,
    uint256 _harvesterRatio,
    uint256 _flashLoanFeeRatio,
    address _treasury,
    address _revenuePool,
    address _reservePool
  ) internal onlyInitializing {
    _updateFundingExpenseRatio(_expenseRatio);
    _updateRewardsExpenseRatio(_expenseRatio);
    _updateLiquidationExpenseRatio(_expenseRatio);
    _updateHarvesterRatio(_harvesterRatio);
    _updateFlashLoanFeeRatio(_flashLoanFeeRatio);
    _updateTreasury(_treasury);
    _updateOpenRevenuePool(_revenuePool);
    _updateCloseRevenuePool(_revenuePool);
    _updateMiscRevenuePool(_revenuePool);
    _updateReservePool(_reservePool);
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @inheritdoc IProtocolFees
  function getFundingExpenseRatio() public view returns (uint256) {
    return _miscData.decodeUint(FUNDING_EXPENSE_RATIO_OFFSET, 30);
  }

  /// @inheritdoc IProtocolFees
  function getRewardsExpenseRatio() public view returns (uint256) {
    return _miscData.decodeUint(REWARDS_EXPENSE_RATIO_OFFSET, 30);
  }

  /// @inheritdoc IProtocolFees
  function getLiquidationExpenseRatio() public view returns (uint256) {
    return _miscData.decodeUint(LIQUIDATION_EXPENSE_RATIO_OFFSET, 30);
  }

  /// @inheritdoc IProtocolFees
  function getHarvesterRatio() public view returns (uint256) {
    return _miscData.decodeUint(HARVESTER_RATIO_OFFSET, 30);
  }

  /// @inheritdoc IProtocolFees
  function getFundingFxSaveRatio() external view returns (uint256) {
    return FEE_PRECISION - getFundingExpenseRatio() - getHarvesterRatio();
  }

  /// @inheritdoc IProtocolFees
  function getRewardsFxSaveRatio() external view returns (uint256) {
    return FEE_PRECISION - getRewardsExpenseRatio() - getHarvesterRatio();
  }

  /// @inheritdoc IProtocolFees
  function getFlashLoanFeeRatio() public view returns (uint256) {
    return _miscData.decodeUint(FLASH_LOAN_RATIO_OFFSET, 30);
  }

  /// @inheritdoc IProtocolFees
  function getRedeemFeeRatio() public view returns (uint256) {
    return _miscData.decodeUint(REDEEM_FEE_RATIO_OFFSET, 30);
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @inheritdoc IProtocolFees
  function withdrawAccumulatedPoolFee(address[] memory pools) external {
    for (uint256 i = 0; i < pools.length; ++i) {
      _takeAccumulatedPoolFee(pools[i]);
    }
  }

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Change address of reserve pool contract.
  /// @param _newReservePool The new address of reserve pool contract.
  function updateReservePool(address _newReservePool) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateReservePool(_newReservePool);
  }

  /// @notice Change address of treasury contract.
  /// @param _newTreasury The new address of treasury contract.
  function updateTreasury(address _newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateTreasury(_newTreasury);
  }

  /// @notice Change address of open revenue pool contract.
  /// @param _newPool The new address of revenue pool contract.
  function updateOpenRevenuePool(address _newPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateOpenRevenuePool(_newPool);
  }

  /// @notice Change address of close revenue pool contract.
  /// @param _newPool The new address of revenue pool contract.
  function updateCloseRevenuePool(address _newPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateCloseRevenuePool(_newPool);
  }

  /// @notice Change address of misc revenue pool contract.
  /// @param _newPool The new address of revenue pool contract.
  function updateMiscRevenuePool(address _newPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateMiscRevenuePool(_newPool);
  }

  /// @notice Update the fee ratio distributed to treasury.
  /// @param newRewardsRatio The new ratio for rewards to update, multiplied by 1e9.
  /// @param newFundingRatio The new ratio for funding to update, multiplied by 1e9.
  /// @param newLiquidationRatio The new ratio for liquidation/rebalance to update, multiplied by 1e9.
  function updateExpenseRatio(
    uint32 newRewardsRatio,
    uint32 newFundingRatio,
    uint32 newLiquidationRatio
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateRewardsExpenseRatio(newRewardsRatio);
    _updateFundingExpenseRatio(newFundingRatio);
    _updateLiquidationExpenseRatio(newLiquidationRatio);
  }

  /// @notice Update the fee ratio distributed to harvester.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function updateHarvesterRatio(uint32 newRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateHarvesterRatio(newRatio);
  }

  /// @notice Update the flash loan fee ratio.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function updateFlashLoanFeeRatio(uint32 newRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateFlashLoanFeeRatio(newRatio);
  }

  /// @notice Update the redeem fee ratio.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function updateRedeemFeeRatio(uint32 newRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateRedeemFeeRatio(newRatio);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to change address of treasury contract.
  /// @param _newTreasury The new address of treasury contract.
  function _updateTreasury(address _newTreasury) private {
    if (_newTreasury == address(0)) revert ErrorZeroAddress();

    address _oldTreasury = treasury;
    treasury = _newTreasury;

    emit UpdateTreasury(_oldTreasury, _newTreasury);
  }

  /// @dev Internal function to change address of revenue pool contract.
  /// @param _newPool The new address of revenue pool contract.
  function _updateOpenRevenuePool(address _newPool) private {
    if (_newPool == address(0)) revert ErrorZeroAddress();

    address _oldPool = openRevenuePool;
    openRevenuePool = _newPool;

    emit UpdateOpenRevenuePool(_oldPool, _newPool);
  }

  /// @dev Internal function to change address of revenue pool contract.
  /// @param _newPool The new address of revenue pool contract.
  function _updateCloseRevenuePool(address _newPool) private {
    if (_newPool == address(0)) revert ErrorZeroAddress();

    address _oldPool = closeRevenuePool;
    closeRevenuePool = _newPool;

    emit UpdateCloseRevenuePool(_oldPool, _newPool);
  }

  /// @dev Internal function to change address of revenue pool contract.
  /// @param _newPool The new address of revenue pool contract.
  function _updateMiscRevenuePool(address _newPool) private {
    if (_newPool == address(0)) revert ErrorZeroAddress();

    address _oldPool = miscRevenuePool;
    miscRevenuePool = _newPool;

    emit UpdateMiscRevenuePool(_oldPool, _newPool);
  }

  /// @dev Internal function to change the address of reserve pool contract.
  /// @param newReservePool The new address of reserve pool contract.
  function _updateReservePool(address newReservePool) private {
    if (newReservePool == address(0)) revert ErrorZeroAddress();

    address oldReservePool = reservePool;
    reservePool = newReservePool;

    emit UpdateReservePool(oldReservePool, newReservePool);
  }

  /// @dev Internal function to update the fee ratio distributed to treasury.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function _updateRewardsExpenseRatio(uint256 newRatio) private {
    if (uint256(newRatio) > MAX_EXPENSE_RATIO) {
      revert ErrorExpenseRatioTooLarge();
    }

    bytes32 _data = _miscData;
    uint256 _oldRatio = _miscData.decodeUint(REWARDS_EXPENSE_RATIO_OFFSET, 30);
    _miscData = _data.insertUint(newRatio, REWARDS_EXPENSE_RATIO_OFFSET, 30);

    emit UpdateRewardsExpenseRatio(_oldRatio, newRatio);
  }

  /// @dev Internal function to update the fee ratio distributed to treasury.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function _updateLiquidationExpenseRatio(uint256 newRatio) private {
    if (uint256(newRatio) > MAX_EXPENSE_RATIO) {
      revert ErrorExpenseRatioTooLarge();
    }

    bytes32 _data = _miscData;
    uint256 _oldRatio = _miscData.decodeUint(LIQUIDATION_EXPENSE_RATIO_OFFSET, 30);
    _miscData = _data.insertUint(newRatio, LIQUIDATION_EXPENSE_RATIO_OFFSET, 30);

    emit UpdateLiquidationExpenseRatio(_oldRatio, newRatio);
  }

  /// @dev Internal function to update the fee ratio distributed to treasury.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function _updateFundingExpenseRatio(uint256 newRatio) private {
    if (uint256(newRatio) > MAX_EXPENSE_RATIO) {
      revert ErrorExpenseRatioTooLarge();
    }

    bytes32 _data = _miscData;
    uint256 _oldRatio = _miscData.decodeUint(FUNDING_EXPENSE_RATIO_OFFSET, 30);
    _miscData = _data.insertUint(newRatio, FUNDING_EXPENSE_RATIO_OFFSET, 30);

    emit UpdateFundingExpenseRatio(_oldRatio, newRatio);
  }

  /// @dev Internal function to update the fee ratio distributed to harvester.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function _updateHarvesterRatio(uint256 newRatio) private {
    if (uint256(newRatio) > MAX_HARVESTER_RATIO) {
      revert ErrorHarvesterRatioTooLarge();
    }

    bytes32 _data = _miscData;
    uint256 _oldRatio = _miscData.decodeUint(HARVESTER_RATIO_OFFSET, 30);
    _miscData = _data.insertUint(newRatio, HARVESTER_RATIO_OFFSET, 30);

    emit UpdateHarvesterRatio(_oldRatio, newRatio);
  }

  /// @dev Internal function to update the flash loan fee ratio.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function _updateFlashLoanFeeRatio(uint256 newRatio) private {
    if (uint256(newRatio) > MAX_FLASH_LOAN_FEE_RATIO) {
      revert ErrorFlashLoanFeeRatioTooLarge();
    }

    bytes32 _data = _miscData;
    uint256 _oldRatio = _miscData.decodeUint(FLASH_LOAN_RATIO_OFFSET, 30);
    _miscData = _data.insertUint(newRatio, FLASH_LOAN_RATIO_OFFSET, 30);

    emit UpdateFlashLoanFeeRatio(_oldRatio, newRatio);
  }

  /// @dev Internal function to update the redeem fee ratio.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function _updateRedeemFeeRatio(uint256 newRatio) private {
    if (uint256(newRatio) > MAX_REDEEM_FEE_RATIO) {
      revert ErrorRedeemFeeRatioTooLarge();
    }

    bytes32 _data = _miscData;
    uint256 _oldRatio = _miscData.decodeUint(REDEEM_FEE_RATIO_OFFSET, 30);
    _miscData = _data.insertUint(newRatio, REDEEM_FEE_RATIO_OFFSET, 30);

    emit UpdateRedeemFeeRatio(_oldRatio, newRatio);
  }

  /// @dev Internal function to accumulate protocol fee for the given pool.
  /// @param pool The address of pool.
  /// @param amount The amount of protocol fee.
  function _accumulatePoolOpenFee(address pool, uint256 amount) internal {
    if (amount > 0) {
      accumulatedPoolOpenFees[pool] += amount;
    }
  }

  /// @dev Internal function to accumulate protocol fee for the given pool.
  /// @param pool The address of pool.
  /// @param amount The amount of protocol fee.
  function _accumulatePoolCloseFee(address pool, uint256 amount) internal {
    if (amount > 0) {
      accumulatedPoolCloseFees[pool] += amount;
    }
  }

  /// @dev Internal function to accumulate protocol fee for the given pool.
  /// @param pool The address of pool.
  /// @param amount The amount of protocol fee.
  function _accumulatePoolMiscFee(address pool, uint256 amount) internal {
    if (amount > 0) {
      accumulatedPoolMiscFees[pool] += amount;
    }
  }

  /// @dev Internal function to withdraw accumulated protocol fee for the given pool.
  /// @param pool The address of pool.
  function _takeAccumulatedPoolFee(address pool) internal returns (uint256 fees) {
    address collateralToken = IPool(pool).collateralToken();
    fees = accumulatedPoolOpenFees[pool];
    if (fees > 0) {
      IERC20(collateralToken).safeTransfer(openRevenuePool, fees);
      accumulatedPoolOpenFees[pool] = 0;
    }
    fees = accumulatedPoolCloseFees[pool];
    if (fees > 0) {
      IERC20(collateralToken).safeTransfer(closeRevenuePool, fees);
      accumulatedPoolCloseFees[pool] = 0;
    }
    fees = accumulatedPoolMiscFees[pool];
    if (fees > 0) {
      IERC20(collateralToken).safeTransfer(miscRevenuePool, fees);
      accumulatedPoolMiscFees[pool] = 0;
    }
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   */
  uint256[41] private __gap;
}
