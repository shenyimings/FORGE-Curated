// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {BalanceDelta, toBalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {FeeTypes} from "../types/FeeTypes.sol";
import {MarginActions} from "../types/MarginActions.sol";
import {MarginState} from "../types/MarginState.sol";
import {MarginBalanceDelta} from "../types/MarginBalanceDelta.sol";
import {ReservesType, Reserves, toReserves, ReservesLibrary} from "../types/Reserves.sol";
import {Slot0} from "../types/Slot0.sol";
import {CustomRevert} from "./CustomRevert.sol";
import {FeeLibrary} from "./FeeLibrary.sol";
import {FixedPoint96} from "./FixedPoint96.sol";
import {Math} from "./Math.sol";
import {PairPosition} from "./PairPosition.sol";
import {LendPosition} from "./LendPosition.sol";
import {PerLibrary} from "./PerLibrary.sol";
import {ProtocolFeeLibrary} from "./ProtocolFeeLibrary.sol";
import {TimeLibrary} from "./TimeLibrary.sol";
import {SafeCast} from "./SafeCast.sol";
import {SwapMath} from "./SwapMath.sol";
import {InterestMath} from "./InterestMath.sol";
import {PriceMath} from "./PriceMath.sol";

/// @title A library for managing Likwid pools.
/// @notice This library contains all the functions for interacting with a Likwid pool.
library Pool {
    using CustomRevert for bytes4;
    using SafeCast for *;
    using SwapMath for *;
    using FeeLibrary for uint24;
    using PerLibrary for uint256;
    using TimeLibrary for uint32;
    using Pool for State;
    using PairPosition for PairPosition.State;
    using PairPosition for mapping(bytes32 => PairPosition.State);
    using LendPosition for LendPosition.State;
    using LendPosition for mapping(bytes32 => LendPosition.State);
    using ProtocolFeeLibrary for uint24;

    /// @notice Thrown when trying to initialize an already initialized pool
    error PoolAlreadyInitialized();

    /// @notice Thrown when trying to interact with a non-initialized pool
    error PoolNotInitialized();

    /// @notice Thrown when trying to remove more liquidity than available in the pool
    error InsufficientLiquidity();

    error InsufficientAmount();

    struct State {
        Slot0 slot0;
        /// @notice The cumulative borrow rate of the first currency in the pool.
        uint256 borrow0CumulativeLast;
        /// @notice The cumulative borrow rate of the second currency in the pool.
        uint256 borrow1CumulativeLast;
        /// @notice The cumulative deposit rate of the first currency in the pool.
        uint256 deposit0CumulativeLast;
        /// @notice The cumulative deposit rate of the second currency in the pool.
        uint256 deposit1CumulativeLast;
        Reserves realReserves;
        Reserves mirrorReserves;
        Reserves pairReserves;
        Reserves truncatedReserves;
        Reserves lendReserves;
        Reserves interestReserves;
        /// @notice The positions in the pool, mapped by a hash of the owner's address and a salt.
        mapping(bytes32 positionKey => PairPosition.State) positions;
        mapping(bytes32 positionKey => LendPosition.State) lendPositions;
    }

    struct ModifyLiquidityParams {
        // the address that owns the position
        address owner;
        uint256 amount0;
        uint256 amount1;
        // any change in liquidity
        int128 liquidityDelta;
        // used to distinguish positions of the same owner, at the same tick range
        bytes32 salt;
    }

    /// @notice Initializes the pool with a given fee
    /// @param self The pool state
    /// @param lpFee The initial fee for the pool
    function initialize(State storage self, uint24 lpFee) internal {
        if (self.borrow0CumulativeLast != 0) PoolAlreadyInitialized.selector.revertWith();

        self.slot0 = Slot0.wrap(bytes32(0)).setLastUpdated(uint32(block.timestamp)).setLpFee(lpFee);
        self.borrow0CumulativeLast = FixedPoint96.Q96;
        self.borrow1CumulativeLast = FixedPoint96.Q96;
        self.deposit0CumulativeLast = FixedPoint96.Q96;
        self.deposit1CumulativeLast = FixedPoint96.Q96;
    }

    /// @notice Sets the protocol fee for the pool
    /// @param self The pool state
    /// @param protocolFee The new protocol fee
    function setProtocolFee(State storage self, uint24 protocolFee) internal {
        self.checkPoolInitialized();
        self.slot0 = self.slot0.setProtocolFee(protocolFee);
    }

    /// @notice Sets the margin fee for the pool
    /// @param self The pool state
    /// @param marginFee The new margin fee
    function setMarginFee(State storage self, uint24 marginFee) internal {
        self.checkPoolInitialized();
        self.slot0 = self.slot0.setMarginFee(marginFee);
    }

    /// @notice Adds or removes liquidity from the pool
    /// @param self The pool state
    /// @param params The parameters for modifying liquidity
    /// @return delta The change in balances
    function modifyLiquidity(State storage self, ModifyLiquidityParams memory params)
        internal
        returns (BalanceDelta delta, int128 finalLiquidityDelta)
    {
        if (params.liquidityDelta == 0 && params.amount0 == 0 && params.amount1 == 0) {
            return (BalanceDelta.wrap(0), 0);
        }

        Slot0 _slot0 = self.slot0;
        Reserves _pairReserves = self.pairReserves;

        (uint128 _reserve0, uint128 _reserve1) = _pairReserves.reserves();
        uint128 totalSupply = _slot0.totalSupply();

        if (params.liquidityDelta < 0) {
            // --- Remove Liquidity ---
            uint256 liquidityToRemove = uint256(-int256(params.liquidityDelta));
            if (liquidityToRemove > totalSupply) InsufficientLiquidity.selector.revertWith();

            uint256 amount0Out = Math.mulDiv(liquidityToRemove, _reserve0, totalSupply);
            uint256 amount1Out = Math.mulDiv(liquidityToRemove, _reserve1, totalSupply);

            delta = toBalanceDelta(amount0Out.toInt128(), amount1Out.toInt128());
            self.slot0 = _slot0.setTotalSupply(totalSupply - liquidityToRemove.toUint128());
            finalLiquidityDelta = params.liquidityDelta;
        } else {
            // --- Add Liquidity ---
            uint256 amount0In;
            uint256 amount1In;
            uint256 liquidityAdded;

            if (totalSupply == 0) {
                amount0In = params.amount0;
                amount1In = params.amount1;
                liquidityAdded = Math.sqrt(amount0In * amount1In);
            } else {
                uint256 amount1FromAmount0 = Math.mulDiv(params.amount0, _reserve1, _reserve0);
                if (amount1FromAmount0 <= params.amount1) {
                    amount0In = params.amount0;
                    amount1In = amount1FromAmount0;
                } else {
                    amount0In = Math.mulDiv(params.amount1, _reserve0, _reserve1);
                    amount1In = params.amount1;
                }
                liquidityAdded = Math.min(
                    Math.mulDiv(amount0In, totalSupply, _reserve0), Math.mulDiv(amount1In, totalSupply, _reserve1)
                );
            }

            delta = toBalanceDelta(-amount0In.toInt128(), -amount1In.toInt128());

            self.slot0 = _slot0.setTotalSupply(totalSupply + liquidityAdded.toUint128());
            finalLiquidityDelta = liquidityAdded.toInt128();
        }
        ReservesLibrary.UpdateParam[] memory deltaParams = new ReservesLibrary.UpdateParam[](2);
        deltaParams[0] = ReservesLibrary.UpdateParam(ReservesType.REAL, delta);
        deltaParams[1] = ReservesLibrary.UpdateParam(ReservesType.PAIR, delta);
        self.updateReserves(deltaParams);

        self.positions.get(params.owner, params.salt).update(finalLiquidityDelta, delta);
    }

    struct SwapParams {
        address sender;
        // zeroForOne Whether to swap token0 for token1
        bool zeroForOne;
        // The amount to swap, negative for exact input, positive for exact output
        int256 amountSpecified;
        // Whether to use the mirror reserves for the swap
        bool useMirror;
        bytes32 salt;
    }

    /// @notice Swaps tokens in the pool
    /// @param self The pool state
    /// @param params The parameters for the swap
    /// @return swapDelta The change in balances
    /// @return amountToProtocol The amount of fees to be sent to the protocol
    /// @return swapFee The fee for the swap
    /// @return feeAmount The total fee amount for the swap.
    function swap(State storage self, SwapParams memory params, uint24 defaultProtocolFee)
        internal
        returns (BalanceDelta swapDelta, uint256 amountToProtocol, uint24 swapFee, uint256 feeAmount)
    {
        Reserves _pairReserves = self.pairReserves;
        Reserves _truncatedReserves = self.truncatedReserves;
        Slot0 _slot0 = self.slot0;
        uint24 _lpFee = _slot0.lpFee();

        bool exactIn = params.amountSpecified < 0;

        uint256 amountIn;
        uint256 amountOut;

        if (exactIn) {
            amountIn = uint256(-params.amountSpecified);
            (amountOut, swapFee, feeAmount) =
                SwapMath.getAmountOut(_pairReserves, _truncatedReserves, _lpFee, params.zeroForOne, amountIn);
        } else {
            amountOut = uint256(params.amountSpecified);
            (amountIn, swapFee, feeAmount) =
                SwapMath.getAmountIn(_pairReserves, _truncatedReserves, _lpFee, params.zeroForOne, amountOut);
        }

        (amountToProtocol, feeAmount) =
            ProtocolFeeLibrary.splitFee(_slot0.protocolFee(defaultProtocolFee), FeeTypes.SWAP, feeAmount);

        int128 amount0Delta;
        int128 amount1Delta;

        if (params.zeroForOne) {
            amount0Delta = -amountIn.toInt128();
            amount1Delta = amountOut.toInt128();
        } else {
            amount0Delta = amountOut.toInt128();
            amount1Delta = -amountIn.toInt128();
        }

        ReservesLibrary.UpdateParam[] memory deltaParams;
        swapDelta = toBalanceDelta(amount0Delta, amount1Delta);
        if (!params.useMirror) {
            deltaParams = new ReservesLibrary.UpdateParam[](2);
            deltaParams[0] = ReservesLibrary.UpdateParam(ReservesType.REAL, swapDelta);
            deltaParams[1] = ReservesLibrary.UpdateParam(ReservesType.PAIR, swapDelta);
        } else {
            deltaParams = new ReservesLibrary.UpdateParam[](3);
            BalanceDelta realDelta;
            BalanceDelta lendDelta;
            if (params.zeroForOne) {
                realDelta = toBalanceDelta(amount0Delta, 0);
                lendDelta = toBalanceDelta(0, -amount1Delta);
            } else {
                realDelta = toBalanceDelta(0, amount1Delta);
                lendDelta = toBalanceDelta(-amount0Delta, 0);
            }
            deltaParams[0] = ReservesLibrary.UpdateParam(ReservesType.REAL, realDelta);
            // pair MIRROR<=>lend MIRROR
            deltaParams[1] = ReservesLibrary.UpdateParam(ReservesType.LEND, lendDelta);
            deltaParams[2] = ReservesLibrary.UpdateParam(ReservesType.PAIR, swapDelta);
            uint256 depositCumulativeLast;
            if (params.zeroForOne) {
                depositCumulativeLast = self.deposit1CumulativeLast;
            } else {
                depositCumulativeLast = self.deposit0CumulativeLast;
            }
            self.lendPositions.get(params.sender, params.zeroForOne, params.salt).update(
                params.zeroForOne, depositCumulativeLast, lendDelta
            );
        }
        self.updateReserves(deltaParams);
    }

    struct LendParams {
        address sender;
        /// False if lend token0,true if lend token1
        bool lendForOne;
        /// The amount to lend, negative for deposit, positive for withdraw
        int128 lendAmount;
        bytes32 salt;
    }

    /// @notice Lends tokens to the pool.
    /// @param self The pool state.
    /// @param params The parameters for the lending operation.
    /// @return lendDelta The change in the lender's balance.
    /// @return depositCumulativeLast The last cumulative deposit rate.
    function lend(State storage self, LendParams memory params)
        internal
        returns (BalanceDelta lendDelta, uint256 depositCumulativeLast)
    {
        int128 amount0Delta;
        int128 amount1Delta;

        if (params.lendForOne) {
            amount1Delta = params.lendAmount;
            depositCumulativeLast = self.deposit1CumulativeLast;
        } else {
            amount0Delta = params.lendAmount;
            depositCumulativeLast = self.deposit0CumulativeLast;
        }

        lendDelta = toBalanceDelta(amount0Delta, amount1Delta);
        ReservesLibrary.UpdateParam[] memory deltaParams = new ReservesLibrary.UpdateParam[](2);
        deltaParams[0] = ReservesLibrary.UpdateParam(ReservesType.REAL, lendDelta);
        deltaParams[1] = ReservesLibrary.UpdateParam(ReservesType.LEND, lendDelta);
        self.updateReserves(deltaParams);

        self.lendPositions.get(params.sender, params.lendForOne, params.salt).update(
            params.lendForOne, depositCumulativeLast, lendDelta
        );
    }

    function margin(State storage self, MarginBalanceDelta memory params, uint24 defaultProtocolFee)
        internal
        returns (BalanceDelta marginDelta, uint256 amountToProtocol, uint256 feeAmount)
    {
        if (
            (params.action != MarginActions.CLOSE && params.action != MarginActions.LIQUIDATE_BURN)
                && params.marginDelta == BalanceDeltaLibrary.ZERO_DELTA
        ) {
            InsufficientAmount.selector.revertWith();
        }
        Slot0 _slot0 = self.slot0;
        if (params.action == MarginActions.MARGIN) {
            (, feeAmount) = params.marginFee.deduct(params.marginTotal);
            (amountToProtocol,) =
                ProtocolFeeLibrary.splitFee(_slot0.protocolFee(defaultProtocolFee), FeeTypes.MARGIN, feeAmount);
        }
        marginDelta = params.marginDelta;
        if (params.debtDepositCumulativeLast > 0) {
            if (params.marginForOne) {
                self.deposit0CumulativeLast = params.debtDepositCumulativeLast;
            } else {
                self.deposit1CumulativeLast = params.debtDepositCumulativeLast;
            }
        }
        ReservesLibrary.UpdateParam[] memory deltaParams = new ReservesLibrary.UpdateParam[](4);
        deltaParams[0] = ReservesLibrary.UpdateParam(ReservesType.REAL, marginDelta);
        deltaParams[1] = ReservesLibrary.UpdateParam(ReservesType.PAIR, params.pairDelta);
        deltaParams[2] = ReservesLibrary.UpdateParam(ReservesType.LEND, params.lendDelta);
        deltaParams[3] = ReservesLibrary.UpdateParam(ReservesType.MIRROR, params.mirrorDelta);
        self.updateReserves(deltaParams);
    }

    /// @notice Reverts if the given pool has not been initialized
    /// @param self The pool state
    function checkPoolInitialized(State storage self) internal view {
        if (self.borrow0CumulativeLast == 0) PoolNotInitialized.selector.revertWith();
    }

    /// @notice Updates the interest rates for the pool.
    /// @param self The pool state.
    /// @param marginState The current rate state.
    /// @return pairInterest0 The interest earned by the pair for token0.
    /// @return pairInterest1 The interest earned by the pair for token1.
    function updateInterests(State storage self, MarginState marginState, uint24 defaultProtocolFee)
        internal
        returns (uint256 pairInterest0, uint256 pairInterest1)
    {
        Slot0 _slot0 = self.slot0;
        uint256 timeElapsed = _slot0.lastUpdated().getTimeElapsed();
        if (timeElapsed == 0) return (0, 0);

        Reserves _realReserves = self.realReserves;
        Reserves _mirrorReserves = self.mirrorReserves;
        Reserves _interestReserves = self.interestReserves;
        Reserves _pairReserves = self.pairReserves;
        Reserves _lendReserves = self.lendReserves;

        uint256 borrow0CumulativeBefore = self.borrow0CumulativeLast;
        uint256 borrow1CumulativeBefore = self.borrow1CumulativeLast;

        (uint256 borrow0CumulativeLast, uint256 borrow1CumulativeLast) = InterestMath.getBorrowRateCumulativeLast(
            timeElapsed, borrow0CumulativeBefore, borrow1CumulativeBefore, marginState, _realReserves, _mirrorReserves
        );
        (uint256 pairReserve0, uint256 pairReserve1) = _pairReserves.reserves();
        (uint256 lendReserve0, uint256 lendReserve1) = _lendReserves.reserves();
        (uint256 mirrorReserve0, uint256 mirrorReserve1) = _mirrorReserves.reserves();
        (uint256 interestReserve0, uint256 interestReserve1) = _interestReserves.reserves();

        InterestMath.InterestUpdateResult memory result0 = InterestMath.updateInterestForOne(
            InterestMath.InterestUpdateParams({
                mirrorReserve: mirrorReserve0,
                borrowCumulativeLast: borrow0CumulativeLast,
                borrowCumulativeBefore: borrow0CumulativeBefore,
                interestReserve: interestReserve0,
                pairReserve: pairReserve0,
                lendReserve: lendReserve0,
                depositCumulativeLast: self.deposit0CumulativeLast,
                protocolFee: _slot0.protocolFee(defaultProtocolFee)
            })
        );

        if (result0.changed) {
            mirrorReserve0 = result0.newMirrorReserve;
            pairReserve0 = result0.newPairReserve;
            lendReserve0 = result0.newLendReserve;
            interestReserve0 = result0.newInterestReserve;
            self.deposit0CumulativeLast = result0.newDepositCumulativeLast;
            pairInterest0 = result0.pairInterest;
            self.borrow0CumulativeLast = borrow0CumulativeLast;
        }

        InterestMath.InterestUpdateResult memory result1 = InterestMath.updateInterestForOne(
            InterestMath.InterestUpdateParams({
                mirrorReserve: mirrorReserve1,
                borrowCumulativeLast: borrow1CumulativeLast,
                borrowCumulativeBefore: borrow1CumulativeBefore,
                interestReserve: interestReserve1,
                pairReserve: pairReserve1,
                lendReserve: lendReserve1,
                depositCumulativeLast: self.deposit1CumulativeLast,
                protocolFee: _slot0.protocolFee(defaultProtocolFee)
            })
        );

        if (result1.changed) {
            mirrorReserve1 = result1.newMirrorReserve;
            pairReserve1 = result1.newPairReserve;
            lendReserve1 = result1.newLendReserve;
            interestReserve1 = result1.newInterestReserve;
            self.deposit1CumulativeLast = result1.newDepositCumulativeLast;
            pairInterest1 = result1.pairInterest;
            self.borrow1CumulativeLast = borrow1CumulativeLast;
        }

        if (result0.changed || result1.changed) {
            self.mirrorReserves = toReserves(mirrorReserve0.toUint128(), mirrorReserve1.toUint128());
            self.pairReserves = toReserves(pairReserve0.toUint128(), pairReserve1.toUint128());
            self.lendReserves = toReserves(lendReserve0.toUint128(), lendReserve1.toUint128());
            Reserves _truncatedReserves = self.truncatedReserves;
            self.truncatedReserves = PriceMath.transferReserves(
                _truncatedReserves,
                _pairReserves,
                _slot0.lastUpdated().getTimeElapsed(),
                marginState.maxPriceMovePerSecond()
            );
        } else {
            self.truncatedReserves = _pairReserves;
        }

        self.interestReserves = toReserves(interestReserve0.toUint128(), interestReserve1.toUint128());
        self.slot0 = self.slot0.setLastUpdated(uint32(block.timestamp));
    }

    /// @notice Updates the reserves of the pool.
    /// @param self The pool state.
    /// @param params An array of parameters for updating the reserves.
    function updateReserves(State storage self, ReservesLibrary.UpdateParam[] memory params) internal {
        if (params.length == 0) return;
        Reserves _realReserves = self.realReserves;
        Reserves _mirrorReserves = self.mirrorReserves;
        Reserves _pairReserves = self.pairReserves;
        Reserves _lendReserves = self.lendReserves;
        for (uint256 i = 0; i < params.length; i++) {
            ReservesType _type = params[i]._type;
            BalanceDelta delta = params[i].delta;
            if (_type == ReservesType.REAL) {
                _realReserves = _realReserves.applyDelta(delta);
            } else if (_type == ReservesType.MIRROR) {
                _mirrorReserves = _mirrorReserves.applyDelta(delta, true);
            } else if (_type == ReservesType.PAIR) {
                _pairReserves = _pairReserves.applyDelta(delta);
            } else if (_type == ReservesType.LEND) {
                _lendReserves = _lendReserves.applyDelta(delta);
            }
        }
        self.realReserves = _realReserves;
        self.mirrorReserves = _mirrorReserves;
        self.pairReserves = _pairReserves;
        self.lendReserves = _lendReserves;
    }
}
