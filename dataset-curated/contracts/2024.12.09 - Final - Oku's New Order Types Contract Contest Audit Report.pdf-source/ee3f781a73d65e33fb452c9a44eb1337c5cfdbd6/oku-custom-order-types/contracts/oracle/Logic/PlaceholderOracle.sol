// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../IOracleRelay.sol";

///NOTE DO NOT DEPLOY, TESTING ONLY
/// @title Testing Oracle
contract PlaceholderOracle is IOracleRelay {
    uint256 private currentPrice;
    address public immutable underlying;
    
    constructor(address _underlying) {
        underlying = _underlying;
    }

    function currentValue() external view override returns (uint256) {
        return currentPrice;
    }

    function setPrice(uint256 newPrice) external {
        currentPrice = newPrice;
    }
}
