// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|                            
*/

abstract contract Constants {
    // ----------- GENERIC ------------
    uint256 public constant SMALL = 10 ether;
    uint256 public constant MEDIUM = 100 ether;
    uint256 public constant LARGE = 1000 ether;

    uint256 public constant ALICE_KEY = 0x1;
    uint256 public constant BOB_KEY = 0x2;
    uint256 public constant FOO_KEY = 0x3;

    address public constant ZERO_ADDRESS = address(0);
    uint256 public constant ZERO_VALUE = 0;

    uint256 public constant DEFAULT_ORACLE_PRICE = 1e18;
    uint256 public constant DEFAULT_ORACLE_PRICE36 = 1e36;
    uint256 public constant DEFAULT_LIQUIDATOR_ORACLE_PRICE = 8e17;
    uint256 public constant DEFAULT_COLLATERAL_FACTOR = 9e17; //90%
    uint256 public constant DEFAULT_INFLATION_INCREASE = 1000; //90%

    uint32 public constant LINEA_CHAIN_ID = 59144;
}
