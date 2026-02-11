// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IFeeCollector {
    function tradingFeeRate() external view returns (uint256);
    function settlementFeeRate() external view returns (uint256);
}
