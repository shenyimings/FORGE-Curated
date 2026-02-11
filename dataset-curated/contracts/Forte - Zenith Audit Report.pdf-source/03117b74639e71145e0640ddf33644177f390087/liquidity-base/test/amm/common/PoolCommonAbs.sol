// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

/**
 * @title Test Common Foundry Setup Pure Abstract Functions
 */
abstract contract PoolCommonAbs {
    function _checkLiquidityExcessState() internal virtual;
    function _checkWithdrawRevenueState() internal virtual;
    function _checkBackAndForthSwapsState() internal virtual;
    function _getMinMaxX() internal virtual returns (uint, uint);
}
