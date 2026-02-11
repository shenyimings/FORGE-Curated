// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title Common Constants
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract Constants {
    uint256 constant POOL_NATIVE_DECIMALS = 18;
    uint256 constant FULL_NATIVE_TOKEN = 10 ** POOL_NATIVE_DECIMALS;
    uint256 constant PERCENTAGE_DENOM = 10_000;
    uint16 constant MAX_PROTOCOL_FEE = 20;
    uint16 constant MAX_LP_FEE = 5_000 - MAX_PROTOCOL_FEE;

    function getPoolConstants() public pure returns (uint, uint, uint, uint16, uint16) {
        return (POOL_NATIVE_DECIMALS, FULL_NATIVE_TOKEN, PERCENTAGE_DENOM, MAX_PROTOCOL_FEE, MAX_LP_FEE);
    }
}
