// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { TickBitmap } from "../../libraries/TickBitmap.sol";
import { TickMath } from "../../libraries/TickMath.sol";
import { PoolStorage } from "./PoolStorage.sol";

abstract contract TickLogic is PoolStorage {
  using TickBitmap for mapping(int8 => uint256);
  using WordCodec for bytes32;

  /*************
   * Constants *
   *************/

  /// @dev Below are offsets of each variables in `TickTreeNode.metadata`.
  uint256 private constant PARENT_OFFSET = 0;
  uint256 private constant TICK_OFFSET = 48;
  uint256 private constant COLL_RATIO_OFFSET = 64;
  uint256 private constant DEBT_RATIO_OFFSET = 128;

  /// @dev Below are offsets of each variables in `TickTreeNode.value`.
  uint256 internal constant COLL_SHARE_OFFSET = 0;
  uint256 internal constant DEBT_SHARE_OFFSET = 128;

  /***************
   * Constructor *
   ***************/

  function __TickLogic_init() internal onlyInitializing {
    _updateNextTreeNodeId(1);
    _updateTopTick(type(int16).min);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to get the root of the given tree node.
  /// @param node The id of the given tree node.
  /// @return root The root node id.
  /// @return collRatio The actual collateral ratio of the given node, multiplied by 2^60.
  /// @return debtRatio The actual debt ratio of the given node, multiplied by 2^60.
  function _getRootNode(uint256 node) internal view returns (uint256 root, uint256 collRatio, uint256 debtRatio) {
    collRatio = E60;
    debtRatio = E60;
    while (true) {
      bytes32 metadata = tickTreeData[node].metadata;
      uint256 parent = metadata.decodeUint(PARENT_OFFSET, 48);
      collRatio = (collRatio * metadata.decodeUint(COLL_RATIO_OFFSET, 64)) >> 60;
      debtRatio = (debtRatio * metadata.decodeUint(DEBT_RATIO_OFFSET, 64)) >> 60;
      if (parent == 0) break;
      node = parent;
    }
    root = node;
  }

  /// @dev Internal function to get the root of the given tree node and compress path.
  /// @param node The id of the given tree node.
  /// @return root The root node id.
  /// @return collRatio The actual collateral ratio of the given node, multiplied by 2^60.
  /// @return debtRatio The actual debt ratio of the given node, multiplied by 2^60.
  function _getRootNodeAndCompress(uint256 node) internal returns (uint256 root, uint256 collRatio, uint256 debtRatio) {
    // @note We can change it to non-recursive version to avoid stack overflow. Normally, the depth should be `log(n)`,
    // where `n` is the total number of tree nodes. So we don't need to worry much about this.
    bytes32 metadata = tickTreeData[node].metadata;
    uint256 parent = metadata.decodeUint(PARENT_OFFSET, 48);
    collRatio = metadata.decodeUint(COLL_RATIO_OFFSET, 64);
    debtRatio = metadata.decodeUint(DEBT_RATIO_OFFSET, 64);
    if (parent == 0) {
      root = node;
    } else {
      uint256 collRatioCompressed;
      uint256 debtRatioCompressed;
      (root, collRatioCompressed, debtRatioCompressed) = _getRootNodeAndCompress(parent);
      collRatio = (collRatio * collRatioCompressed) >> 60;
      debtRatio = (debtRatio * debtRatioCompressed) >> 60;
      metadata = metadata.insertUint(root, PARENT_OFFSET, 48);
      metadata = metadata.insertUint(collRatio, COLL_RATIO_OFFSET, 64);
      metadata = metadata.insertUint(debtRatio, DEBT_RATIO_OFFSET, 64);
      tickTreeData[node].metadata = metadata;
    }
  }

  /// @dev Internal function to create a new tree node.
  /// @param tick The tick where this tree node belongs to.
  /// @return node The created tree node id.
  function _newTickTreeNode(int16 tick) internal returns (uint48 node) {
    unchecked {
      node = _getNextTreeNodeId();
      _updateNextTreeNodeId(node + 1);
    }
    tickData[tick] = node;

    bytes32 metadata = bytes32(0);
    metadata = metadata.insertInt(tick, TICK_OFFSET, 16); // set tick
    metadata = metadata.insertUint(E60, COLL_RATIO_OFFSET, 64); // set coll ratio
    metadata = metadata.insertUint(E60, DEBT_RATIO_OFFSET, 64); // set debt ratio
    tickTreeData[node].metadata = metadata;
  }

  /// @dev Internal function to find first tick such that `TickMath.getRatioAtTick(tick) >= debts/colls`.
  /// @param colls The collateral shares.
  /// @param debts The debt shares.
  /// @return tick The value of found first tick.
  function _getTick(uint256 colls, uint256 debts) internal pure returns (int256 tick) {
    uint256 ratio = (debts * TickMath.ZERO_TICK_SCALED_RATIO) / colls;
    uint256 ratioAtTick;
    (tick, ratioAtTick) = TickMath.getTickAtRatio(ratio);
    if (ratio != ratioAtTick) {
      tick++;
      ratio = (ratioAtTick * 10015) / 10000;
    }
  }

  /// @dev Internal function to retrieve or create a tree node.
  /// @param tick The tick where this tree node belongs to.
  /// @return node The tree node id.
  function _getOrCreateTickNode(int256 tick) internal returns (uint48 node) {
    node = tickData[tick];
    if (node == 0) {
      node = _newTickTreeNode(int16(tick));
    }
  }

  /// @dev Internal function to add position collaterals and debts to some tick.
  /// @param colls The collateral shares.
  /// @param debts The debt shares.
  /// @param checkDebts Whether we should check the value of `debts`.
  /// @return tick The tick where this position belongs to.
  /// @return node The corresponding tree node id for this tick.
  function _addPositionToTick(
    uint256 colls,
    uint256 debts,
    bool checkDebts
  ) internal returns (int256 tick, uint48 node) {
    if (debts > 0) {
      if (checkDebts && int256(debts) < MIN_DEBT) {
        revert ErrorDebtTooSmall();
      }

      tick = _getTick(colls, debts);
      node = _getOrCreateTickNode(tick);
      bytes32 value = tickTreeData[node].value;
      uint256 newColls = value.decodeUint(COLL_SHARE_OFFSET, 128) + colls;
      uint256 newDebts = value.decodeUint(DEBT_SHARE_OFFSET, 128) + debts;
      value = value.insertUint(newColls, COLL_SHARE_OFFSET, 128);
      value = value.insertUint(newDebts, DEBT_SHARE_OFFSET, 128);
      tickTreeData[node].value = value;

      if (newDebts == debts) {
        tickBitmap.flipTick(int16(tick));
      }

      // update top tick
      if (tick > _getTopTick()) {
        _updateTopTick(int16(tick));
      }
    }
  }

  /// @dev Internal function to remove position from tick.
  /// @param position The position struct to remove.
  function _removePositionFromTick(PositionInfo memory position) internal {
    if (position.nodeId == 0) return;

    bytes32 value = tickTreeData[position.nodeId].value;
    uint256 oldDebts = value.decodeUint(DEBT_SHARE_OFFSET, 128);
    uint256 newColls = value.decodeUint(COLL_SHARE_OFFSET, 128) - position.colls;
    uint256 newDebts = oldDebts - position.debts;
    value = value.insertUint(newColls, COLL_SHARE_OFFSET, 128);
    value = value.insertUint(newDebts, DEBT_SHARE_OFFSET, 128);
    tickTreeData[position.nodeId].value = value;

    if (newDebts == 0 && oldDebts > 0) {
      int16 tick = int16(tickTreeData[position.nodeId].metadata.decodeInt(TICK_OFFSET, 16));
      tickBitmap.flipTick(tick);

      // top tick gone, update it to new one
      int16 topTick = _getTopTick();
      if (topTick == tick) {
        _resetTopTick(topTick);
      }
    }
  }

  /// @dev Internal function to liquidate a tick.
  ///      The caller make sure `max(liquidatedColl, liquidatedDebt) > 0`.
  ///
  /// @param tick The id of tick to liquidate.
  /// @param liquidatedColl The amount of collateral shares liquidated.
  /// @param liquidatedDebt The amount of debt shares liquidated.
  function _liquidateTick(int16 tick, uint256 liquidatedColl, uint256 liquidatedDebt, uint256 price) internal {
    uint48 node = tickData[tick];
    // create new tree node for this tick
    _newTickTreeNode(tick);
    // clear bitmap first, and it will be updated later if needed.
    tickBitmap.flipTick(tick);

    bytes32 value = tickTreeData[node].value;
    bytes32 metadata = tickTreeData[node].metadata;
    uint256 tickColl = value.decodeUint(COLL_SHARE_OFFSET, 128);
    uint256 tickDebt = value.decodeUint(DEBT_SHARE_OFFSET, 128);
    uint256 tickCollAfter = tickColl - liquidatedColl;
    uint256 tickDebtAfter = tickDebt - liquidatedDebt;
    uint256 collRatio = (tickCollAfter * E60) / tickColl;
    uint256 debtRatio = (tickDebtAfter * E60) / tickDebt;

    // update metadata
    metadata = metadata.insertUint(collRatio, COLL_RATIO_OFFSET, 64);
    metadata = metadata.insertUint(debtRatio, DEBT_RATIO_OFFSET, 64);

    int256 newTick = type(int256).min;
    if (tickDebtAfter > 0) {
      // partial liquidated, move funds to another tick
      uint48 parentNode;
      (newTick, parentNode) = _addPositionToTick(tickCollAfter, tickDebtAfter, false);
      metadata = metadata.insertUint(parentNode, PARENT_OFFSET, 48);
    }
    if (newTick == type(int256).min) {
      emit TickMovement(tick, type(int16).min, tickCollAfter, tickDebtAfter, price);
    } else {
      emit TickMovement(tick, int16(newTick), tickCollAfter, tickDebtAfter, price);
    }

    // top tick liquidated, update it to new one
    int16 topTick = _getTopTick();
    if (topTick == tick && newTick != int256(tick)) {
      _resetTopTick(topTick);
    }
    tickTreeData[node].metadata = metadata;
  }

  /// @dev Internal function to reset top tick.
  /// @param oldTopTick The previous value of top tick.
  function _resetTopTick(int16 oldTopTick) internal {
    while (oldTopTick > type(int16).min) {
      bool hasDebt;
      (oldTopTick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(oldTopTick - 1);
      if (hasDebt) break;
    }
    _updateTopTick(oldTopTick);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   */
  uint256[50] private __gap;
}
