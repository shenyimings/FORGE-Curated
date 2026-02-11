// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

contract ImplementationMock {
    
    uint256 public foo;
    constructor() {}

    function bar() external {
        foo++;
    }
}