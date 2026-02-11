// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

/**
 * @title Test Common Foundry Setup Pure Abstract Functions
 */
abstract contract PoolCommonAbs {
    function _checkRevenueState() internal virtual;
    function _checkWithdrawRevenueState() internal virtual;
    function _getMinMaxX() internal virtual returns (uint, uint);
}
