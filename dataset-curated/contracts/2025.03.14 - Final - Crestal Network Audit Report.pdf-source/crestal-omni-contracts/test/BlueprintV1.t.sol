// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BlueprintV1} from "../src/BlueprintV1.sol";

contract BlueprintTest is Test {
    BlueprintV1 public blueprint;

    function setUp() public {
        blueprint = new BlueprintV1();
        blueprint.initialize(); // mimic upgradeable contract deploy behavior
    }

    // TODO: This is just an example of how to write Solidity-native tests
    // Fill in more tests later!
    function test_ProjectID() public {
        bytes32 pid = blueprint.createProjectID();
        bytes32 projId = blueprint.getLatestUserProjectID(address(this));
        assertEq(pid, projId);
    }

    function test_VERSION() public view {
        string memory ver = blueprint.VERSION();
        assertEq(ver, "1.0.0");
    }
}
