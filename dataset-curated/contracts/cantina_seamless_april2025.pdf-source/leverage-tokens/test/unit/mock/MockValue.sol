// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

contract MockValue {
    uint256 public value;

    bool public initialized;

    error Initialized();

    function initialize(uint256 _value) public {
        if (initialized) revert Initialized();
        value = _value;
        initialized = true;
    }

    function mockFunction() public view returns (uint256) {
        return value;
    }
}
