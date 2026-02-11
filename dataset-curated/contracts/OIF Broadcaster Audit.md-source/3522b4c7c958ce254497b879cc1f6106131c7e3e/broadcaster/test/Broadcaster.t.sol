// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Broadcaster} from "../src/contracts/Broadcaster.sol";
import {IBroadcaster} from "../src/contracts/interfaces/IBroadcaster.sol";

contract BroadcasterTest is Test {
    Broadcaster public broadcaster;

    address public publisher = makeAddr("publisher");

    function setUp() public {
        broadcaster = new Broadcaster();
    }

    function test_broadcast() public {
        bytes32 message = "test";

        vm.prank(publisher);
        vm.expectEmit();
        emit IBroadcaster.MessageBroadcast(message, publisher);
        broadcaster.broadcastMessage(message);

        assertEq(broadcaster.hasBroadcasted(message, publisher), true);
    }
}
