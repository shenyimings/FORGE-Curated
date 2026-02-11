// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import { IPool } from "../../interfaces/IPool.sol";

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { PoolConstant } from "./PoolConstant.sol";
import { PoolErrors } from "./PoolErrors.sol";

abstract contract PoolStorage is ERC721Upgradeable, AccessControlUpgradeable, PoolConstant, PoolErrors {
  using WordCodec for bytes32;

  /*************
   * Constants *
   *************/

  /// @dev Below are offsets of each variables in `miscData`.
  uint256 private constant BORROW_FLAG_OFFSET = 0;
  uint256 private constant REDEEM_FLAG_OFFSET = 1;
  uint256 private constant TOP_TICK_OFFSET = 2;
  uint256 private constant NEXT_POSITION_OFFSET = 18;
  uint256 private constant NEXT_NODE_OFFSET = 50;
  uint256 private constant MIN_DEBT_RATIO_OFFSET = 98;
  uint256 private constant MAX_DEBT_RATIO_OFFSET = 158;
  uint256 private constant MAX_REDEEM_RATIO_OFFSET = 218;

  /// @dev Below are offsets of each variables in `rebalanceRatioData`.
  uint256 private constant REBALANCE_DEBT_RATIO_OFFSET = 0;
  uint256 private constant REBALANCE_BONUS_RATIO_OFFSET = 60;
  uint256 private constant LIQUIDATE_DEBT_RATIO_OFFSET = 90;
  uint256 private constant LIQUIDATE_BONUS_RATIO_OFFSET = 150;

  /// @dev Below are offsets of each variables in `indexData`.
  uint256 private constant DEBT_INDEX_OFFSET = 0;
  uint256 private constant COLLATERAL_INDEX_OFFSET = 128;

  /// @dev Below are offsets of each variables in `sharesData`.
  uint256 private constant DEBT_SHARES_OFFSET = 0;
  uint256 private constant COLLATERAL_SHARES_OFFSET = 128;

  /***********
   * Structs *
   ***********/

  /// @dev if nodeId = 0, tick is not used and this position only has collateral
  ///
  /// @param tick The tick this position belongs to at the beginning.
  /// @param nodeId The tree node id this position belongs to at the beginning.
  /// @param colls The collateral shares this position has.
  /// @param debts The debt shares this position has.
  struct PositionInfo {
    int16 tick;
    uint48 nodeId;
    // `uint96` is enough, since we use `86` bits in `PoolManager`.
    uint96 colls;
    // `uint96` is enough, since we use `96` bits in `PoolManager`.
    uint96 debts;
  }

  /// @dev The compiler will pack it into two `uint256`.
  /// @param metadata The metadata for tree node.
  ///   ```text
  ///   * Field           Bits    Index       Comments
  ///   * parent          48      0           The index for parent tree node.
  ///   * tick            16      48          The original tick for this tree node.
  ///   * coll ratio      64      64          The remained coll share ratio base on parent node, the value is real ratio * 2^60.
  ///   * debt ratio      64      128         The remained debt share ratio base on parent node, the value is real ratio * 2^60.
  ///   ```
  /// @param value The value for tree node
  ///   ```text
  ///   * Field           Bits    Index       Comments
  ///   * coll share      128     0           The original total coll share before rebalance or redeem.
  ///   * debt share      128     128         The original total debt share before rebalance or redeem.
  ///   ```
  struct TickTreeNode {
    bytes32 metadata;
    bytes32 value;
  }

  /*********************
   * Storage Variables *
   *********************/

  /// @inheritdoc IPool
  address public collateralToken;

  /// @inheritdoc IPool
  address public priceOracle;

  /// @dev `miscData` is a storage slot that can be used to store unrelated pieces of information.
  ///
  /// - The *borrow flag* indicates whether borrow fxUSD is allowed, 1 means paused.
  /// - The *redeem flag* indicates whether redeem fxUSD is allowed, 1 means paused.
  /// - The *top tick* is the largest tick with debts.
  /// - The *next position* is the next unassigned position id.
  /// - The *next node* is the next unassigned tree node id.
  /// - The *min debt ratio* is the minimum allowed debt ratio, multiplied by 1e18.
  /// - The *max debt ratio* is the maximum allowed debt ratio, multiplied by 1e18.
  /// - The *max redeem ratio* is the maximum allowed redeem ratio per tick, multiplied by 1e9.
  ///
  /// [ borrow flag | redeem flag | top tick | next position | next node | min debt ratio | max debt ratio | max redeem ratio | reserved ]
  /// [    1 bit    |    1 bit    | 16  bits |    32 bits    |  48 bits  |    60  bits    |    60  bits    |      30 bits     |  8 bits  ]
  /// [ MSB                                                                                                                          LSB ]
  bytes32 private miscData;

  /// @dev `rebalanceRatioData` is a storage slot used to store rebalance and liquidate information.
  ///
  /// - The *rebalance debt ratio* is the min debt ratio to start rebalance, multiplied by 1e18.
  /// - The *rebalance bonus ratio* is the bonus ratio during rebalance, multiplied by 1e9.
  /// - The *liquidate debt ratio* is the min debt ratio to start liquidate, multiplied by 1e18.
  /// - The *liquidate bonus ratio* is the bonus ratio during liquidate, multiplied by 1e9.
  ///
  /// [ rebalance debt ratio | rebalance bonus ratio | liquidate debt ratio | liquidate bonus ratio | reserved ]
  /// [       60  bits       |        30 bits        |       60  bits       |        30 bits        | 76  bits ]
  /// [ MSB                                                                                                LSB ]
  bytes32 private rebalanceRatioData;

  /// @dev `indexData` is a storage slot used to store debt/collateral index.
  ///
  /// - The *debt index* is the index for each debt shares, only increasing, starting from 2^96, max 2^128-1.
  /// - The *collateral index* is the index for each collateral shares, only increasing, starting from 2^96, max 2^128-1
  ///
  /// [ debt index | collateral index ]
  /// [  128 bits  |     128 bits     ]
  /// [ MSB                       LSB ]
  bytes32 private indexData;

  /// @dev `sharesData` is a storage slot used to store debt/collateral shares.
  ///
  /// - The *debt shares* is the total debt shares. The actual number of total debts
  ///   is `<debt shares> * <debt index>`.
  /// - The *collateral shares* is the total collateral shares. The actual number of
  ///   total collateral is `<collateral shares> / <collateral index>`.
  ///
  /// [ debt shares | collateral shares ]
  /// [  128  bits  |     128  bits     ]
  /// [ MSB                         LSB ]
  bytes32 private sharesData;

  /// @dev Mapping from position id to position information.
  mapping(uint256 => PositionInfo) public positionData;

  /// @dev Mapping from position id to position metadata.
  /// [ open timestamp | reserved ]
  /// [    40  bits    | 216 bits ]
  /// [ MSB                   LSB ]
  mapping(uint256 => bytes32) public positionMetadata;

  /// @dev The bitmap for ticks with debts.
  mapping(int8 => uint256) public tickBitmap;

  /// @dev Mapping from tick to tree node id.
  mapping(int256 => uint48) public tickData;

  /// @dev Mapping from tree node id to tree node data.
  mapping(uint256 => TickTreeNode) public tickTreeData;

  /***************
   * Constructor *
   ***************/

  function __PoolStorage_init(address _collateralToken, address _priceOracle) internal onlyInitializing {
    _checkAddressNotZero(_collateralToken);

    collateralToken = _collateralToken;
    _updatePriceOracle(_priceOracle);
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @inheritdoc AccessControlUpgradeable
  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual override(AccessControlUpgradeable, ERC721Upgradeable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  /// @inheritdoc IPool
  function isBorrowPaused() external view returns (bool) {
    return _isBorrowPaused();
  }

  /// @inheritdoc IPool
  function isRedeemPaused() external view returns (bool) {
    return _isRedeemPaused();
  }

  /// @inheritdoc IPool
  function getTopTick() external view returns (int16) {
    return _getTopTick();
  }

  /// @inheritdoc IPool
  function getNextPositionId() external view returns (uint32) {
    return _getNextPositionId();
  }

  /// @inheritdoc IPool
  function getNextTreeNodeId() external view returns (uint48) {
    return _getNextTreeNodeId();
  }

  /// @inheritdoc IPool
  function getDebtRatioRange() external view returns (uint256, uint256) {
    return _getDebtRatioRange();
  }

  /// @inheritdoc IPool
  function getMaxRedeemRatioPerTick() external view returns (uint256) {
    return _getMaxRedeemRatioPerTick();
  }

  /// @inheritdoc IPool
  function getRebalanceRatios() external view returns (uint256, uint256) {
    return _getRebalanceRatios();
  }

  /// @inheritdoc IPool
  function getLiquidateRatios() external view returns (uint256, uint256) {
    return _getLiquidateRatios();
  }

  /// @inheritdoc IPool
  function getDebtAndCollateralIndex() external view returns (uint256, uint256) {
    return _getDebtAndCollateralIndex();
  }

  /// @inheritdoc IPool
  function getDebtAndCollateralShares() external view returns (uint256, uint256) {
    return _getDebtAndCollateralShares();
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to update price oracle.
  /// @param newOracle The address of new price oracle;
  function _updatePriceOracle(address newOracle) internal {
    _checkAddressNotZero(newOracle);

    address oldOracle = priceOracle;
    priceOracle = newOracle;

    emit UpdatePriceOracle(oldOracle, newOracle);
  }

  /*************************************
   * Internal Functions For `miscData` *
   *************************************/

  /// @dev Internal function to get the borrow pause status.
  function _isBorrowPaused() internal view returns (bool) {
    return miscData.decodeBool(BORROW_FLAG_OFFSET);
  }

  /// @dev Internal function to update borrow pause status.
  /// @param status The status to update.
  function _updateBorrowStatus(bool status) internal {
    miscData = miscData.insertBool(status, BORROW_FLAG_OFFSET);

    emit UpdateBorrowStatus(status);
  }

  /// @dev Internal function to get the redeem pause status.
  function _isRedeemPaused() internal view returns (bool) {
    return miscData.decodeBool(REDEEM_FLAG_OFFSET);
  }

  /// @dev Internal function to update redeem pause status.
  /// @param status The status to update.
  function _updateRedeemStatus(bool status) internal {
    miscData = miscData.insertBool(status, REDEEM_FLAG_OFFSET);

    emit UpdateRedeemStatus(status);
  }

  /// @dev Internal function to get the value of top tick.
  function _getTopTick() internal view returns (int16) {
    return int16(miscData.decodeInt(TOP_TICK_OFFSET, 16));
  }

  /// @dev Internal function to update the top tick.
  /// @param tick The new top tick.
  function _updateTopTick(int16 tick) internal {
    miscData = miscData.insertInt(tick, TOP_TICK_OFFSET, 16);
  }

  /// @dev Internal function to get next available position id.
  function _getNextPositionId() internal view returns (uint32) {
    return uint32(miscData.decodeUint(NEXT_POSITION_OFFSET, 32));
  }

  /// @dev Internal function to update next available position id.
  /// @param id The position id to update.
  function _updateNextPositionId(uint32 id) internal {
    miscData = miscData.insertUint(id, NEXT_POSITION_OFFSET, 32);
  }

  /// @dev Internal function to get next available tree node id.
  function _getNextTreeNodeId() internal view returns (uint48) {
    return uint48(miscData.decodeUint(NEXT_NODE_OFFSET, 48));
  }

  /// @dev Internal function to update next available tree node id.
  /// @param id The tree node id to update.
  function _updateNextTreeNodeId(uint48 id) internal {
    miscData = miscData.insertUint(id, NEXT_NODE_OFFSET, 48);
  }

  /// @dev Internal function to get `minDebtRatio` and `maxDebtRatio`, both multiplied by 1e18.
  function _getDebtRatioRange() internal view returns (uint256 minDebtRatio, uint256 maxDebtRatio) {
    bytes32 data = miscData;
    minDebtRatio = data.decodeUint(MIN_DEBT_RATIO_OFFSET, 60);
    maxDebtRatio = data.decodeUint(MAX_DEBT_RATIO_OFFSET, 60);
  }

  /// @dev Internal function to update debt ratio range.
  /// @param minDebtRatio The minimum allowed debt ratio to update, multiplied by 1e18.
  /// @param maxDebtRatio The maximum allowed debt ratio to update, multiplied by 1e18.
  function _updateDebtRatioRange(uint256 minDebtRatio, uint256 maxDebtRatio) internal {
    _checkValueTooLarge(minDebtRatio, maxDebtRatio);
    _checkValueTooLarge(maxDebtRatio, PRECISION);

    bytes32 data = miscData;
    data = data.insertUint(minDebtRatio, MIN_DEBT_RATIO_OFFSET, 60);
    miscData = data.insertUint(maxDebtRatio, MAX_DEBT_RATIO_OFFSET, 60);

    emit UpdateDebtRatioRange(minDebtRatio, maxDebtRatio);
  }

  /// @dev Internal function to get the `maxRedeemRatioPerTick`.
  function _getMaxRedeemRatioPerTick() internal view returns (uint256) {
    return miscData.decodeUint(MAX_REDEEM_RATIO_OFFSET, 30);
  }

  /// @dev Internal function to update maximum redeem ratio per tick.
  /// @param ratio The ratio to update, multiplied by 1e9.
  function _updateMaxRedeemRatioPerTick(uint256 ratio) internal {
    _checkValueTooLarge(ratio, FEE_PRECISION);

    miscData = miscData.insertUint(ratio, MAX_REDEEM_RATIO_OFFSET, 30);

    emit UpdateMaxRedeemRatioPerTick(ratio);
  }

  /***********************************************
   * Internal Functions For `rebalanceRatioData` *
   ***********************************************/

  /// @dev Internal function to get `debtRatio` and `bonusRatio` for rebalance.
  /// @return debtRatio The minimum debt ratio to start rebalance, multiplied by 1e18.
  /// @return bonusRatio The bonus ratio during rebalance, multiplied by 1e9.
  function _getRebalanceRatios() internal view returns (uint256 debtRatio, uint256 bonusRatio) {
    bytes32 data = rebalanceRatioData;
    debtRatio = data.decodeUint(REBALANCE_DEBT_RATIO_OFFSET, 60);
    bonusRatio = data.decodeUint(REBALANCE_BONUS_RATIO_OFFSET, 30);
  }

  /// @dev Internal function to update ratio for rebalance.
  /// @param debtRatio The minimum debt ratio to start rebalance, multiplied by 1e18.
  /// @param bonusRatio The bonus ratio during rebalance, multiplied by 1e9.
  function _updateRebalanceRatios(uint256 debtRatio, uint256 bonusRatio) internal {
    _checkValueTooLarge(debtRatio, PRECISION);
    _checkValueTooLarge(bonusRatio, FEE_PRECISION);

    bytes32 data = rebalanceRatioData;
    data = data.insertUint(debtRatio, REBALANCE_DEBT_RATIO_OFFSET, 60);
    rebalanceRatioData = data.insertUint(bonusRatio, REBALANCE_BONUS_RATIO_OFFSET, 30);

    emit UpdateRebalanceRatios(debtRatio, bonusRatio);
  }

  /// @dev Internal function to get `debtRatio` and `bonusRatio` for liquidate.
  /// @return debtRatio The minimum debt ratio to start liquidate, multiplied by 1e18.
  /// @return bonusRatio The bonus ratio during liquidate, multiplied by 1e9.
  function _getLiquidateRatios() internal view returns (uint256 debtRatio, uint256 bonusRatio) {
    bytes32 data = rebalanceRatioData;
    debtRatio = data.decodeUint(LIQUIDATE_DEBT_RATIO_OFFSET, 60);
    bonusRatio = data.decodeUint(LIQUIDATE_BONUS_RATIO_OFFSET, 30);
  }

  /// @dev Internal function to update ratio for liquidate.
  /// @param debtRatio The minimum debt ratio to start liquidate, multiplied by 1e18.
  /// @param bonusRatio The bonus ratio during liquidate, multiplied by 1e9.
  function _updateLiquidateRatios(uint256 debtRatio, uint256 bonusRatio) internal {
    _checkValueTooLarge(debtRatio, PRECISION);
    _checkValueTooLarge(bonusRatio, FEE_PRECISION);

    bytes32 data = rebalanceRatioData;
    data = data.insertUint(debtRatio, LIQUIDATE_DEBT_RATIO_OFFSET, 60);
    rebalanceRatioData = data.insertUint(bonusRatio, LIQUIDATE_BONUS_RATIO_OFFSET, 30);

    emit UpdateLiquidateRatios(debtRatio, bonusRatio);
  }

  /**************************************
   * Internal Functions For `indexData` *
   **************************************/

  /// @dev Internal function to get debt and collateral index.
  /// @return debtIndex The index for debt shares.
  /// @return collIndex The index for collateral shares.
  function _getDebtAndCollateralIndex() internal view returns (uint256 debtIndex, uint256 collIndex) {
    bytes32 data = indexData;
    debtIndex = data.decodeUint(DEBT_INDEX_OFFSET, 128);
    collIndex = data.decodeUint(COLLATERAL_INDEX_OFFSET, 128);
  }

  /// @dev Internal function to update debt index.
  /// @param index The debt index to update.
  function _updateDebtIndex(uint256 index) internal {
    indexData = indexData.insertUint(index, DEBT_INDEX_OFFSET, 128);

    emit DebtIndexSnapshot(index);
  }

  /// @dev Internal function to update collateral index.
  /// @param index The collateral index to update.
  function _updateCollateralIndex(uint256 index) internal {
    indexData = indexData.insertUint(index, COLLATERAL_INDEX_OFFSET, 128);

    emit CollateralIndexSnapshot(index);
  }

  /**************************************
   * Internal Functions For `sharesData` *
   **************************************/

  /// @dev Internal function to get debt and collateral shares.
  /// @return debtShares The total number of debt shares.
  /// @return collShares The total number of collateral shares.
  function _getDebtAndCollateralShares() internal view returns (uint256 debtShares, uint256 collShares) {
    bytes32 data = sharesData;
    debtShares = data.decodeUint(DEBT_SHARES_OFFSET, 128);
    collShares = data.decodeUint(COLLATERAL_SHARES_OFFSET, 128);
  }

  /// @dev Internal function to update debt and collateral shares.
  /// @param debtShares The debt shares to update.
  /// @param collShares The collateral shares to update.
  function _updateDebtAndCollateralShares(uint256 debtShares, uint256 collShares) internal {
    bytes32 data = sharesData;
    data = data.insertUint(debtShares, DEBT_SHARES_OFFSET, 128);
    sharesData = data.insertUint(collShares, COLLATERAL_SHARES_OFFSET, 128);
  }

  /// @dev Internal function to update debt shares.
  /// @param shares The debt shares to update.
  function _updateDebtShares(uint256 shares) internal {
    sharesData = sharesData.insertUint(shares, DEBT_SHARES_OFFSET, 128);
  }

  /// @dev Internal function to update collateral shares.
  /// @param shares The collateral shares to update.
  function _updateCollateralShares(uint256 shares) internal {
    sharesData = sharesData.insertUint(shares, COLLATERAL_SHARES_OFFSET, 128);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   */
  uint256[40] private __gap;
}
