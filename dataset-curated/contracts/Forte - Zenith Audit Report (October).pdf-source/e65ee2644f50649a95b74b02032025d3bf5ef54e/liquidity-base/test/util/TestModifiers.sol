// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {TestCommon} from "test/util/TestCommon.sol";

/**
 * @title End With Stop Prank
 * @author @ShaneDuncan602 @oscarsernarosero @TJ-Everett @mpetersoCode55
 * @dev encapsulates the modifier used in the whole test directory to end a test function
 * with a stopPrank command.
 */
abstract contract TestModifiers is TestCommon {
    modifier endWithStopPrank() {
        _;
        vm.stopPrank();
    }

    modifier startAsAdmin() {
        vm.startPrank(admin);
        _;
    }
}
