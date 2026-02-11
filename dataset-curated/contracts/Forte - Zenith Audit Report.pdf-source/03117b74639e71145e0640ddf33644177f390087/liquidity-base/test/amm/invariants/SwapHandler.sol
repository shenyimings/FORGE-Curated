/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PoolBase} from "src/amm/base/PoolBase.sol";
import {TestCommon} from "test/util/TestCommon.sol";

/**
 * @title Handler for the testing the invariants defined for the swap mechanics.
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract SwapHandler is TestCommon {
    PoolBase public poolUnderTest;
    uint256 public trackedAmountOutX;
    constructor(PoolBase _poolUnderTest) {
        poolUnderTest = _poolUnderTest;
    }
    function swap(uint256 _amountIn) external returns (uint256 amountOut, uint256 feeAmount) {
        vm.startPrank(admin);
        (uint256 expectedAmountOut, , ) = poolUnderTest.simSwap(poolUnderTest.xToken(), _amountIn);
        (amountOut, feeAmount, ) = poolUnderTest.swap(poolUnderTest.xToken(), _amountIn, expectedAmountOut);
        trackedAmountOutX = amountOut;
    }
}
