// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {LikwidVault} from "../../src/LikwidVault.sol";
import {LikwidMarginPosition} from "../../src/LikwidMarginPosition.sol";
import {LikwidPairPosition} from "../../src/LikwidPairPosition.sol";
import {LikwidHelper} from "./LikwidHelper.sol";
import {IMarginPositionManager} from "../../src/interfaces/IMarginPositionManager.sol";
import {IPairPositionManager} from "../../src/interfaces/IPairPositionManager.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {PoolState} from "../../src/types/PoolState.sol";
import {Currency} from "../../src/types/Currency.sol";
import {MarginLevels} from "../../src/types/MarginLevels.sol";
import {MarginPosition} from "../../src/libraries/MarginPosition.sol";
import {SwapMath} from "../../src/libraries/SwapMath.sol";
import {InterestMath} from "../../src/libraries/InterestMath.sol";
import {Math} from "../../src/libraries/Math.sol";
import {PerLibrary} from "../../src/libraries/PerLibrary.sol";
import {StateLibrary} from "../../src/libraries/StateLibrary.sol";

contract LikwidHelperTest is Test {
    using PerLibrary for uint256;

    LikwidVault vault;
    LikwidMarginPosition marginPositionManager;
    LikwidPairPosition pairPositionManager;
    LikwidHelper public helper;
    PoolId public poolId;
    PoolKey public key;
    MockERC20 token0;
    MockERC20 token1;
    Currency currency0;
    Currency currency1;

    function setUp() public {
        vault = new LikwidVault(address(this));
        marginPositionManager = new LikwidMarginPosition(address(this), vault);
        pairPositionManager = new LikwidPairPosition(address(this), vault);
        helper = new LikwidHelper(address(this), vault);
        vault.setMarginController(address(marginPositionManager));
        // Deploy mock tokens
        address tokenA = address(new MockERC20("TokenA", "TKNA", 18));
        address tokenB = address(new MockERC20("TokenB", "TKNB", 18));

        // Ensure currency order
        if (tokenA < tokenB) {
            token0 = MockERC20(tokenA);
            token1 = MockERC20(tokenB);
        } else {
            token0 = MockERC20(tokenB);
            token1 = MockERC20(tokenA);
        }

        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        // Approve the vault to pull funds from this test contract
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
        token0.approve(address(marginPositionManager), type(uint256).max);
        token1.approve(address(marginPositionManager), type(uint256).max);
        token0.approve(address(pairPositionManager), type(uint256).max);
        token1.approve(address(pairPositionManager), type(uint256).max);

        uint24 fee = 3000; // 0.3%
        key = PoolKey({currency0: currency0, currency1: currency1, fee: fee});
        vault.initialize(key);
        poolId = key.toId();
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 20e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);
    }

    function testGetPoolStateInfo() public view {
        LikwidHelper.PoolStateInfo memory stateInfo = helper.getPoolStateInfo(poolId);
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 20e18;
        assertEq(stateInfo.lastUpdated, 1);
        assertEq(stateInfo.lpFee, 3000);
        assertEq(stateInfo.marginFee, 0);
        assertEq(stateInfo.protocolFee, 0);
        assertEq(stateInfo.realReserve0, amount0ToAdd, "stateInfo.realReserve0==amount0ToAdd");
        assertEq(stateInfo.realReserve1, amount1ToAdd, "stateInfo.realReserve1==amount1ToAdd");
        assertEq(stateInfo.mirrorReserve0, 0);
        assertEq(stateInfo.mirrorReserve1, 0);
        assertEq(stateInfo.pairReserve0, amount0ToAdd, "stateInfo.realReserve0==amount0ToAdd");
        assertEq(stateInfo.pairReserve1, amount1ToAdd, "stateInfo.realReserve1==amount1ToAdd");
        assertEq(stateInfo.truncatedReserve0, amount0ToAdd, "stateInfo.realReserve0==amount0ToAdd");
        assertEq(stateInfo.truncatedReserve1, amount1ToAdd, "stateInfo.realReserve1==amount1ToAdd");
        assertEq(stateInfo.lendReserve0, 0);
        assertEq(stateInfo.lendReserve1, 0);
        assertEq(stateInfo.interestReserve0, 0);
        assertEq(stateInfo.interestReserve1, 0);
    }

    function testGetStageLiquidities() public view {
        uint128[][] memory liquidities = helper.getStageLiquidities(poolId);
        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 20e18;
        uint256 stage = Math.sqrt(amount0ToAdd * amount1ToAdd) / 5 + 1;
        assertEq(liquidities.length, 5);
        assertEq(liquidities[0][1], stage);
        uint256 releasedLiquidity = helper.getReleasedLiquidity(poolId);
        assertEq(releasedLiquidity, stage);
    }

    function testHelperGetAmountOut() public {
        bool zeroForOne = true;
        uint256 amountIn = 1e17;
        (uint256 amountOut,,) = helper.getAmountOut(poolId, zeroForOne, amountIn, false);
        PoolState memory state = StateLibrary.getCurrentState(vault, poolId);
        (uint256 expectedAmountOut,) = SwapMath.getAmountOut(state.pairReserves, state.lpFee, zeroForOne, amountIn);
        assertEq(amountOut, expectedAmountOut);

        (amountOut,,) = helper.getAmountOut(poolId, zeroForOne, amountIn, true);
        (expectedAmountOut,,) =
            SwapMath.getAmountOut(state.pairReserves, state.truncatedReserves, state.lpFee, true, amountIn);
        assertEq(amountOut, expectedAmountOut);

        token0.mint(address(this), amountIn);

        IPairPositionManager.SwapInputParams memory params = IPairPositionManager.SwapInputParams({
            poolId: poolId,
            zeroForOne: zeroForOne,
            to: address(this),
            amountIn: amountIn,
            amountOutMin: 0,
            deadline: block.timestamp + 1
        });

        (,, uint256 actAmountOut) = pairPositionManager.exactInput(params);
        assertEq(actAmountOut, expectedAmountOut);
        assertEq(expectedAmountOut, token1.balanceOf(address(this)));
    }

    function testHelperGetAmountIn() public {
        bool zeroForOne = true;
        uint256 amountOut = 1e17;
        PoolState memory state = StateLibrary.getCurrentState(vault, poolId);

        (uint256 amountIn,,) = helper.getAmountIn(poolId, zeroForOne, amountOut, false);
        (uint256 expectedAmountIn,) = SwapMath.getAmountIn(state.pairReserves, state.lpFee, zeroForOne, amountOut);
        assertEq(amountIn, expectedAmountIn);

        (amountIn,,) = helper.getAmountIn(poolId, zeroForOne, amountOut, true);
        (expectedAmountIn,,) =
            SwapMath.getAmountIn(state.pairReserves, state.truncatedReserves, state.lpFee, zeroForOne, amountOut);
        assertEq(amountIn, expectedAmountIn);

        token0.mint(address(this), amountIn);

        IPairPositionManager.SwapOutputParams memory params = IPairPositionManager.SwapOutputParams({
            poolId: poolId,
            zeroForOne: zeroForOne,
            to: address(this),
            amountInMax: 20e18,
            amountOut: amountOut,
            deadline: block.timestamp + 1
        });

        (,, uint256 actAmountIn) = pairPositionManager.exactOutput(params);

        assertEq(actAmountIn, expectedAmountIn);
        assertEq(amountOut, token1.balanceOf(address(this)));
    }

    function testGetBorrowRate() public view {
        PoolState memory state = StateLibrary.getCurrentState(vault, poolId);

        uint256 borrowRate = helper.getBorrowRate(poolId, true);
        (uint128 realReserve0,) = state.realReserves.reserves();
        (uint128 mirrorReserve0,) = state.mirrorReserves.reserves();
        uint256 borrowReserve = mirrorReserve0 + realReserve0;
        uint256 mirrorReserve = mirrorReserve0;

        uint256 expectedBorrowRate =
            InterestMath.getBorrowRateByReserves(state.marginState, borrowReserve, mirrorReserve);
        assertEq(borrowRate, expectedBorrowRate);
        assertTrue(expectedBorrowRate > 0);
    }

    function testGetPoolFees() public view {
        PoolState memory state = StateLibrary.getCurrentState(vault, poolId);

        (uint24 fee, uint24 marginFee) = helper.getPoolFees(poolId, true, 1e17, 1e17);
        uint256 degree =
            SwapMath.getPriceDegree(state.pairReserves, state.truncatedReserves, state.lpFee, true, 1e17, 1e17);
        assertEq(fee, SwapMath.dynamicFee(state.lpFee, degree));
        assertEq(0, state.marginFee);
        assertEq(marginFee, marginPositionManager.defaultMarginFee());
    }

    function testGetMaxDecrease() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with token0, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, params);

        assertTrue(tokenId > 0);
        assertTrue(borrowAmount > 0);

        MarginPosition.State memory pos = marginPositionManager.getPositionState(tokenId);
        PoolState memory state = StateLibrary.getCurrentState(vault, poolId);
        (uint128 pairReserve0, uint128 pairReserve1) = state.pairReserves.reserves();
        (uint256 reserveBorrow, uint256 reserveMargin) =
            pos.marginForOne ? (pairReserve0, pairReserve1) : (pairReserve1, pairReserve0);

        MarginLevels marginLevels = marginPositionManager.marginLevels();
        uint24 minBorrowLevel = marginLevels.minBorrowLevel();

        uint256 maxDecrease = helper.getMaxDecrease(tokenId);
        uint256 debtAmount = uint256(pos.debtAmount).mulDivMillion(minBorrowLevel);
        uint256 needAmount = Math.mulDiv(reserveMargin, debtAmount, reserveBorrow);
        uint256 assetAmount = pos.marginAmount + pos.marginTotal;
        uint256 expectedMax = assetAmount - needAmount;
        assertTrue(maxDecrease > 0);
        assertEq(maxDecrease, expectedMax);
    }

    function testMinMarginLevels() public view {
        MarginLevels marginLevels = marginPositionManager.marginLevels();
        (uint24 minMarginLevel, uint24 minBorrowLevel) = helper.minMarginLevels();
        assertEq(minMarginLevel, marginLevels.minMarginLevel());
        assertEq(minBorrowLevel, marginLevels.minBorrowLevel());
    }

    function testGetLiquidateRepayAmount() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with token0, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, params);

        assertTrue(tokenId > 0);
        assertTrue(borrowAmount > 0);

        MarginPosition.State memory pos = marginPositionManager.getPositionState(tokenId);
        PoolState memory state = StateLibrary.getCurrentState(vault, poolId);
        (uint128 pairReserve0, uint128 pairReserve1) = state.pairReserves.reserves();
        (uint256 reserveBorrow, uint256 reserveMargin) =
            pos.marginForOne ? (pairReserve0, pairReserve1) : (pairReserve1, pairReserve0);

        uint256 repayAmount = helper.getLiquidateRepayAmount(tokenId);
        uint256 expectedRepay = Math.mulDiv(reserveBorrow, pos.marginAmount + pos.marginTotal, reserveMargin);
        MarginLevels marginLevels = marginPositionManager.marginLevels();
        expectedRepay = expectedRepay.mulDivMillion(marginLevels.liquidationRatio());
        assertEq(repayAmount, expectedRepay);
    }

    function testGetLendingAPR() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with token0, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, params);

        assertTrue(tokenId > 0);
        assertTrue(borrowAmount > 0);
        PoolState memory state = StateLibrary.getCurrentState(vault, poolId);
        uint256 rate0 = helper.getLendingAPR(poolId, false, marginAmount);
        uint256 rate1 = helper.getLendingAPR(poolId, true, marginAmount);
        assertTrue(rate0 < rate1);
        assertTrue(rate0 == 0);
        (, uint256 reserve1) = state.pairReserves.reserves();
        (, uint256 lendReserve1) = state.lendReserves.reserves();
        uint256 allInterestReserve = marginAmount + reserve1 + lendReserve1;
        uint256 borrowRate = helper.getBorrowAPR(poolId, true);
        uint256 apr = Math.mulDiv(borrowRate, borrowAmount, allInterestReserve);
        assertTrue(rate1 == apr);
    }

    function testGetBorrowAPR() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with token0, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, params);

        assertTrue(tokenId > 0);
        assertTrue(borrowAmount > 0);
        PoolState memory state = StateLibrary.getCurrentState(vault, poolId);
        uint256 rate0 = helper.getBorrowAPR(poolId, false);
        uint256 rate1 = helper.getBorrowAPR(poolId, true);
        assertTrue(rate0 < rate1);
        assertTrue(rate0 == state.marginState.rateBase());
    }
}
