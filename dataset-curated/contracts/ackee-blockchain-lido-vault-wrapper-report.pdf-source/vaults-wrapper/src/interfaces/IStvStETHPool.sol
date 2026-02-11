// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IBasePool} from "./IBasePool.sol";

interface IStvStETHPool is IBasePool {
    function totalExceedingMintedSteth() external view returns (uint256);
    function rebalanceMintedStethSharesForWithdrawalQueue(uint256 _stethShares, uint256 _maxStvToBurn)
        external
        returns (uint256 stvBurned);
    function transferFromWithLiabilityForWithdrawalQueue(address _from, uint256 _stv, uint256 _stethShares) external;
}
