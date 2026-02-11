// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity ^0.8.26;

// Local
import {BasePositionManager} from "./base/BasePositionManager.sol";
import {IMarginPositionManager} from "./interfaces/IMarginPositionManager.sol";
import {IProtocolFees} from "./interfaces/IProtocolFees.sol";
import {IVault} from "./interfaces/IVault.sol";
import {CurrencyPoolLibrary} from "./libraries/CurrencyPoolLibrary.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";
import {FeeLibrary} from "./libraries/FeeLibrary.sol";
import {MarginPosition} from "./libraries/MarginPosition.sol";
import {Math} from "./libraries/Math.sol";
import {PerLibrary} from "./libraries/PerLibrary.sol";
import {PositionLibrary} from "./libraries/PositionLibrary.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {StateLibrary} from "./libraries/StateLibrary.sol";
import {TimeLibrary} from "./libraries/TimeLibrary.sol";
import {SwapMath} from "./libraries/SwapMath.sol";
import {MarginActions} from "./types/MarginActions.sol";
import {BalanceDelta, toBalanceDelta} from "./types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {MarginLevels, MarginLevelsLibrary} from "./types/MarginLevels.sol";
import {PoolId} from "./types/PoolId.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {Reserves} from "./types/Reserves.sol";
import {PoolState} from "./types/PoolState.sol";
import {MarginBalanceDelta} from "./types/MarginBalanceDelta.sol";
// Solmate

