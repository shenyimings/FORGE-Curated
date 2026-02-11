// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

contract Counter {
    uint256 public number;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }
}
