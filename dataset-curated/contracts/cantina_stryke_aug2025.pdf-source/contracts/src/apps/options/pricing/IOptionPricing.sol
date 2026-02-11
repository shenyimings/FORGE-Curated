// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IOptionPricing {
    function getOptionPrice(bool isPut, uint256 expiry, uint256 strike, uint256 lastPrice, uint256 baseIv)
        external
        view
        returns (uint256);
}
