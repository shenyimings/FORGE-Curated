// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IAaveV3Pool } from "../../interfaces/Aave/IAaveV3Pool.sol";
import { IAaveFundingPool } from "../../interfaces/IAaveFundingPool.sol";
import { IPegKeeper } from "../../interfaces/IPegKeeper.sol";

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { Math } from "../../libraries/Math.sol";
import { BasePool } from "./BasePool.sol";

contract AaveFundingPool is BasePool, IAaveFundingPool {
  using WordCodec for bytes32;

  /*************
   * Constants *
   *************/

  /// @dev The offset of *open ratio* in `fundingMiscData`.
  uint256 private constant OPEN_RATIO_OFFSET = 0;

  /// @dev The offset of *open ratio step* in `fundingMiscData`.
  uint256 private constant OPEN_RATIO_STEP_OFFSET = 30;

  /// @dev The offset of *close fee ratio* in `fundingMiscData`.
  uint256 private constant CLOSE_FEE_RATIO_OFFSET = 90;

  /// @dev The offset of *funding ratio* in `fundingMiscData`.
  uint256 private constant FUNDING_RATIO_OFFSET = 120;

  /// @dev The offset of *interest rate* in `fundingMiscData`.
  uint256 private constant INTEREST_RATE_OFFSET = 152;

  /// @dev The offset of *timestamp* in `fundingMiscData`.
  uint256 private constant TIMESTAMP_OFFSET = 220;

  /// @dev The maximum value of *funding ratio*.
  uint256 private constant MAX_FUNDING_RATIO = 4294967295;

  /// @dev The minimum Aave borrow index snapshot delay.
  uint256 private constant MIN_SNAPSHOT_DELAY = 30 minutes;

  /***********************
   * Immutable Variables *
   ***********************/

  /// @dev The address of Aave V3 `LendingPool` contract.
  address private immutable lendingPool;

  /// @dev The address of asset used for interest calculation.
  address private immutable baseAsset;

  /***********
   * Structs *
   ***********/

  /// @dev The struct for AAVE borrow rate snapshot.
  /// @param borrowIndex The current borrow index of AAVE, multiplied by 1e27.
  /// @param lastInterestRate The last recorded interest rate, multiplied by 1e18.
  /// @param timestamp The timestamp when the snapshot is taken.
  struct BorrowRateSnapshot {
    // The initial value of `borrowIndex` is `10^27`, it is very unlikely this value will exceed `2^128`.
    uint128 borrowIndex;
    uint80 lastInterestRate;
    uint48 timestamp;
  }

  /*********************
   * Storage Variables *
   *********************/

  /// @dev `fundingMiscData` is a storage slot that can be used to store unrelated pieces of information.
  ///
  /// - The *open ratio* is the fee ratio for opening position, multiplied by 1e9.
  /// - The *open ratio step* is the fee ratio step for opening position, multiplied by 1e18.
  /// - The *close fee ratio* is the fee ratio for closing position, multiplied by 1e9.
  /// - The *funding ratio* is the scalar for funding rate, multiplied by 1e9.
  ///   The maximum value is `4.294967296`.
  ///
  /// [ open ratio | open ratio step | close fee ratio | funding ratio | reserved ]
  /// [  30  bits  |     60 bits     |     30 bits     |    32 bits    | 104 bits ]
  /// [ MSB                                                                   LSB ]
  bytes32 private fundingMiscData;

  /// @notice The snapshot for AAVE borrow rate.
  BorrowRateSnapshot public borrowRateSnapshot;

  /***************
   * Constructor *
   ***************/

  constructor(address _poolManager, address _lendingPool, address _baseAsset) BasePool(_poolManager) {
    _checkAddressNotZero(_lendingPool);
    _checkAddressNotZero(_baseAsset);

    lendingPool = _lendingPool;
    baseAsset = _baseAsset;
  }

  function initialize(
    address admin,
    string memory name_,
    string memory symbol_,
    address _collateralToken,
    address _priceOracle
  ) external initializer {
    __Context_init();
    __ERC165_init();
    __ERC721_init(name_, symbol_);
    __AccessControl_init();

    __PoolStorage_init(_collateralToken, _priceOracle);
    __TickLogic_init();
    __PositionLogic_init();
    __BasePool_init();

    _grantRole(DEFAULT_ADMIN_ROLE, admin);

    _updateOpenRatio(1000000, 50000000000000000); // 0.1% and 5%
    _updateCloseFeeRatio(1000000); // 0.1%

    uint256 borrowIndex = IAaveV3Pool(lendingPool).getReserveNormalizedVariableDebt(baseAsset);
    IAaveV3Pool.ReserveDataLegacy memory reserveData = IAaveV3Pool(lendingPool).getReserveData(baseAsset);
    _updateInterestRate(borrowIndex, reserveData.currentVariableBorrowRate / 1e9);
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @notice Get open fee ratio related parameters.
  /// @return ratio The value of open ratio, multiplied by 1e9.
  /// @return step The value of open ratio step, multiplied by 1e18.
  function getOpenRatio() external view returns (uint256 ratio, uint256 step) {
    return _getOpenRatio();
  }

  /// @notice Return the value of funding ratio, multiplied by 1e9.
  function getFundingRatio() external view returns (uint256) {
    return _getFundingRatio();
  }

  /// @notice Return the fee ratio for opening position, multiplied by 1e9.
  function getOpenFeeRatio() public view returns (uint256) {
    (uint256 openRatio, uint256 openRatioStep) = _getOpenRatio();
    (, uint256 rate) = _getAverageInterestRate(borrowRateSnapshot);
    unchecked {
      uint256 aaveRatio = rate <= openRatioStep ? 1 : (rate - 1) / openRatioStep;
      return aaveRatio * openRatio;
    }
  }

  /// @notice Return the fee ratio for closing position, multiplied by 1e9.
  function getCloseFeeRatio() external view returns (uint256) {
    return _getCloseFeeRatio();
  }

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Update the fee ratio for opening position.
  /// @param ratio The open ratio value, multiplied by 1e9.
  /// @param step The open ratio step value, multiplied by 1e18.
  function updateOpenRatio(uint256 ratio, uint256 step) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateOpenRatio(ratio, step);
  }

  /// @notice Update the fee ratio for closing position.
  /// @param ratio The close ratio value, multiplied by 1e9.
  function updateCloseFeeRatio(uint256 ratio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateCloseFeeRatio(ratio);
  }

  /// @notice Update the funding ratio.
  /// @param ratio The funding ratio value, multiplied by 1e9.
  function updateFundingRatio(uint256 ratio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateFundingRatio(ratio);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to get open ratio and open ratio step.
  /// @return ratio The value of open ratio, multiplied by 1e9.
  /// @return step The value of open ratio step, multiplied by 1e18.
  function _getOpenRatio() internal view returns (uint256 ratio, uint256 step) {
    bytes32 data = fundingMiscData;
    ratio = data.decodeUint(OPEN_RATIO_OFFSET, 30);
    step = data.decodeUint(OPEN_RATIO_STEP_OFFSET, 60);
  }

  /// @dev Internal function to update the fee ratio for opening position.
  /// @param ratio The open ratio value, multiplied by 1e9.
  /// @param step The open ratio step value, multiplied by 1e18.
  function _updateOpenRatio(uint256 ratio, uint256 step) internal {
    _checkValueTooLarge(ratio, FEE_PRECISION);
    _checkValueTooLarge(step, PRECISION);

    bytes32 data = fundingMiscData;
    data = data.insertUint(ratio, OPEN_RATIO_OFFSET, 30);
    fundingMiscData = data.insertUint(step, OPEN_RATIO_STEP_OFFSET, 60);

    emit UpdateOpenRatio(ratio, step);
  }

  /// @dev Internal function to get the value of close ratio, multiplied by 1e9.
  function _getCloseFeeRatio() internal view returns (uint256) {
    return fundingMiscData.decodeUint(CLOSE_FEE_RATIO_OFFSET, 30);
  }

  /// @dev Internal function to update the fee ratio for closing position.
  /// @param newRatio The close fee ratio value, multiplied by 1e9.
  function _updateCloseFeeRatio(uint256 newRatio) internal {
    _checkValueTooLarge(newRatio, FEE_PRECISION);

    bytes32 data = fundingMiscData;
    uint256 oldRatio = data.decodeUint(CLOSE_FEE_RATIO_OFFSET, 30);
    fundingMiscData = data.insertUint(newRatio, CLOSE_FEE_RATIO_OFFSET, 30);

    emit UpdateCloseFeeRatio(oldRatio, newRatio);
  }

  /// @dev Internal function to get the value of funding ratio, multiplied by 1e9.
  function _getFundingRatio() internal view returns (uint256) {
    return fundingMiscData.decodeUint(FUNDING_RATIO_OFFSET, 32);
  }

  /// @dev Internal function to update the funding ratio.
  /// @param newRatio The funding ratio value, multiplied by 1e9.
  function _updateFundingRatio(uint256 newRatio) internal {
    _checkValueTooLarge(newRatio, MAX_FUNDING_RATIO);

    bytes32 data = fundingMiscData;
    uint256 oldRatio = data.decodeUint(FUNDING_RATIO_OFFSET, 32);
    fundingMiscData = data.insertUint(newRatio, FUNDING_RATIO_OFFSET, 32);

    emit UpdateFundingRatio(oldRatio, newRatio);
  }

  /// @dev Internal function to return interest rate snapshot.
  /// @param snapshot The previous borrow index snapshot.
  /// @return newBorrowIndex The current borrow index, multiplied by 1e27.
  /// @return rate The annual interest rate, multiplied by 1e18.
  function _getAverageInterestRate(
    BorrowRateSnapshot memory snapshot
  ) internal view returns (uint256 newBorrowIndex, uint256 rate) {
    uint256 prevBorrowIndex = snapshot.borrowIndex;
    newBorrowIndex = IAaveV3Pool(lendingPool).getReserveNormalizedVariableDebt(baseAsset);
    // absolute rate change is (new - prev) / prev
    // annual interest rate is (new - prev) / prev / duration * 365 days
    uint256 duration = block.timestamp - snapshot.timestamp;
    // @note Users can trigger this every `MIN_SNAPSHOT_DELAY` seconds and make the interest rate never change.
    // We allow users to do so, since the risk is not very high. And if we remove this if, the computed interest
    // rate may not correct due to small `duration`.
    if (duration < MIN_SNAPSHOT_DELAY) {
      rate = snapshot.lastInterestRate;
    } else {
      rate = ((newBorrowIndex - prevBorrowIndex) * 365 days * PRECISION) / (prevBorrowIndex * duration);
      if (rate == 0) rate = snapshot.lastInterestRate;
    }
  }

  /// @dev Internal function to update interest rate snapshot.
  function _updateInterestRate(uint256 newBorrowIndex, uint256 lastInterestRate) internal {
    BorrowRateSnapshot memory snapshot = borrowRateSnapshot;
    snapshot.borrowIndex = uint128(newBorrowIndex);
    snapshot.lastInterestRate = uint80(lastInterestRate);
    snapshot.timestamp = uint48(block.timestamp);
    borrowRateSnapshot = snapshot;

    emit SnapshotAaveBorrowIndex(newBorrowIndex, block.timestamp);
  }

  /// @inheritdoc BasePool
  function _updateCollAndDebtIndex() internal virtual override returns (uint256 newCollIndex, uint256 newDebtIndex) {
    (newDebtIndex, newCollIndex) = _getDebtAndCollateralIndex();

    BorrowRateSnapshot memory snapshot = borrowRateSnapshot;
    uint256 duration = block.timestamp - snapshot.timestamp;
    if (duration > 0) {
      (uint256 borrowIndex, uint256 interestRate) = _getAverageInterestRate(snapshot);
      if (IPegKeeper(pegKeeper).isFundingEnabled()) {
        (, uint256 totalColls) = _getDebtAndCollateralShares();
        uint256 totalRawColls = _convertToRawColl(totalColls, newCollIndex, Math.Rounding.Down);
        uint256 funding = (totalRawColls * interestRate * duration) / (365 days * PRECISION);
        funding = ((funding * _getFundingRatio()) / FEE_PRECISION);

        // update collateral index with funding costs
        newCollIndex = (newCollIndex * totalRawColls) / (totalRawColls - funding);
        _updateCollateralIndex(newCollIndex);
      }

      // update interest snapshot
      _updateInterestRate(borrowIndex, interestRate);
    }
  }

  /// @inheritdoc BasePool
  function _deductProtocolFees(int256 rawColl) internal view virtual override returns (uint256) {
    if (rawColl > 0) {
      // open position or add collateral
      uint256 feeRatio = getOpenFeeRatio();
      if (feeRatio > FEE_PRECISION) feeRatio = FEE_PRECISION;
      return (uint256(rawColl) * feeRatio) / FEE_PRECISION;
    } else {
      // close position or remove collateral
      return (uint256(-rawColl) * _getCloseFeeRatio()) / FEE_PRECISION;
    }
  }
}
