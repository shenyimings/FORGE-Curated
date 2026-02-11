// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";
import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
import {packedFloat, MathLibs} from "src/amm/mathLibs/MathLibs.sol";

/**
 * @title Test Pool functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55
 */
abstract contract PoolPrecisionTest is TestCommonSetup {
    using MathLibs for packedFloat;
    uint8 constant MAX_TOLERANCE_X = 12;
    uint8 constant TOLERANCE_PRECISION_X = 12;
    uint256 constant TOLERANCE_DEN_X = 10 ** TOLERANCE_PRECISION_X;

    uint MAX_SUPPLY = 10e4 * ERC20_DECIMALS;
    PoolBase wadPool;
    PoolBase sdPool;
    IERC20 wadYToken;
    IERC20 sdYToken;
    IERC20 wadXToken;
    IERC20 sdXToken;

    function _setUp(uint16 _fee) internal {
        (wadPool, sdPool) = _setupPrecisionPools(MAX_SUPPLY, _fee);
        _assignTokens();
    }

    function _assignTokens() internal {
        wadXToken = IERC20(wadPool.xToken());
        sdXToken = IERC20(sdPool.xToken());
        wadYToken = IERC20(wadPool.yToken());
        sdYToken = IERC20(sdPool.yToken());
    }

    function _normalizeTokenDecimals(uint rawAmount) internal pure returns (uint normalizedAmount) {
        normalizedAmount = rawAmount / (10 ** 12);
    }

    function _swapX(
        bool isBuy,
        PoolBase _pool,
        uint swapAmount
    ) internal returns (uint256 amountOut, uint256 feeAmount, uint256 expected, uint256 expectedReverse) {
        IERC20 _yToken = IERC20(_pool.yToken());
        IERC20 _xToken = IERC20(_pool.xToken());

        IERC20 tokenIn = isBuy ? _yToken : _xToken;
        IERC20 tokenOut = isBuy ? _xToken : _yToken;
        console2.log("before simswap");
        (expected, , ) = _pool.simSwap(address(tokenIn), swapAmount);
        console2.log("after simswap");
        try _pool.simSwapReversed(address(tokenOut), expected) returns (uint expectedAmount, uint, uint) {
            expectedReverse = expectedAmount;
        } catch {
            console2.log("buy x failed");
        }

        (amountOut, feeAmount, ) = _pool.swap(address(tokenIn), swapAmount, expected, admin, getValidExpiration());
    }

    function test_poolPrecision_swapTests() public startAsAdmin endWithStopPrank {
        uint buyAmountSixDecimal = 1_000_000;
        uint buyAmountWad = 1_000_000_000_000_000_000;

        uint xBalanceAdminWad = wadXToken.balanceOf(address(admin));
        uint xBalanceAdminSd = sdXToken.balanceOf(address(admin));

        uint SWAPS = 1000;
        console2.log("x liquidity wad pool: ", IERC20(wadPool.xToken()).balanceOf(address(wadPool)));
        console2.log("x liquidity sd pool: ", xToken.balanceOf(address(sdPool)));
        uint256 expectedReverseWad;
        uint256 expectedReverseSd;
        for (uint i = 0; i < SWAPS; i++) {
            (, , , expectedReverseWad) = _swapX(true, wadPool, buyAmountWad);
            (, , , expectedReverseSd) = _swapX(true, sdPool, buyAmountSixDecimal);

            assertTrue(buyAmountWad >= expectedReverseWad);
            assertTrue(buyAmountSixDecimal >= expectedReverseSd);

            uint yBalanceWad = wadYToken.balanceOf(address(wadPool));
            uint xBalanceWad = wadXToken.balanceOf(address(wadPool));

            uint yBalanceSd = sdYToken.balanceOf(address(sdPool));
            uint xBalanceSd = sdXToken.balanceOf(address(sdPool));

            console2.log("x wad pool: ", wadPool.x().convertpackedFloatToWAD());
            console2.log("x sd pool: ", sdPool.x().convertpackedFloatToWAD());

            assertTrue(areWithinTolerance(xBalanceWad, xBalanceSd, 9, 9), "x balances should be within tolerance after buy");
            assertTrue(
                areWithinTolerance(yBalanceSd * 10 ** 12, yBalanceWad, MAX_TOLERANCE_X, TOLERANCE_PRECISION_X),
                "x out of tolerance"
            );
        }

        xBalanceAdminWad = wadXToken.balanceOf(address(admin)) - xBalanceAdminWad;
        xBalanceAdminSd = sdXToken.balanceOf(address(admin)) - xBalanceAdminSd;
        uint sellAmountSixDecimal = xBalanceAdminSd / SWAPS;
        uint sellAmountWad = xBalanceAdminWad / SWAPS;
        console2.log("sellAmountSixDecimal: ", sellAmountSixDecimal);
        console2.log("sellAmountWad", sellAmountWad);

        for (uint i = 0; i < SWAPS; i++) {
            (uint256 amountOutWad, , , ) = _swapX(false, wadPool, sellAmountWad);
            (uint256 amountOutSd, , , ) = _swapX(false, sdPool, sellAmountSixDecimal);
            assertTrue(amountOutSd <= amountOutWad, "amount out in six decimal should not exceed amount out in wad");

            uint yBalanceWad = wadYToken.balanceOf(address(wadPool));
            uint xBalanceWad = wadXToken.balanceOf(address(wadPool));

            uint yBalanceSd = sdYToken.balanceOf(address(sdPool));
            uint xBalanceSd = sdXToken.balanceOf(address(sdPool));

            assertTrue(areWithinTolerance(xBalanceWad, xBalanceSd, 9, 9), "x pool balances should be within tolerance");
            assertTrue(yBalanceWad <= (yBalanceSd * 10 ** 12), "y balance in six decimal should not exceed amount out in wad");
        }
    }
}
