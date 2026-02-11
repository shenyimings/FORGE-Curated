// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IRocketPoolRETH {
    function getExchangeRate() external view returns (uint256);
}
