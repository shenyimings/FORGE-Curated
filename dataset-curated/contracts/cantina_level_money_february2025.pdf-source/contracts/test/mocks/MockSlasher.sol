// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.19;

import {lvlUSD} from "../../src/lvlUSD.sol";

contract MockSlasher {
    constructor() {}

    function burn(uint256 _amount, lvlUSD _lvlUSD) public {
        _lvlUSD.burn(_amount);
    }
    // add this to be excluded from coverage report
    function test() public {}
}
