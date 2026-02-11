/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PoolBase} from "src/amm/base/PoolBase.sol";
import {TestCommon} from "test/util/TestCommon.sol";

/**
 * @title Handler for testing to verify invariants related to transactions when the contract is paused.
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract pausedAuthorizationHandler is TestCommon {
    PoolBase public poolUnderTest;
    bool previousSwapX = false;
    constructor(PoolBase _poolUnderTest) {
        poolUnderTest = _poolUnderTest;
    }
    function swap(uint256 _amountIn) external returns (uint256 amountOut, uint256 feeAmount) {
        vm.startPrank(admin);
        if (previousSwapX) {
            (uint256 expectedAmountOut, , ) = poolUnderTest.simSwap(poolUnderTest.yToken(), _amountIn);
            (amountOut, feeAmount, ) = poolUnderTest.swap(poolUnderTest.yToken(), _amountIn, expectedAmountOut);
            previousSwapX = false;
        } else {
            (uint256 expectedAmountOut, , ) = poolUnderTest.simSwap(poolUnderTest.xToken(), _amountIn);
            (amountOut, feeAmount, ) = poolUnderTest.swap(poolUnderTest.xToken(), _amountIn, expectedAmountOut);
            previousSwapX = true;
        }
    }
}
