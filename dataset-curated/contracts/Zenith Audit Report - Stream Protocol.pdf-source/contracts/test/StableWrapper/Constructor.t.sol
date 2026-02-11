// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Base} from "./Base.t.sol";

/************************************************
 *  CONSTRUCTOR TESTS
 ***********************************************/
contract StableWrapperConstructorTest is Base {
    function test_initializesCorrectly() public {
        assertEq(stableWrapper.name(), "Wrapped USD Coin");
        assertEq(stableWrapper.symbol(), "wUSDC");
        assertEq(stableWrapper.decimals(), 6);
        assertEq(stableWrapper.totalSupply(), 0);
        assertEq(address(stableWrapper.endpoint()), address(endpoints[1]));
        assertEq(stableWrapper.owner(), owner);
        assertEpoch(1);
    }
}
