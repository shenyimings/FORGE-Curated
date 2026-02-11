// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IRateProvider {
    function getRate() external view returns (uint256 _rate);
}
