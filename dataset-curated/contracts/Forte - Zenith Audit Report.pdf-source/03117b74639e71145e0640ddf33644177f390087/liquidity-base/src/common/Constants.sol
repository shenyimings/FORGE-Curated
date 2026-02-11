// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/**
 * @title Common Constants
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract Constants {
    uint256 public constant POOL_NATIVE_DECIMALS = 18;
    uint256 public constant FULL_NATIVE_TOKEN = 10 ** POOL_NATIVE_DECIMALS;
    string public constant VERSION = "v0.2.0";
    uint256 public constant TOTAL_SUPPLY_LIMIT = 100_000_000_000 * FULL_NATIVE_TOKEN;
    uint16 public constant MIN_PRICE_LIMIT_FACTOR = 1_000;
    uint24 public constant MAX_PRICE_LIMIT_FACTOR = 100_000;
    uint16 public constant MAX_PROTOCOL_FEE = 20;
    uint256 public constant PERCENTAGE_DENOM = 10_000;
    uint16 public constant MAX_LP_FEE = 5_000 - MAX_PROTOCOL_FEE;
    uint256 public constant PLOWER_MIN = 1_000;
    
}
