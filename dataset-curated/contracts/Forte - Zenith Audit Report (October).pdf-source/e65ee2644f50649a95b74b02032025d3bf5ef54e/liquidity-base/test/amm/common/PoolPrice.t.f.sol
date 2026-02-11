// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";
import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
import {PoolCommonAbs} from "test/amm/common/PoolCommonAbs.sol";
import {packedFloat, MathLibs} from "src/amm/mathLibs/MathLibs.sol";

/**
 * @title Test Pool functionality
 * @dev fuzz test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract PoolPriceFuzzTest is TestCommonSetup, PoolCommonAbs {
    using MathLibs for packedFloat;
    using MathLibs for int256;

    function testLiquidity_Pool_priceAlwaysGoesUpToTheRight(uint256 amount) public startAsAdmin {
        amount = bound(amount, address(_yToken) == address(stableCoin) ? amountMinBound : 10, 1_000 * fullToken);

        _yToken.approve(address(pool), amount);
        (uint256 toutOp, , ) = pool.simSwap(address(_yToken), amount);
        pool.swap(address(_yToken), amount, toutOp, msg.sender, getValidExpiration());
        uint256 priceBefore = pool.spotPrice();

        _yToken.approve(address(pool), amount);
        (toutOp, , ) = pool.simSwap(address(_yToken), amount);
        pool.swap(address(_yToken), amount, toutOp, msg.sender, getValidExpiration());
        uint256 priceAfter = pool.spotPrice();

        assert(priceAfter >= priceBefore);
    }

    function swapAndVerifyPriceChange(uint256 amount) public startAsAdmin {
        uint256 priceBefore = pool.spotPrice();

        _yToken.approve(address(pool), amount);
        (uint256 toutOp, , ) = pool.simSwap(address(_yToken), amount);
        pool.swap(address(_yToken), amount, toutOp, msg.sender, getValidExpiration());
        uint256 priceAfter = pool.spotPrice();

        assert(priceAfter >= priceBefore);
    }

    function testLiquidity_PoolToB_priceAlwaysGoesUpToTheRight_A(uint256 amountA, uint256 amountB) public {
        amountA = bound(amountA, 1e6 * fullToken, 1e9 * fullToken); // big initial number
        amountB = bound(amountB, address(_yToken) == address(stableCoin) ? amountMinBound : 10, 1 * fullToken); // small number
        swapAndVerifyPriceChange(amountA);
        swapAndVerifyPriceChange(amountB);
    }

    function testLiquidity_Pool_priceImpactAlwaysDecreases(uint256 amount) public startAsAdmin {
        amount = bound(amount, address(_yToken) == address(stableCoin) ? amountMinBound : 10, 1e3 * fullToken);
        _yToken.approve(address(pool), amount * 2);

        packedFloat currentX = PoolBase(address(pool)).x();
        uint currentPrice = pool.spotPrice();

        (uint256 tout, , ) = pool.simSwap(address(_yToken), amount);
        pool.swap(address(_yToken), amount, tout, msg.sender, getValidExpiration());

        uint _currentPrice = pool.spotPrice();
        assertLe(currentPrice, _currentPrice, "Price decreased");
        uint currentImpact = _currentPrice - currentPrice;
        currentX = PoolBase(address(pool)).x();
        currentPrice = _currentPrice;

        uint256 afterImpact;
        (tout, , ) = pool.simSwap(address(_yToken), amount);
        pool.swap(address(_yToken), amount, tout, msg.sender, getValidExpiration());

        afterImpact = pool.spotPrice() - currentPrice;
        console2.log(currentImpact, afterImpact);
        assert(afterImpact <= currentImpact + 1);
    }

    function testLiquidity_Pool_priceAlwaysIncreasesForSameX(uint256 amount, uint256 initialAmount) public startAsAdmin {
        amount = bound(amount, address(_yToken) == address(stableCoin) ? amountMinBound : 10, 1_000 * fullToken);
        initialAmount = bound(amount, address(_yToken) == address(stableCoin) ? amountMinBound : 10, 1_000 * fullToken);
        console2.log("amount", amount);

        _yToken.approve(address(pool), initialAmount);
        (uint256 toutOp, , ) = pool.simSwap(address(_yToken), initialAmount);
        pool.swap(address(_yToken), initialAmount, getAmountSubFee(toutOp), msg.sender, getValidExpiration());

        packedFloat xBefore = PoolBase(address(pool)).x();
        uint256 priceBefore = pool.spotPrice();
        _yToken.approve(address(pool), amount);
        (toutOp, , ) = pool.simSwap(address(_yToken), amount);
        pool.swap(address(_yToken), amount, getAmountSubFee(toutOp), msg.sender, getValidExpiration());
        address _xToken = pool.xToken();

        IERC20(_xToken).approve(address(pool), toutOp);
        /// therre are 2 fees
        (uint yOut, , ) = pool.simSwap(_xToken, getAmountSubFee(getAmountSubFee(toutOp)));
        if (yOut > 0) {
            pool.swap(_xToken, toutOp, yOut, msg.sender, getValidExpiration());
            uint256 priceAfter = pool.spotPrice();
            packedFloat xAfter = PoolBase(address(pool)).x();
            console2.log(priceBefore, priceAfter);
            if (transferFee == 0) assertEq(xBefore.convertpackedFloatToWAD(), xAfter.convertpackedFloatToWAD());
            assertGe((priceAfter), priceBefore);
        }
    }
}
