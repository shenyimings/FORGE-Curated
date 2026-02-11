// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

// Solmate
import {Owned} from "solmate/src/auth/Owned.sol";

import {PoolState} from "../../src/types/PoolState.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {MarginLevels} from "../../src/types/MarginLevels.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IMarginPositionManager} from "../../src/interfaces/IMarginPositionManager.sol";
import {IMarginBase} from "../../src/interfaces/IMarginBase.sol";
import {MarginState} from "../../src/types/MarginState.sol";
import {StageMath} from "../../src/libraries/StageMath.sol";
import {Math} from "../../src/libraries/Math.sol";
import {StateLibrary} from "../../src/libraries/StateLibrary.sol";
import {PerLibrary} from "../../src/libraries/PerLibrary.sol";
import {SwapMath} from "../../src/libraries/SwapMath.sol";
import {StageMath} from "../../src/libraries/StageMath.sol";
import {InterestMath} from "../../src/libraries/InterestMath.sol";
import {MarginPosition} from "../../src/libraries/MarginPosition.sol";

contract LikwidHelper is Owned {
    using PerLibrary for uint256;
    using StageMath for uint256;

    IVault public vault;

    constructor(address initialOwner, IVault _vault) Owned(initialOwner) {
        vault = _vault;
    }

    struct PoolStateInfo {
        uint128 totalSupply;
        uint32 lastUpdated;
        uint24 lpFee;
        uint24 marginFee;
        uint24 protocolFee;
        uint128 realReserve0;
        uint128 realReserve1;
        uint128 mirrorReserve0;
        uint128 mirrorReserve1;
        uint128 pairReserve0;
        uint128 pairReserve1;
        uint128 truncatedReserve0;
        uint128 truncatedReserve1;
        uint128 lendReserve0;
        uint128 lendReserve1;
        uint128 interestReserve0;
        uint128 interestReserve1;
        uint256 borrow0CumulativeLast;
        uint256 borrow1CumulativeLast;
        uint256 deposit0CumulativeLast;
        uint256 deposit1CumulativeLast;
    }

    function getPoolStateInfo(PoolId poolId) external view returns (PoolStateInfo memory stateInfo) {
        PoolState memory state = StateLibrary.getCurrentState(vault, poolId);
        stateInfo.totalSupply = state.totalSupply;
        stateInfo.lastUpdated = state.lastUpdated;
        stateInfo.lpFee = state.lpFee;
        stateInfo.marginFee = state.marginFee;
        stateInfo.protocolFee = state.protocolFee;
        (uint128 realReserve0, uint128 realReserve1) = state.realReserves.reserves();
        stateInfo.realReserve0 = realReserve0;
        stateInfo.realReserve1 = realReserve1;
        (uint128 mirrorReserve0, uint128 mirrorReserve1) = state.mirrorReserves.reserves();
        stateInfo.mirrorReserve0 = mirrorReserve0;
        stateInfo.mirrorReserve1 = mirrorReserve1;
        (uint128 pairReserve0, uint128 pairReserve1) = state.pairReserves.reserves();
        stateInfo.pairReserve0 = pairReserve0;
        stateInfo.pairReserve1 = pairReserve1;
        (uint128 truncatedReserve0, uint128 truncatedReserve1) = state.truncatedReserves.reserves();
        stateInfo.truncatedReserve0 = truncatedReserve0;
        stateInfo.truncatedReserve1 = truncatedReserve1;
        (uint128 lendReserve0, uint128 lendReserve1) = state.lendReserves.reserves();
        stateInfo.lendReserve0 = lendReserve0;
        stateInfo.lendReserve1 = lendReserve1;
        (uint128 interestReserve0, uint128 interestReserve1) = state.interestReserves.reserves();
        stateInfo.interestReserve0 = interestReserve0;
        stateInfo.interestReserve1 = interestReserve1;

        stateInfo.borrow0CumulativeLast = state.borrow0CumulativeLast;
        stateInfo.borrow1CumulativeLast = state.borrow1CumulativeLast;
        stateInfo.deposit0CumulativeLast = state.deposit0CumulativeLast;
        stateInfo.deposit1CumulativeLast = state.deposit1CumulativeLast;
    }

    function getAmountOut(PoolId poolId, bool zeroForOne, uint256 amountIn, bool dynamicFee)
        external
        view
        returns (uint256 amountOut, uint24 fee, uint256 feeAmount)
    {
        PoolState memory state = StateLibrary.getCurrentState(vault, poolId);
        fee = state.lpFee;
        if (!dynamicFee) {
            (amountOut, feeAmount) = SwapMath.getAmountOut(state.pairReserves, fee, zeroForOne, amountIn);
        } else {
            (amountOut, fee, feeAmount) =
                SwapMath.getAmountOut(state.pairReserves, state.truncatedReserves, fee, zeroForOne, amountIn);
        }
    }

    function getAmountIn(PoolId poolId, bool zeroForOne, uint256 amountOut, bool dynamicFee)
        external
        view
        returns (uint256 amountIn, uint24 fee, uint256 feeAmount)
    {
        PoolState memory state = StateLibrary.getCurrentState(vault, poolId);
        fee = state.lpFee;
        if (!dynamicFee) {
            (amountIn, feeAmount) = SwapMath.getAmountIn(state.pairReserves, fee, zeroForOne, amountOut);
        } else {
            (amountIn, fee, feeAmount) =
                SwapMath.getAmountIn(state.pairReserves, state.truncatedReserves, fee, zeroForOne, amountOut);
        }
    }

    function _getBorrowRate(PoolState memory state, bool marginForOne) internal pure returns (uint256) {
        (uint128 realReserve0, uint128 realReserve1) = state.realReserves.reserves();
        (uint128 mirrorReserve0, uint128 mirrorReserve1) = state.mirrorReserves.reserves();
        uint256 borrowReserve;
        uint256 mirrorReserve;
        if (marginForOne) {
            mirrorReserve = mirrorReserve0;
            borrowReserve = mirrorReserve0 + realReserve0;
        } else {
            mirrorReserve = mirrorReserve1;
            borrowReserve = mirrorReserve1 + realReserve1;
        }
        return InterestMath.getBorrowRateByReserves(state.marginState, borrowReserve, mirrorReserve);
    }

    function getBorrowRate(PoolId poolId, bool marginForOne) external view returns (uint256) {
        PoolState memory state = StateLibrary.getCurrentState(vault, poolId);
        return _getBorrowRate(state, marginForOne);
    }

    function getPoolFees(PoolId poolId, bool zeroForOne, uint256 amountIn, uint256 amountOut)
        external
        view
        returns (uint24 _fee, uint24 _marginFee)
    {
        PoolState memory state = StateLibrary.getCurrentState(vault, poolId);
        uint256 degree = SwapMath.getPriceDegree(
            state.pairReserves, state.truncatedReserves, state.lpFee, zeroForOne, amountIn, amountOut
        );
        _fee = SwapMath.dynamicFee(state.lpFee, degree);
        IMarginPositionManager manager = IMarginPositionManager(vault.marginController());
        _marginFee = state.marginFee == 0 ? manager.defaultMarginFee() : state.marginFee;
    }

    function _getMaxDecrease(
        IMarginPositionManager manager,
        PoolState memory _state,
        MarginPosition.State memory _position
    ) internal view returns (uint256 maxAmount) {
        MarginLevels marginLevels = manager.marginLevels();
        uint24 minBorrowLevel = marginLevels.minBorrowLevel();
        (uint128 pairReserve0, uint128 pairReserve1) = _state.pairReserves.reserves();
        (uint256 reserveBorrow, uint256 reserveMargin) =
            _position.marginForOne ? (pairReserve0, pairReserve1) : (pairReserve1, pairReserve0);
        uint256 needAmount;
        uint256 debtAmount = uint256(_position.debtAmount).mulDivMillion(minBorrowLevel);
        if (_position.marginTotal > 0) {
            needAmount = Math.mulDiv(reserveMargin, debtAmount, reserveBorrow);
        } else {
            (needAmount,) = SwapMath.getAmountIn(_state.pairReserves, _state.lpFee, !_position.marginForOne, debtAmount);
        }
        uint256 assetAmount = _position.marginAmount + _position.marginTotal;

        if (needAmount < assetAmount) {
            maxAmount = assetAmount - needAmount;
        }
        maxAmount = Math.min(uint256(_position.marginAmount), maxAmount);
    }

    function getMaxDecrease(uint256 tokenId) external view returns (uint256 maxAmount) {
        IMarginPositionManager manager = IMarginPositionManager(vault.marginController());
        MarginPosition.State memory _position = manager.getPositionState(tokenId);
        IVault _vault = manager.vault();
        PoolId poolId = manager.poolIds(tokenId);
        PoolState memory _state = StateLibrary.getCurrentState(_vault, poolId);
        maxAmount = _getMaxDecrease(manager, _state, _position);
    }

    function minMarginLevels() external view returns (uint24 minMarginLevel, uint24 minBorrowLevel) {
        MarginLevels marginLevels = IMarginPositionManager(vault.marginController()).marginLevels();
        minMarginLevel = marginLevels.minMarginLevel();
        minBorrowLevel = marginLevels.minBorrowLevel();
    }

    function getLiquidateRepayAmount(uint256 tokenId) external view returns (uint256 repayAmount) {
        IMarginPositionManager manager = IMarginPositionManager(vault.marginController());
        MarginPosition.State memory _position = manager.getPositionState(tokenId);
        IVault _vault = manager.vault();
        PoolId poolId = manager.poolIds(tokenId);
        PoolState memory _state = StateLibrary.getCurrentState(_vault, poolId);
        (uint128 pairReserve0, uint128 pairReserve1) = _state.pairReserves.reserves();
        (uint256 reserveBorrow, uint256 reserveMargin) =
            _position.marginForOne ? (pairReserve0, pairReserve1) : (pairReserve1, pairReserve0);
        repayAmount = Math.mulDiv(reserveBorrow, _position.marginAmount + _position.marginTotal, reserveMargin);
        MarginLevels marginLevels = manager.marginLevels();
        repayAmount = repayAmount.mulDivMillion(marginLevels.liquidationRatio());
    }

    function getLendingAPR(PoolId poolId, bool borrowForOne, uint256 inputAmount) public view returns (uint256 apr) {
        PoolState memory _state = StateLibrary.getCurrentState(vault, poolId);
        (uint128 mirrorReserve0, uint128 mirrorReserve1) = _state.mirrorReserves.reserves();
        uint256 mirrorReserve = borrowForOne ? mirrorReserve1 : mirrorReserve0;
        uint256 borrowRate = _getBorrowRate(_state, !borrowForOne);
        (uint256 reserve0, uint256 reserve1) = _state.pairReserves.reserves();
        (uint256 lendReserve0, uint256 lendReserve1) = _state.lendReserves.reserves();
        uint256 flowReserve = borrowForOne ? reserve1 : reserve0;
        uint256 totalSupply = borrowForOne ? lendReserve1 : lendReserve0;
        uint256 allInterestReserve = flowReserve + inputAmount + totalSupply;
        if (allInterestReserve > 0) {
            apr = Math.mulDiv(borrowRate, mirrorReserve, allInterestReserve);
        }
    }

    function getBorrowAPR(PoolId poolId, bool borrowForOne) external view returns (uint256 rate) {
        PoolState memory _state = StateLibrary.getCurrentState(vault, poolId);
        (uint256 realReserve0, uint256 realReserve1) = _state.realReserves.reserves();
        (uint256 mirrorReserve0, uint256 mirrorReserve1) = _state.mirrorReserves.reserves();
        rate = borrowForOne
            ? InterestMath.getBorrowRateByReserves(_state.marginState, realReserve1 + mirrorReserve1, mirrorReserve1)
            : InterestMath.getBorrowRateByReserves(_state.marginState, realReserve0 + mirrorReserve0, mirrorReserve0);
    }

    function getStageLiquidities(PoolId poolId) external view returns (uint128[][] memory liquidities) {
        uint256[] memory queue = StateLibrary.getRawStageLiquidities(vault, poolId);
        liquidities = new uint128[][](queue.length);
        for (uint256 i = 0; i < queue.length; i++) {
            (uint128 total, uint128 liquidity) = queue[i].decode();
            liquidities[i] = new uint128[](2);
            liquidities[i][0] = total;
            liquidities[i][1] = liquidity;
        }
    }

    function getReleasedLiquidity(PoolId id) external view returns (uint128) {
        IMarginBase marginBase = IMarginBase(address(vault));
        MarginState marginState = marginBase.marginState();
        uint128 releasedLiquidity;
        uint128 nextReleasedLiquidity;
        releasedLiquidity = type(uint128).max;
        if (uint256(marginState.stageDuration()) * marginState.stageSize() > 0) {
            uint256[] memory queue = StateLibrary.getRawStageLiquidities(vault, id);
            uint256 lastStageTimestamp = StateLibrary.getLastStageTimestamp(vault, id);

            if (queue.length > 0) {
                uint256 currentStage = queue[0];
                (, releasedLiquidity) = StageMath.decode(currentStage);
                if (
                    queue.length > 1 && StageMath.isFree(currentStage, marginState.stageLeavePart())
                        && block.timestamp >= lastStageTimestamp + marginState.stageDuration()
                ) {
                    uint256 nextStage = queue[1];
                    (, nextReleasedLiquidity) = StageMath.decode(nextStage);
                }
            }
        }
        return releasedLiquidity + nextReleasedLiquidity;
    }

    function getStageState(PoolId id)
        external
        view
        returns (uint24 stageSize, uint24 stageLeavePart, uint24 stageDuration, uint256 lastStageTimestamp)
    {
        IMarginBase marginBase = IMarginBase(address(vault));
        MarginState marginState = marginBase.marginState();
        stageSize = marginState.stageSize();
        stageLeavePart = marginState.stageLeavePart();
        stageDuration = marginState.stageDuration();
        lastStageTimestamp = StateLibrary.getLastStageTimestamp(vault, id);
    }

    // ******************** OWNER CALL ********************

    function setVault(IVault _vault) external onlyOwner {
        vault = _vault;
    }
}
