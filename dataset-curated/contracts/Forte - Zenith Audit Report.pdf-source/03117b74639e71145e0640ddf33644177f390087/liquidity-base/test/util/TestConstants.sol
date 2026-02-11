// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

enum TBCInputOption { BASE, FORK, PRECISION }

/**
 * @title Test Constants
 */
abstract contract TestConstants {
    uint256 MAX_SQUAREABLE = 340_282_366_920_938_463_463_374607431768211455;
    uint256 constant STABLECOIN_DEC = 1e6;
    uint256 constant ERC20_DECIMALS = 1e18;
    uint256 constant X_TOKEN_MAX_SUPPLY = 100_000_000_000 * ERC20_DECIMALS;
    
}