contract LikwidMarginPosition is IMarginPositionManager, BasePositionManager {
    using SafeCast for *;
    using CurrencyLibrary for Currency;
    using CurrencyPoolLibrary for Currency;
    using PerLibrary for uint256;
    using FeeLibrary for uint24;
    using CustomRevert for bytes4;
    using PositionLibrary for address;
    using MarginLevelsLibrary for MarginLevels;
    using TimeLibrary for uint32;
    using MarginPosition for MarginPosition.State;

    uint8 constant MAX_LEVERAGE = 5; // 5x

    mapping(uint256 tokenId => MarginPosition.State positionInfo) private positionInfos;
    MarginLevels public marginLevels;
    uint24 public defaultMarginFee = 3000; // 0.3%

    constructor(address initialOwner, IVault _vault)
        BasePositionManager("LIKWIDMarginPositionManager", "LMPM", initialOwner, _vault)
    {
        MarginLevels _marginLevels;
        _marginLevels = _marginLevels.setMinMarginLevel(1170000);
        _marginLevels = _marginLevels.setMinBorrowLevel(1400000);
        _marginLevels = _marginLevels.setLiquidateLevel(1100000);
        _marginLevels = _marginLevels.setLiquidationRatio(950000);
        _marginLevels = _marginLevels.setCallerProfit(10000);
        _marginLevels = _marginLevels.setProtocolProfit(5000);
        marginLevels = _marginLevels;
    }

    /// @notice Callback function for the vault to execute margin-related actions.
    /// @param data The encoded action and parameters.
    /// @return The result of the action.
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        (MarginActions action, bytes memory params) = abi.decode(data, (MarginActions, bytes));

        if (action == MarginActions.LIQUIDATE_BURN) {
            return handleLiquidateBurn(params);
        } else {
            return handleMargin(params);
        }
    }

    function _getPoolState(PoolId poolId) internal view returns (PoolState memory state) {
        state = StateLibrary.getCurrentState(vault, poolId);
    }

    /// @dev Gets the last cumulative borrow and deposit values for a given position.
    /// @param poolState The current state of the pool.
    /// @param marginForOne Whether the margin is on token1.
    /// @return borrowCumulativeLast The last cumulative borrow value.
    /// @return depositCumulativeLast The last cumulative deposit value.
    function _getPoolCumulativeValues(PoolState memory poolState, bool marginForOne)
        private
        pure
        returns (uint256 borrowCumulativeLast, uint256 depositCumulativeLast)
    {
        if (marginForOne) {
            borrowCumulativeLast = poolState.borrow0CumulativeLast;
            depositCumulativeLast = poolState.deposit1CumulativeLast;
        } else {
            borrowCumulativeLast = poolState.borrow1CumulativeLast;
            depositCumulativeLast = poolState.deposit0CumulativeLast;
        }
    }

    function getPositionState(uint256 tokenId) external view returns (MarginPosition.State memory position) {
        PoolId poolId = poolIds[tokenId];
        position = positionInfos[tokenId];
        PoolState memory state = _getPoolState(poolId);
        (uint256 borrowCumulativeLast, uint256 depositCumulativeLast) =
            _getPoolCumulativeValues(state, position.marginForOne);

        position.marginAmount =
            Math.mulDiv(position.marginAmount, depositCumulativeLast, position.depositCumulativeLast).toUint128();
        position.marginTotal =
            Math.mulDiv(position.marginTotal, depositCumulativeLast, position.depositCumulativeLast).toUint128();
        position.debtAmount =
            Math.mulDiv(position.debtAmount, borrowCumulativeLast, position.borrowCumulativeLast).toUint128();

        position.depositCumulativeLast = depositCumulativeLast;
        position.borrowCumulativeLast = borrowCumulativeLast;
    }

    function checkLiquidate(uint256 tokenId)
        external
        view
        returns (bool liquidated, uint256 marginAmount, uint256 marginTotal, uint256 debtAmount)
    {
        PoolId poolId = poolIds[tokenId];
        MarginPosition.State memory position = positionInfos[tokenId];
        PoolState memory state = _getPoolState(poolId);
        (liquidated, marginAmount, marginTotal, debtAmount) = _checkLiquidate(state, position);
    }

    function _checkLiquidate(PoolState memory state, MarginPosition.State memory position)
        internal
        view
        returns (bool liquidated, uint256 marginAmount, uint256 marginTotal, uint256 debtAmount)
    {
        (uint256 borrowCumulativeLast, uint256 depositCumulativeLast) =
            _getPoolCumulativeValues(state, position.marginForOne);
        MarginLevels _marginLevels = marginLevels;
        // use truncatedReserves
        uint256 level = position.marginLevel(state.truncatedReserves, borrowCumulativeLast, depositCumulativeLast);
        liquidated = level < _marginLevels.liquidateLevel();
        if (liquidated) {
            marginAmount = Math.mulDiv(position.marginAmount, depositCumulativeLast, position.depositCumulativeLast);
            marginTotal = Math.mulDiv(position.marginTotal, depositCumulativeLast, position.depositCumulativeLast);
            debtAmount = Math.mulDiv(position.debtAmount, borrowCumulativeLast, position.borrowCumulativeLast);
        }
    }

    function _checkMinLevel(
        Reserves pairReserves,
        uint256 borrowCumulativeLast,
        uint256 depositCumulativeLast,
        MarginPosition.State memory position,
        uint256 minLevel
    ) internal pure {
        uint256 level = position.marginLevel(pairReserves, borrowCumulativeLast, depositCumulativeLast);
        if (level < minLevel) {
            InvalidLevel.selector.revertWith();
        }
    }

    function _processLost(PoolState memory state, MarginPosition.State memory position, uint256 lostAmount)
        internal
        pure
        returns (uint256 lendLostAmount, uint256 debtDepositCumulativeLast)
    {
        debtDepositCumulativeLast = position.marginForOne ? state.deposit0CumulativeLast : state.deposit1CumulativeLast;
        if (lostAmount > 0) {
            (uint128 pairReserve0, uint128 pairReserve1) = state.pairReserves.reserves();
            (uint128 lendReserve0, uint128 lendReserve1) = state.lendReserves.reserves();
            uint256 pairReserve = position.marginForOne ? pairReserve0 : pairReserve1;
            uint256 lendReserve = position.marginForOne ? lendReserve0 : lendReserve1;
            lendLostAmount = Math.mulDiv(lostAmount, lendReserve, pairReserve + lendReserve);
            if (lendReserve > 0) {
                debtDepositCumulativeLast =
                    Math.mulDiv(debtDepositCumulativeLast, lendReserve - lendLostAmount, lendReserve);
            }
        }
    }

    /// @inheritdoc IMarginPositionManager
    function addMargin(PoolKey memory key, IMarginPositionManager.CreateParams calldata params)
        external
        payable
        ensure(params.deadline)
        returns (uint256 tokenId, uint256 borrowAmount, uint256 swapFeeAmount)
    {
        tokenId = _mintPosition(key, params.recipient);
        positionInfos[tokenId].marginForOne = params.marginForOne;
        (borrowAmount, swapFeeAmount) = _margin(
            msg.sender,
            params.recipient,
            IMarginPositionManager.MarginParams({
                tokenId: tokenId,
                leverage: params.leverage,
                marginAmount: params.marginAmount,
                borrowAmount: params.borrowAmount,
                borrowAmountMax: params.borrowAmountMax,
                deadline: params.deadline
            })
        );
    }

    function _margin(address sender, address tokenOwner, IMarginPositionManager.MarginParams memory params)
        internal
        returns (uint256 borrowAmount, uint256 swapFeeAmount)
    {
        _requireAuth(tokenOwner, params.tokenId);
        PoolId poolId = poolIds[params.tokenId];
        PoolState memory poolState = _getPoolState(poolId);
        if (poolState.lpFee < 3000) revert LowFeePoolMarginBanned();
        PoolKey memory key = poolKeys[poolId];
        MarginPosition.State storage position = positionInfos[params.tokenId];

        (uint256 borrowCumulativeLast, uint256 depositCumulativeLast) =
            _getPoolCumulativeValues(poolState, position.marginForOne);

        MarginBalanceDelta memory delta;
        delta.action = MarginActions.MARGIN;
        delta.marginForOne = position.marginForOne;
        uint256 minLevel;
        if (params.leverage > 0) {
            minLevel = marginLevels.minMarginLevel();
            (borrowAmount, swapFeeAmount) = _executeAddLeverage(params, poolState, position, delta);
        } else {
            minLevel = marginLevels.minBorrowLevel();
            borrowAmount = _executeAddCollateralAndBorrow(params, poolState, position, delta);
        }
        delta.swapFeeAmount = swapFeeAmount;
        _checkMinLevel(poolState.pairReserves, borrowCumulativeLast, depositCumulativeLast, position, minLevel);
        bytes memory callbackData = abi.encode(sender, key, delta);
        bytes memory data = abi.encode(delta.action, callbackData);

        vault.unlock(data);
        emit Margin(
            key.toId(),
            sender,
            params.tokenId,
            position.marginAmount,
            position.marginTotal,
            position.debtAmount,
            position.marginForOne
        );
    }

    /// @inheritdoc IMarginPositionManager
    function margin(IMarginPositionManager.MarginParams memory params)
        external
        payable
        ensure(params.deadline)
        returns (uint256 borrowAmount, uint256 swapFeeAmount)
    {
        (borrowAmount, swapFeeAmount) = _margin(msg.sender, msg.sender, params);
    }

    function _executeAddLeverage(
        IMarginPositionManager.MarginParams memory params,
        PoolState memory poolState,
        MarginPosition.State storage position,
        MarginBalanceDelta memory delta
    ) internal returns (uint256 borrowAmount, uint256 swapFeeAmount) {
        uint256 borrowMirrorReserves = poolState.mirrorReserves.reserve01(!position.marginForOne);
        uint256 borrowRealReserves = poolState.realReserves.reserve01(!position.marginForOne);
        if (Math.mulDiv(borrowMirrorReserves, 100, borrowRealReserves + borrowMirrorReserves) > 90) {
            MirrorTooMuch.selector.revertWith();
        }

        uint256 marginReserves = poolState.realReserves.reserve01(position.marginForOne);
        uint256 marginTotal = params.marginAmount * params.leverage;
        if (marginTotal > marginReserves) ReservesNotEnough.selector.revertWith();

        delta.marginTotal = marginTotal.toUint128();
        delta.marginFee = poolState.marginFee == 0 ? defaultMarginFee : poolState.marginFee;
        (uint256 marginWithoutFee,) = delta.marginFee.deduct(marginTotal);
        (borrowAmount,, swapFeeAmount) = SwapMath.getAmountIn(
            poolState.pairReserves, poolState.truncatedReserves, poolState.lpFee, position.marginForOne, marginTotal
        );
        params.borrowAmount = borrowAmount.toUint128();

        uint256 borrowCumulativeLast;
        uint256 depositCumulativeLast;
        if (position.marginForOne) {
            borrowCumulativeLast = poolState.borrow0CumulativeLast;
            depositCumulativeLast = poolState.deposit1CumulativeLast;
        } else {
            borrowCumulativeLast = poolState.borrow1CumulativeLast;
            depositCumulativeLast = poolState.deposit0CumulativeLast;
        }

        position.update(
            borrowCumulativeLast,
            depositCumulativeLast,
            params.marginAmount.toInt128(),
            marginWithoutFee,
            params.borrowAmount,
            0
        );

        int128 amount0Delta;
        int128 amount1Delta;
        int128 amount = -params.marginAmount.toInt128();
        int128 lendAmount = amount - marginWithoutFee.toInt128();

        if (position.marginForOne) {
            amount1Delta = amount;
            delta.pairDelta = toBalanceDelta(-borrowAmount.toInt128(), marginWithoutFee.toInt128());
            delta.lendDelta = toBalanceDelta(0, lendAmount);
            delta.mirrorDelta = toBalanceDelta(-borrowAmount.toInt128(), 0);
        } else {
            amount0Delta = amount;
            delta.pairDelta = toBalanceDelta(marginWithoutFee.toInt128(), -borrowAmount.toInt128());
            delta.lendDelta = toBalanceDelta(lendAmount, 0);
            delta.mirrorDelta = toBalanceDelta(0, -borrowAmount.toInt128());
        }
        delta.marginDelta = toBalanceDelta(amount0Delta, amount1Delta);
    }

    function _executeAddCollateralAndBorrow(
        IMarginPositionManager.MarginParams memory params,
        PoolState memory poolState,
        MarginPosition.State storage position,
        MarginBalanceDelta memory delta
    ) internal returns (uint256 borrowAmount) {
        uint256 borrowRealReserves = poolState.realReserves.reserve01(!position.marginForOne);
        (uint256 borrowMaxAmount,) =
            SwapMath.getAmountOut(poolState.pairReserves, poolState.lpFee, !position.marginForOne, params.marginAmount);
        borrowMaxAmount = Math.min(borrowMaxAmount, borrowRealReserves * 20 / 100);
        if (params.borrowAmount > borrowMaxAmount) BorrowTooMuch.selector.revertWith();
        if (params.borrowAmount == 0) params.borrowAmount = borrowMaxAmount.toUint128();
        borrowAmount = params.borrowAmount;
        uint256 borrowCumulativeLast;
        uint256 depositCumulativeLast;
        if (position.marginForOne) {
            borrowCumulativeLast = poolState.borrow0CumulativeLast;
            depositCumulativeLast = poolState.deposit1CumulativeLast;
        } else {
            borrowCumulativeLast = poolState.borrow1CumulativeLast;
            depositCumulativeLast = poolState.deposit0CumulativeLast;
        }

        position.update(
            borrowCumulativeLast, depositCumulativeLast, params.marginAmount.toInt128(), 0, params.borrowAmount, 0
        );

        int128 amount0Delta;
        int128 amount1Delta;
        int128 amount = -params.marginAmount.toInt128();

        if (position.marginForOne) {
            amount1Delta = amount;
            amount0Delta = borrowAmount.toInt128();
            delta.lendDelta = toBalanceDelta(0, amount);
            delta.mirrorDelta = toBalanceDelta(-borrowAmount.toInt128(), 0);
        } else {
            amount0Delta = amount;
            amount1Delta = borrowAmount.toInt128();
            delta.lendDelta = toBalanceDelta(amount, 0);
            delta.mirrorDelta = toBalanceDelta(0, -borrowAmount.toInt128());
        }
        delta.marginDelta = toBalanceDelta(amount0Delta, amount1Delta);
    }

    /// @inheritdoc IMarginPositionManager
    function repay(uint256 tokenId, uint256 repayAmount, uint256 deadline) external payable ensure(deadline) {
        _requireAuth(msg.sender, tokenId);
        PoolId poolId = poolIds[tokenId];
        PoolKey memory key = poolKeys[poolId];
        PoolState memory poolState = _getPoolState(poolId);
        MarginPosition.State storage position = positionInfos[tokenId];
        MarginBalanceDelta memory delta;

        (uint256 borrowCumulativeLast, uint256 depositCumulativeLast) =
            _getPoolCumulativeValues(poolState, position.marginForOne);

        (uint256 releaseAmount, uint256 realRepayAmount) =
            position.update(borrowCumulativeLast, depositCumulativeLast, 0, 0, 0, repayAmount);

        MarginLevels _marginLevels = marginLevels;
        _checkMinLevel(
            poolState.pairReserves,
            borrowCumulativeLast,
            depositCumulativeLast,
            position,
            _marginLevels.liquidateLevel()
        );

        int128 amount0Delta;
        int128 amount1Delta;
        if (position.marginForOne) {
            amount0Delta = -realRepayAmount.toInt128();
            amount1Delta = releaseAmount.toInt128();
            delta.lendDelta = toBalanceDelta(0, amount1Delta);
            delta.mirrorDelta = toBalanceDelta(realRepayAmount.toInt128(), 0);
        } else {
            amount0Delta = releaseAmount.toInt128();
            amount1Delta = -realRepayAmount.toInt128();
            delta.lendDelta = toBalanceDelta(amount0Delta, 0);
            delta.mirrorDelta = toBalanceDelta(0, realRepayAmount.toInt128());
        }
        delta.action = MarginActions.REPAY;
        delta.marginForOne = position.marginForOne;
        delta.marginDelta = toBalanceDelta(amount0Delta, amount1Delta);

        bytes memory callbackData = abi.encode(msg.sender, key, delta);
        bytes memory data = abi.encode(delta.action, callbackData);

        vault.unlock(data);

        emit Repay(
            key.toId(),
            msg.sender,
            tokenId,
            position.marginAmount,
            position.marginTotal,
            position.debtAmount,
            releaseAmount,
            realRepayAmount
        );
    }

    /// @inheritdoc IMarginPositionManager
    function close(uint256 tokenId, uint24 closeMillionth, uint256 closeAmountMin, uint256 deadline)
        external
        ensure(deadline)
    {
        _requireAuth(msg.sender, tokenId);
        PoolId poolId = poolIds[tokenId];
        PoolKey memory key = poolKeys[poolId];
        PoolState memory poolState = _getPoolState(poolId);
        MarginPosition.State storage position = positionInfos[tokenId];
        MarginBalanceDelta memory delta;

        (uint256 borrowCumulativeLast, uint256 depositCumulativeLast) =
            _getPoolCumulativeValues(poolState, position.marginForOne);

        (uint256 releaseAmount, uint256 repayAmount, uint256 closeAmount, uint256 lostAmount, uint256 swapFeeAmount) =
        position.close(
            poolState.pairReserves, poolState.lpFee, borrowCumulativeLast, depositCumulativeLast, 0, closeMillionth
        );
        if (lostAmount > 0 || (closeAmountMin > 0 && closeAmount < closeAmountMin)) {
            InsufficientCloseReceived.selector.revertWith();
        }
        MarginLevels _marginLevels = marginLevels;
        _checkMinLevel(
            poolState.pairReserves,
            borrowCumulativeLast,
            depositCumulativeLast,
            position,
            _marginLevels.liquidateLevel()
        );

        int128 amount0Delta;
        int128 amount1Delta;
        if (position.marginForOne) {
            amount1Delta = closeAmount.toInt128();
            delta.lendDelta = toBalanceDelta(0, releaseAmount.toInt128());
            delta.mirrorDelta = toBalanceDelta(repayAmount.toInt128(), 0);
            delta.pairDelta = toBalanceDelta(repayAmount.toInt128(), -(releaseAmount - closeAmount).toInt128());
        } else {
            amount0Delta = closeAmount.toInt128();
            delta.lendDelta = toBalanceDelta(releaseAmount.toInt128(), 0);
            delta.mirrorDelta = toBalanceDelta(0, repayAmount.toInt128());
            delta.pairDelta = toBalanceDelta(-(releaseAmount - closeAmount).toInt128(), repayAmount.toInt128());
        }
        delta.action = MarginActions.CLOSE;
        delta.swapFeeAmount = swapFeeAmount;
        delta.marginForOne = position.marginForOne;
        delta.marginDelta = toBalanceDelta(amount0Delta, amount1Delta);

        bytes memory callbackData = abi.encode(msg.sender, key, delta);
        bytes memory data = abi.encode(delta.action, callbackData);

        vault.unlock(data);
        emit Close(
            key.toId(),
            msg.sender,
            tokenId,
            position.marginAmount,
            position.marginTotal,
            position.debtAmount,
            releaseAmount,
            repayAmount,
            closeAmount
        );
    }

    /// @inheritdoc IMarginPositionManager
    function liquidateBurn(uint256 tokenId) external returns (uint256 profit) {
        PoolId poolId = poolIds[tokenId];
        PoolState memory poolState = _getPoolState(poolId);
        MarginPosition.State storage position = positionInfos[tokenId];
        (bool liquidated, uint256 marginAmount, uint256 marginTotal, uint256 debtAmount) =
            _checkLiquidate(poolState, position);
        if (!liquidated) {
            PositionNotLiquidated.selector.revertWith();
        }
        PoolKey memory key = poolKeys[poolId];
        MarginBalanceDelta memory delta;
        MarginLevels _marginLevels = marginLevels;
        uint256 assetsAmount = marginAmount + marginTotal;
        profit = assetsAmount.mulDivMillion(_marginLevels.callerProfit());
        uint256 protocolProfitAmount = assetsAmount.mulDivMillion(_marginLevels.protocolProfit());

        (uint256 borrowCumulativeLast, uint256 depositCumulativeLast) =
            _getPoolCumulativeValues(poolState, position.marginForOne);
        uint256 rewardAmount = profit + protocolProfitAmount;
        (uint256 releaseAmount, uint256 repayAmount,, uint256 lostAmount, uint256 swapFeeAmount) = position.close(
            poolState.pairReserves,
            poolState.lpFee,
            borrowCumulativeLast,
            depositCumulativeLast,
            rewardAmount,
            uint24(PerLibrary.ONE_MILLION)
        );
        (uint256 lendLostAmount, uint256 debtDepositCumulativeLast) = _processLost(poolState, position, lostAmount);
        delta.swapFeeAmount = swapFeeAmount;
        delta.debtDepositCumulativeLast = debtDepositCumulativeLast;

        int128 amount0Delta;
        int128 amount1Delta;
        if (position.marginForOne) {
            amount1Delta = rewardAmount.toInt128();
            delta.lendDelta = toBalanceDelta(lendLostAmount.toInt128(), releaseAmount.toInt128());
            delta.mirrorDelta = toBalanceDelta(repayAmount.toInt128(), 0);
            delta.pairDelta =
                toBalanceDelta((repayAmount - lendLostAmount).toInt128(), -(releaseAmount - rewardAmount).toInt128());
        } else {
            amount0Delta = rewardAmount.toInt128();
            delta.lendDelta = toBalanceDelta(releaseAmount.toInt128(), lendLostAmount.toInt128());
            delta.mirrorDelta = toBalanceDelta(0, repayAmount.toInt128());
            delta.pairDelta =
                toBalanceDelta(-(releaseAmount - rewardAmount).toInt128(), (repayAmount - lendLostAmount).toInt128());
        }
        delta.action = MarginActions.LIQUIDATE_BURN;
        delta.marginForOne = position.marginForOne;
        delta.marginDelta = toBalanceDelta(amount0Delta, amount1Delta);

        bytes memory callbackData = abi.encode(msg.sender, key, delta, profit, protocolProfitAmount);
        bytes memory data = abi.encode(delta.action, callbackData);

        vault.unlock(data);

        emit LiquidateBurn(
            key.toId(),
            msg.sender,
            tokenId,
            marginAmount,
            marginTotal,
            debtAmount,
            Reserves.unwrap(poolState.truncatedReserves),
            Reserves.unwrap(poolState.pairReserves),
            releaseAmount,
            repayAmount,
            profit,
            lostAmount
        );
    }

    /// @inheritdoc IMarginPositionManager
    function liquidateCall(uint256 tokenId) external payable returns (uint256 profit, uint256 repayAmount) {
        PoolId poolId = poolIds[tokenId];
        PoolState memory poolState = _getPoolState(poolId);
        MarginPosition.State storage position = positionInfos[tokenId];
        (bool liquidated, uint256 marginAmount, uint256 marginTotal, uint256 debtAmount) =
            _checkLiquidate(poolState, position);
        if (!liquidated) {
            PositionNotLiquidated.selector.revertWith();
        }
        PoolKey memory key = poolKeys[poolId];
        MarginBalanceDelta memory delta;
        (uint128 reserve0, uint128 reserve1) = poolState.pairReserves.reserves();
        (uint256 reserveBorrow, uint256 reserveMargin) =
            position.marginForOne ? (reserve0, reserve1) : (reserve1, reserve0);

        MarginLevels _marginLevels = marginLevels;
        uint24 _liquidationRatio = _marginLevels.liquidationRatio();
        uint256 assetsAmount = marginAmount + marginTotal;
        repayAmount = Math.mulDiv(reserveBorrow, assetsAmount, reserveMargin);
        uint256 needPayAmount = repayAmount.mulDivMillion(_liquidationRatio);
        profit = assetsAmount;

        (uint256 borrowCumulativeLast, uint256 depositCumulativeLast) =
            _getPoolCumulativeValues(poolState, position.marginForOne);

        uint256 releaseAmount;
        (releaseAmount, repayAmount) = position.update(borrowCumulativeLast, depositCumulativeLast, 0, 0, 0, debtAmount);
        if (profit != releaseAmount) {
            InsufficientReceived.selector.revertWith();
        }
        uint256 realRepayAmount = Math.min(repayAmount, needPayAmount);

        uint256 lostAmount;
        if (debtAmount > realRepayAmount) {
            lostAmount = debtAmount - realRepayAmount;
        }
        (uint256 lendLostAmount, uint256 debtDepositCumulativeLast) = _processLost(poolState, position, lostAmount);
        delta.debtDepositCumulativeLast = debtDepositCumulativeLast;
        int128 amount0Delta;
        int128 amount1Delta;
        if (position.marginForOne) {
            amount0Delta = -realRepayAmount.toInt128();
            amount1Delta = releaseAmount.toInt128();
            delta.lendDelta = toBalanceDelta(lendLostAmount.toInt128(), amount1Delta);
            delta.pairDelta = toBalanceDelta((lostAmount - lendLostAmount).toInt128(), 0);
            delta.mirrorDelta = toBalanceDelta(debtAmount.toInt128(), 0);
        } else {
            amount0Delta = releaseAmount.toInt128();
            amount1Delta = -realRepayAmount.toInt128();
            delta.lendDelta = toBalanceDelta(amount0Delta, lendLostAmount.toInt128());
            delta.pairDelta = toBalanceDelta(0, (lostAmount - lendLostAmount).toInt128());
            delta.mirrorDelta = toBalanceDelta(0, debtAmount.toInt128());
        }
        delta.action = MarginActions.LIQUIDATE_CALL;
        delta.marginForOne = position.marginForOne;
        delta.marginDelta = toBalanceDelta(amount0Delta, amount1Delta);

        bytes memory callbackData = abi.encode(msg.sender, key, delta);
        bytes memory data = abi.encode(delta.action, callbackData);

        vault.unlock(data);

        emit LiquidateCall(
            key.toId(),
            msg.sender,
            tokenId,
            marginAmount,
            marginTotal,
            debtAmount,
            Reserves.unwrap(poolState.truncatedReserves),
            Reserves.unwrap(poolState.pairReserves),
            releaseAmount,
            repayAmount,
            needPayAmount,
            lostAmount
        );
    }

    /// @inheritdoc IMarginPositionManager
    function modify(uint256 tokenId, int128 changeAmount) external payable {
        _requireAuth(msg.sender, tokenId);
        PoolId poolId = poolIds[tokenId];
        PoolKey memory key = poolKeys[poolId];
        PoolState memory poolState = _getPoolState(poolId);
        MarginPosition.State storage position = positionInfos[tokenId];
        MarginBalanceDelta memory delta;

        (uint256 borrowCumulativeLast, uint256 depositCumulativeLast) =
            _getPoolCumulativeValues(poolState, position.marginForOne);

        position.update(borrowCumulativeLast, depositCumulativeLast, changeAmount, 0, 0, 0);

        MarginLevels _marginLevels = marginLevels;
        _checkMinLevel(
            poolState.pairReserves,
            borrowCumulativeLast,
            depositCumulativeLast,
            position,
            _marginLevels.minBorrowLevel()
        );

        int128 amount0Delta;
        int128 amount1Delta;
        if (position.marginForOne) {
            amount1Delta = -changeAmount.toInt128();
            delta.lendDelta = toBalanceDelta(0, amount1Delta);
        } else {
            amount0Delta = -changeAmount.toInt128();
            delta.lendDelta = toBalanceDelta(amount0Delta, 0);
        }
        delta.action = MarginActions.MODIFY;
        delta.marginForOne = position.marginForOne;
        delta.marginDelta = toBalanceDelta(amount0Delta, amount1Delta);

        bytes memory callbackData = abi.encode(msg.sender, key, delta);
        bytes memory data = abi.encode(delta.action, callbackData);

        vault.unlock(data);
        emit Modify(
            key.toId(),
            msg.sender,
            tokenId,
            position.marginAmount,
            position.marginTotal,
            position.debtAmount,
            changeAmount
        );
    }

    function handleMargin(bytes memory _data) internal returns (bytes memory) {
        (address sender, PoolKey memory key, MarginBalanceDelta memory params) =
            abi.decode(_data, (address, PoolKey, MarginBalanceDelta));

        (BalanceDelta delta, uint256 feeAmount) = vault.marginBalance(key, params);

        _processDelta(sender, key, delta, 0, 0, 0, 0);

        return abi.encode(feeAmount);
    }

    function handleLiquidateBurn(bytes memory _data) internal returns (bytes memory) {
        (
            address sender,
            PoolKey memory key,
            MarginBalanceDelta memory params,
            uint256 callerProfitAmount,
            uint256 protocolProfitAmount
        ) = abi.decode(_data, (address, PoolKey, MarginBalanceDelta, uint256, uint256));

        vault.marginBalance(key, params);

        Currency marginCurrency = params.marginForOne ? key.currency1 : key.currency0;
        if (protocolProfitAmount > 0) {
            address feeTo = IProtocolFees(address(vault)).protocolFeeController();
            if (feeTo == address(0)) {
                feeTo = owner;
            }
            marginCurrency.take(vault, feeTo, protocolProfitAmount, false);
        }
        if (callerProfitAmount > 0) {
            marginCurrency.take(vault, sender, callerProfitAmount, false);
        }

        return abi.encode(callerProfitAmount + protocolProfitAmount);
    }

    // ******************** OWNER CALL ********************
    function setMarginLevel(bytes32 _marginLevel) external onlyOwner {
        MarginLevels newMarginLevels = MarginLevels.wrap(_marginLevel);
        if (!newMarginLevels.isValidMarginLevels()) InvalidLevel.selector.revertWith();
        bytes32 old = MarginLevels.unwrap(marginLevels);
        marginLevels = newMarginLevels;
        emit MarginLevelChanged(old, _marginLevel);
    }

    function setDefaultMarginFee(uint24 newMarginFee) external onlyOwner {
        uint24 old = defaultMarginFee;
        defaultMarginFee = newMarginFee;
        emit MarginFeeChanged(old, newMarginFee);
    }
}
