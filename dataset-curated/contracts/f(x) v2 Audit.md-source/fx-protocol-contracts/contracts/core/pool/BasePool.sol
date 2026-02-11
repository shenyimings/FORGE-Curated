// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IPegKeeper } from "../../interfaces/IPegKeeper.sol";
import { IPool } from "../../interfaces/IPool.sol";
import { IPoolManager } from "../../interfaces/IPoolManager.sol";
import { IPriceOracle } from "../../price-oracle/interfaces/IPriceOracle.sol";

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { Math } from "../../libraries/Math.sol";
import { TickBitmap } from "../../libraries/TickBitmap.sol";
import { PositionLogic } from "./PositionLogic.sol";
import { TickLogic } from "./TickLogic.sol";

abstract contract BasePool is TickLogic, PositionLogic {
  using TickBitmap for mapping(int8 => uint256);
  using WordCodec for bytes32;

  /***********
   * Structs *
   ***********/

  struct OperationMemoryVar {
    int256 tick;
    uint48 node;
    uint256 positionColl;
    uint256 positionDebt;
    int256 newColl;
    int256 newDebt;
    uint256 collIndex;
    uint256 debtIndex;
    uint256 globalColl;
    uint256 globalDebt;
    uint256 price;
  }

  /*************
   * Modifiers *
   *************/

  modifier onlyPoolManager() {
    if (_msgSender() != poolManager) {
      revert ErrorCallerNotPoolManager();
    }
    _;
  }

  /***************
   * Constructor *
   ***************/

  constructor(address _poolManager) {
    _checkAddressNotZero(_poolManager);

    poolManager = _poolManager;
    fxUSD = IPoolManager(_poolManager).fxUSD();
    pegKeeper = IPoolManager(_poolManager).pegKeeper();
  }

  function __BasePool_init() internal onlyInitializing {
    _updateDebtIndex(E96);
    _updateCollateralIndex(E96);
    _updateDebtRatioRange(500000000000000000, 857142857142857142); // 1/2 ~ 6/7
    _updateMaxRedeemRatioPerTick(200000000); // 20%
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @inheritdoc IPool
  function operate(
    uint256 positionId,
    int256 newRawColl,
    int256 newRawDebt,
    address owner
  ) external onlyPoolManager returns (uint256, int256, int256, uint256) {
    if (newRawColl == 0 && newRawDebt == 0) revert ErrorNoSupplyAndNoBorrow();
    if (newRawColl != 0 && (newRawColl > -MIN_COLLATERAL && newRawColl < MIN_COLLATERAL)) {
      revert ErrorCollateralTooSmall();
    }
    if (newRawDebt != 0 && (newRawDebt > -MIN_DEBT && newRawDebt < MIN_DEBT)) {
      revert ErrorDebtTooSmall();
    }
    if (newRawDebt > 0 && (_isBorrowPaused() || !IPegKeeper(pegKeeper).isBorrowAllowed())) {
      revert ErrorBorrowPaused();
    }

    OperationMemoryVar memory op;
    // price precision and ratio precision are both 1e18, use min price here
    op.price = IPriceOracle(priceOracle).getExchangePrice();
    (op.globalDebt, op.globalColl) = _getDebtAndCollateralShares();
    (op.collIndex, op.debtIndex) = _updateCollAndDebtIndex();
    if (positionId == 0) {
      positionId = _mintPosition(owner);
    } else {
      // make sure position is owned and check owner only in case of withdraw or borrow
      if (ownerOf(positionId) != owner && (newRawColl < 0 || newRawDebt > 0)) {
        revert ErrorNotPositionOwner();
      }
      PositionInfo memory position = _getAndUpdatePosition(positionId);
      // temporarily remove position from tick tree for simplicity
      _removePositionFromTick(position);
      op.tick = position.tick;
      op.node = position.nodeId;
      op.positionDebt = position.debts;
      op.positionColl = position.colls;

      // cannot withdraw or borrow when the position is above liquidation ratio
      if (newRawColl < 0 || newRawDebt > 0) {
        uint256 rawColls = _convertToRawColl(op.positionColl, op.collIndex, Math.Rounding.Down);
        uint256 rawDebts = _convertToRawDebt(op.positionDebt, op.debtIndex, Math.Rounding.Down);
        (uint256 debtRatio, ) = _getLiquidateRatios();
        if (rawDebts * PRECISION * PRECISION > debtRatio * rawColls * op.price) revert ErrorPositionInLiquidationMode();
      }
    }

    uint256 protocolFees;
    // supply or withdraw
    if (newRawColl > 0) {
      protocolFees = _deductProtocolFees(newRawColl);
      newRawColl -= int256(protocolFees);
      op.newColl = int256(_convertToCollShares(uint256(newRawColl), op.collIndex, Math.Rounding.Down));
      op.positionColl += uint256(op.newColl);
      op.globalColl += uint256(op.newColl);
    } else if (newRawColl < 0) {
      if (newRawColl == type(int256).min) {
        // this is max withdraw
        newRawColl = -int256(_convertToRawColl(op.positionColl, op.collIndex, Math.Rounding.Down));
        op.newColl = -int256(op.positionColl);
      } else {
        // this is partial withdraw, rounding up removing extra wei from collateral
        op.newColl = -int256(_convertToCollShares(uint256(-newRawColl), op.collIndex, Math.Rounding.Up));
        if (uint256(-op.newColl) > op.positionColl) revert ErrorWithdrawExceedSupply();
      }
      unchecked {
        op.positionColl -= uint256(-op.newColl);
        op.globalColl -= uint256(-op.newColl);
      }
      protocolFees = _deductProtocolFees(newRawColl);
      newRawColl += int256(protocolFees);
    }

    // borrow or repay
    if (newRawDebt > 0) {
      // rounding up adding extra wei in debt
      op.newDebt = int256(_convertToDebtShares(uint256(newRawDebt), op.debtIndex, Math.Rounding.Up));
      op.positionDebt += uint256(op.newDebt);
      op.globalDebt += uint256(op.newDebt);
    } else if (newRawDebt < 0) {
      if (newRawDebt == type(int256).min) {
        // this is max repay, rounding up amount that will be transferred in to pay back full debt:
        // subtracting -1 of negative debtAmount newDebt_ for safe rounding (increasing payback)
        newRawDebt = -int256(_convertToRawDebt(op.positionDebt, op.debtIndex, Math.Rounding.Up));
        op.newDebt = -int256(op.positionDebt);
      } else {
        // this is partial repay, safe rounding up negative amount to rounding reduce payback
        op.newDebt = -int256(_convertToDebtShares(uint256(-newRawDebt), op.debtIndex, Math.Rounding.Up));
      }
      op.positionDebt -= uint256(-op.newDebt);
      op.globalDebt -= uint256(-op.newDebt);
    }

    // final debt ratio check
    {
      // check position debt ratio is between `minDebtRatio` and `maxDebtRatio`.
      uint256 rawColls = _convertToRawColl(op.positionColl, op.collIndex, Math.Rounding.Down);
      uint256 rawDebts = _convertToRawDebt(op.positionDebt, op.debtIndex, Math.Rounding.Down);
      (uint256 minDebtRatio, uint256 maxDebtRatio) = _getDebtRatioRange();
      if (rawDebts * PRECISION * PRECISION > maxDebtRatio * rawColls * op.price) revert ErrorDebtRatioTooLarge();
      if (rawDebts * PRECISION * PRECISION < minDebtRatio * rawColls * op.price) revert ErrorDebtRatioTooSmall();
    }

    // update position state to storage
    (op.tick, op.node) = _addPositionToTick(op.positionColl, op.positionDebt, true);

    if (op.positionColl > type(uint96).max) revert ErrorOverflow();
    if (op.positionDebt > type(uint96).max) revert ErrorOverflow();
    positionData[positionId] = PositionInfo(int16(op.tick), op.node, uint96(op.positionColl), uint96(op.positionDebt));

    // update global state to storage
    _updateDebtAndCollateralShares(op.globalDebt, op.globalColl);

    emit PositionSnapshot(positionId, int16(op.tick), op.positionColl, op.positionDebt, op.price);

    return (positionId, newRawColl, newRawDebt, protocolFees);
  }

  /// @inheritdoc IPool
  function redeem(uint256 rawDebts) external onlyPoolManager returns (uint256 rawColls) {
    if (_isRedeemPaused()) revert ErrorRedeemPaused();

    (uint256 cachedCollIndex, uint256 cachedDebtIndex) = _updateCollAndDebtIndex();
    (uint256 cachedTotalDebts, uint256 cachedTotalColls) = _getDebtAndCollateralShares();
    uint256 price = IPriceOracle(priceOracle).getRedeemPrice();
    // check global debt ratio, if global debt ratio >= 1, disable redeem
    {
      uint256 totalRawColls = _convertToRawColl(cachedTotalColls, cachedCollIndex, Math.Rounding.Down);
      uint256 totalRawDebts = _convertToRawDebt(cachedTotalDebts, cachedDebtIndex, Math.Rounding.Down);
      if (totalRawDebts * PRECISION >= totalRawColls * price) revert ErrorPoolUnderCollateral();
    }

    int16 tick = _getTopTick();
    bool hasDebt = true;
    uint256 debtShare = _convertToDebtShares(rawDebts, cachedDebtIndex, Math.Rounding.Down);
    while (debtShare > 0) {
      if (!hasDebt) {
        (tick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(tick - 1);
      } else {
        uint256 node = tickData[tick];
        bytes32 value = tickTreeData[node].value;
        uint256 tickDebtShare = value.decodeUint(DEBT_SHARE_OFFSET, 128);
        // skip bad debt
        {
          uint256 tickCollShare = value.decodeUint(COLL_SHARE_OFFSET, 128);
          if (
            _convertToRawDebt(tickDebtShare, cachedDebtIndex, Math.Rounding.Down) * PRECISION >
            _convertToRawColl(tickCollShare, cachedCollIndex, Math.Rounding.Down) * price
          ) {
            hasDebt = false;
            tick = tick;
            continue;
          }
        }

        // redeem at most `maxRedeemRatioPerTick`
        uint256 debtShareToRedeem = (tickDebtShare * _getMaxRedeemRatioPerTick()) / FEE_PRECISION;
        if (debtShareToRedeem > debtShare) debtShareToRedeem = debtShare;
        uint256 rawCollRedeemed = (_convertToRawDebt(debtShareToRedeem, cachedDebtIndex, Math.Rounding.Down) *
          PRECISION) / price;
        uint256 collShareRedeemed = _convertToCollShares(rawCollRedeemed, cachedCollIndex, Math.Rounding.Down);
        _liquidateTick(tick, collShareRedeemed, debtShareToRedeem, price);
        debtShare -= debtShareToRedeem;
        rawColls += rawCollRedeemed;

        cachedTotalColls -= collShareRedeemed;
        cachedTotalDebts -= debtShareToRedeem;

        (tick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(tick - 1);
      }
      if (tick == type(int16).min) break;
    }
    _updateDebtAndCollateralShares(cachedTotalDebts, cachedTotalColls);
  }

  /// @inheritdoc IPool
  function rebalance(int16 tick, uint256 maxRawDebts) external onlyPoolManager returns (RebalanceResult memory result) {
    (uint256 cachedCollIndex, uint256 cachedDebtIndex) = _updateCollAndDebtIndex();
    (, uint256 price, ) = IPriceOracle(priceOracle).getPrice(); // use min price
    uint256 node = tickData[tick];
    bytes32 value = tickTreeData[node].value;
    uint256 tickRawColl = _convertToRawColl(
      value.decodeUint(COLL_SHARE_OFFSET, 128),
      cachedCollIndex,
      Math.Rounding.Down
    );
    uint256 tickRawDebt = _convertToRawDebt(
      value.decodeUint(DEBT_SHARE_OFFSET, 128),
      cachedDebtIndex,
      Math.Rounding.Down
    );
    (uint256 rebalanceDebtRatio, uint256 rebalanceBonusRatio) = _getRebalanceRatios();
    (uint256 liquidateDebtRatio, ) = _getLiquidateRatios();
    // rebalance only debt ratio >= `rebalanceDebtRatio` and ratio < `liquidateDebtRatio`
    if (tickRawDebt * PRECISION * PRECISION < rebalanceDebtRatio * tickRawColl * price) {
      revert ErrorRebalanceDebtRatioNotReached();
    }
    if (tickRawDebt * PRECISION * PRECISION >= liquidateDebtRatio * tickRawColl * price) {
      revert ErrorRebalanceOnLiquidatableTick();
    }

    // compute debts to rebalance to make debt ratio to `rebalanceDebtRatio`
    result.rawDebts = _getRawDebtToRebalance(tickRawColl, tickRawDebt, price, rebalanceDebtRatio, rebalanceBonusRatio);
    if (maxRawDebts < result.rawDebts) result.rawDebts = maxRawDebts;

    uint256 debtShareToRebalance = _convertToDebtShares(result.rawDebts, cachedDebtIndex, Math.Rounding.Down);
    result.rawColls = (result.rawDebts * PRECISION) / price;
    result.bonusRawColls = (result.rawColls * rebalanceBonusRatio) / FEE_PRECISION;
    if (result.bonusRawColls > tickRawColl - result.rawColls) {
      result.bonusRawColls = tickRawColl - result.rawColls;
    }
    uint256 collShareToRebalance = _convertToCollShares(
      result.rawColls + result.bonusRawColls,
      cachedCollIndex,
      Math.Rounding.Down
    );

    _liquidateTick(tick, collShareToRebalance, debtShareToRebalance, price);
    unchecked {
      (uint256 totalDebts, uint256 totalColls) = _getDebtAndCollateralShares();
      _updateDebtAndCollateralShares(totalDebts - debtShareToRebalance, totalColls - collShareToRebalance);
    }
  }

  struct RebalanceVars {
    uint256 tickCollShares;
    uint256 tickDebtShares;
    uint256 tickRawColls;
    uint256 tickRawDebts;
    uint256 maxRawDebts;
    uint256 rebalanceDebtRatio;
    uint256 rebalanceBonusRatio;
    uint256 price;
    uint256 collIndex;
    uint256 debtIndex;
    uint256 totalCollShares;
    uint256 totalDebtShares;
  }

  /// @inheritdoc IPool
  function rebalance(uint256 maxRawDebts) external onlyPoolManager returns (RebalanceResult memory result) {
    RebalanceVars memory vars;
    vars.maxRawDebts = maxRawDebts;
    (vars.rebalanceDebtRatio, vars.rebalanceBonusRatio) = _getRebalanceRatios();
    (, vars.price, ) = IPriceOracle(priceOracle).getPrice();
    (vars.collIndex, vars.debtIndex) = _updateCollAndDebtIndex();
    (vars.totalDebtShares, vars.totalCollShares) = _getDebtAndCollateralShares();
    (uint256 liquidateDebtRatio, ) = _getLiquidateRatios();

    int16 tick = _getTopTick();
    bool hasDebt = true;
    while (vars.maxRawDebts > 0) {
      if (!hasDebt) {
        (tick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(tick - 1);
      } else {
        (vars.tickCollShares, vars.tickDebtShares, vars.tickRawColls, vars.tickRawDebts) = _getTickRawCollAndDebts(
          tick,
          vars.collIndex,
          vars.debtIndex
        );
        // skip bad debt and liquidatable positions: coll * price * liquidateDebtRatio <= debts
        if (vars.tickRawColls * vars.price * liquidateDebtRatio <= vars.tickRawDebts * PRECISION * PRECISION) {
          hasDebt = false;
          tick = tick;
          continue;
        }
        // skip dust
        if (vars.tickRawDebts < uint256(MIN_DEBT)) {
          hasDebt = false;
          tick = tick;
          continue;
        }
        // no more rebalanceable tick: coll * price * rebalanceDebtRatio > debts
        if (vars.tickRawColls * vars.price * vars.rebalanceDebtRatio > vars.tickRawDebts * PRECISION * PRECISION) {
          break;
        }
        // rebalance this tick
        (uint256 rawDebts, uint256 rawColls, uint256 bonusRawColls) = _rebalanceTick(tick, vars);
        result.rawDebts += rawDebts;
        result.rawColls += rawColls;
        result.bonusRawColls += bonusRawColls;

        // goto next tick
        (tick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(tick - 1);
      }
      if (tick == type(int16).min) break;
    }

    _updateDebtAndCollateralShares(vars.totalDebtShares, vars.totalCollShares);
  }

  struct LiquidateVars {
    uint256 tickCollShares;
    uint256 tickDebtShares;
    uint256 tickRawColls;
    uint256 tickRawDebts;
    uint256 maxRawDebts;
    uint256 reservedRawColls;
    uint256 liquidateDebtRatio;
    uint256 liquidateBonusRatio;
    uint256 price;
    uint256 collIndex;
    uint256 debtIndex;
    uint256 totalCollShares;
    uint256 totalDebtShares;
  }

  /// @inheritdoc IPool
  function liquidate(
    uint256 maxRawDebts,
    uint256 reservedRawColls
  ) external onlyPoolManager returns (LiquidateResult memory result) {
    LiquidateVars memory vars;
    vars.maxRawDebts = maxRawDebts;
    vars.reservedRawColls = reservedRawColls;
    (vars.liquidateDebtRatio, vars.liquidateBonusRatio) = _getLiquidateRatios();
    (, vars.price, ) = IPriceOracle(priceOracle).getPrice();
    (vars.collIndex, vars.debtIndex) = _updateCollAndDebtIndex();
    (vars.totalDebtShares, vars.totalCollShares) = _getDebtAndCollateralShares();

    int16 tick = _getTopTick();
    bool hasDebt = true;
    while (vars.maxRawDebts > 0) {
      if (!hasDebt) {
        (tick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(tick - 1);
      } else {
        (vars.tickCollShares, vars.tickDebtShares, vars.tickRawColls, vars.tickRawDebts) = _getTickRawCollAndDebts(
          tick,
          vars.collIndex,
          vars.debtIndex
        );
        // no more liquidatable tick: coll * price * liquidateDebtRatio > debts
        if (vars.tickRawColls * vars.price * vars.liquidateDebtRatio > vars.tickRawDebts * PRECISION * PRECISION) {
          // skip dust, since the results might be wrong
          if (vars.tickRawDebts < uint256(MIN_DEBT)) {
            hasDebt = false;
            tick = tick;
            continue;
          }
          break;
        }
        // rebalance this tick
        (uint256 rawDebts, uint256 rawColls, uint256 bonusRawColls, uint256 bonusFromReserve) = _liquidateTick(
          tick,
          vars
        );
        result.rawDebts += rawDebts;
        result.rawColls += rawColls;
        result.bonusRawColls += bonusRawColls;
        result.bonusFromReserve += bonusFromReserve;

        // goto next tick
        (tick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(tick - 1);
      }
      if (tick == type(int16).min) break;
    }

    _updateDebtAndCollateralShares(vars.totalDebtShares, vars.totalCollShares);
    _updateDebtIndex(vars.debtIndex);
  }

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Update the borrow and redeem status.
  /// @param borrowStatus The new borrow status.
  /// @param redeemStatus The new redeem status.
  function updateBorrowAndRedeemStatus(bool borrowStatus, bool redeemStatus) external onlyRole(EMERGENCY_ROLE) {
    _updateBorrowStatus(borrowStatus);
    _updateRedeemStatus(redeemStatus);
  }

  /// @notice Update debt ratio range.
  /// @param minRatio The minimum allowed debt ratio to update, multiplied by 1e18.
  /// @param maxRatio The maximum allowed debt ratio to update, multiplied by 1e18.
  function updateDebtRatioRange(uint256 minRatio, uint256 maxRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateDebtRatioRange(minRatio, maxRatio);
  }

  /// @notice Update maximum redeem ratio per tick.
  /// @param ratio The ratio to update, multiplied by 1e9.
  function updateMaxRedeemRatioPerTick(uint256 ratio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateMaxRedeemRatioPerTick(ratio);
  }

  /// @notice Update ratio for rebalance.
  /// @param debtRatio The minimum debt ratio to start rebalance, multiplied by 1e18.
  /// @param bonusRatio The bonus ratio during rebalance, multiplied by 1e9.
  function updateRebalanceRatios(uint256 debtRatio, uint256 bonusRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateRebalanceRatios(debtRatio, bonusRatio);
  }

  /// @notice Update ratio for liquidate.
  /// @param debtRatio The minimum debt ratio to start liquidate, multiplied by 1e18.
  /// @param bonusRatio The bonus ratio during liquidate, multiplied by 1e9.
  function updateLiquidateRatios(uint256 debtRatio, uint256 bonusRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateLiquidateRatios(debtRatio, bonusRatio);
  }

  /// @notice Update the address of price oracle.
  /// @param newOracle The address of new price oracle.
  function updatePriceOracle(address newOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updatePriceOracle(newOracle);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to compute the amount of debt to rebalance to reach certain debt ratio.
  /// @param coll The amount of collateral tokens.
  /// @param debt The amount of debt tokens.
  /// @param price The price of the collateral token.
  /// @param targetDebtRatio The target debt ratio, multiplied by 1e18.
  /// @param incentiveRatio The bonus ratio, multiplied by 1e9.
  /// @return rawDebts The amount of debt tokens to rebalance.
  function _getRawDebtToRebalance(
    uint256 coll,
    uint256 debt,
    uint256 price,
    uint256 targetDebtRatio,
    uint256 incentiveRatio
  ) internal pure returns (uint256 rawDebts) {
    // we have
    //   1. (debt - x) / (price * (coll - y * (1 + incentive))) <= target_ratio
    //   2. debt / (price * coll) >= target_ratio
    // then
    // => debt - x <= target * price * (coll - y * (1 + incentive)) and y = x / price
    // => debt - target_ratio * price * coll <= (1 - (1 + incentive) * target) * x
    // => x >= (debt - target_ratio * price * coll) / (1 - (1 + incentive) * target)
    rawDebts =
      (debt * PRECISION * PRECISION - targetDebtRatio * price * coll) /
      (PRECISION * PRECISION - (PRECISION * targetDebtRatio * (FEE_PRECISION + incentiveRatio)) / FEE_PRECISION);
  }

  function _getTickRawCollAndDebts(
    int16 tick,
    uint256 collIndex,
    uint256 debtIndex
  ) internal view returns (uint256 colls, uint256 debts, uint256 rawColls, uint256 rawDebts) {
    uint256 node = tickData[tick];
    bytes32 value = tickTreeData[node].value;
    colls = value.decodeUint(COLL_SHARE_OFFSET, 128);
    debts = value.decodeUint(DEBT_SHARE_OFFSET, 128);
    rawColls = _convertToRawColl(colls, collIndex, Math.Rounding.Down);
    rawDebts = _convertToRawDebt(debts, debtIndex, Math.Rounding.Down);
  }

  function _rebalanceTick(
    int16 tick,
    RebalanceVars memory vars
  ) internal returns (uint256 rawDebts, uint256 rawColls, uint256 bonusRawColls) {
    // compute debts to rebalance to make debt ratio to `rebalanceDebtRatio`
    rawDebts = _getRawDebtToRebalance(
      vars.tickRawColls,
      vars.tickRawDebts,
      vars.price,
      vars.rebalanceDebtRatio,
      vars.rebalanceBonusRatio
    );
    if (vars.maxRawDebts < rawDebts) rawDebts = vars.maxRawDebts;

    uint256 debtShares = _convertToDebtShares(rawDebts, vars.debtIndex, Math.Rounding.Down);
    rawColls = (rawDebts * PRECISION) / vars.price;
    bonusRawColls = (rawColls * vars.rebalanceBonusRatio) / FEE_PRECISION;
    if (bonusRawColls > vars.tickRawColls - rawColls) {
      bonusRawColls = vars.tickRawColls - rawColls;
    }
    uint256 collShares = _convertToCollShares(rawColls + bonusRawColls, vars.collIndex, Math.Rounding.Down);

    _liquidateTick(tick, collShares, debtShares, vars.price);
    vars.totalCollShares -= collShares;
    vars.totalDebtShares -= debtShares;
    vars.maxRawDebts -= rawDebts;
  }

  function _liquidateTick(
    int16 tick,
    LiquidateVars memory vars
  ) internal returns (uint256 rawDebts, uint256 rawColls, uint256 bonusRawColls, uint256 bonusFromReserve) {
    uint256 virtualTickRawColls = vars.tickRawColls + vars.reservedRawColls;
    rawDebts = vars.tickRawDebts;
    if (rawDebts > vars.maxRawDebts) rawDebts = vars.maxRawDebts;
    rawColls = (rawDebts * PRECISION) / vars.price;
    uint256 debtShares;
    uint256 collShares;
    if (rawDebts == vars.tickRawDebts) {
      // full liquidation
      debtShares = vars.tickDebtShares;
    } else {
      // partial liquidation
      debtShares = _convertToDebtShares(rawDebts, vars.debtIndex, Math.Rounding.Down);
    }
    if (virtualTickRawColls <= rawColls) {
      // even reserve funds cannot cover bad debts, no bonus and will trigger bad debt redistribution
      rawColls = virtualTickRawColls;
      bonusFromReserve = vars.reservedRawColls;
      rawDebts = (virtualTickRawColls * vars.price) / PRECISION;
      debtShares = _convertToDebtShares(rawDebts, vars.debtIndex, Math.Rounding.Down);
      collShares = vars.tickCollShares;
    } else {
      // Bonus is from colls in tick, if it is not enough will use reserve funds
      bonusRawColls = (rawColls * vars.liquidateBonusRatio) / FEE_PRECISION;
      uint256 rawCollWithBonus = bonusRawColls + rawColls;
      if (rawCollWithBonus > virtualTickRawColls) {
        rawCollWithBonus = virtualTickRawColls;
        bonusRawColls = rawCollWithBonus - rawColls;
      }
      if (rawCollWithBonus >= vars.tickRawColls) {
        bonusFromReserve = rawCollWithBonus - vars.tickRawColls;
        collShares = vars.tickCollShares;
      } else {
        collShares = _convertToCollShares(rawCollWithBonus, vars.collIndex, Math.Rounding.Down);
      }
    }

    vars.reservedRawColls -= bonusFromReserve;
    if (collShares == vars.tickCollShares && debtShares < vars.tickDebtShares) {
      // trigger bad debt redistribution
      uint256 rawBadDebt = _convertToRawDebt(vars.tickDebtShares - debtShares, vars.debtIndex, Math.Rounding.Down);
      debtShares = vars.tickDebtShares;
      vars.totalCollShares -= collShares;
      vars.totalDebtShares -= debtShares;
      vars.debtIndex += (rawBadDebt * E96) / vars.totalDebtShares;
    } else {
      vars.totalCollShares -= collShares;
      vars.totalDebtShares -= debtShares;
    }
    vars.maxRawDebts -= rawDebts;
    _liquidateTick(tick, collShares, debtShares, vars.price);
  }

  /// @dev Internal function to update collateral and debt index.
  /// @return newCollIndex The updated collateral index.
  /// @return newDebtIndex The updated debt index.
  function _updateCollAndDebtIndex() internal virtual returns (uint256 newCollIndex, uint256 newDebtIndex);

  /// @dev Internal function to compute the protocol fees.
  /// @param rawColl The amount of collateral tokens involved.
  /// @return fees The expected protocol fees.
  function _deductProtocolFees(int256 rawColl) internal view virtual returns (uint256 fees);

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   */
  uint256[50] private __gap;
}
