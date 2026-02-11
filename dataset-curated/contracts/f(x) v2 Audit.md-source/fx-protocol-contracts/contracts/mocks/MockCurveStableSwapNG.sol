// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

contract MockCurveStableSwapNG {
    mapping(uint256 => address) public coins;

    mapping(uint256 => uint256) public price_oracle;

    function setCoin(uint256 index, address token) external {
        coins[index] = token;
    }

    function setPriceOracle(uint256 index, uint256 value) external {
        price_oracle[index] = value;
    }
}