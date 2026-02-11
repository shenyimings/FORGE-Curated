// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface ICoinbaseCBETH {
    function exchangeRate() external view returns (uint256);
}
