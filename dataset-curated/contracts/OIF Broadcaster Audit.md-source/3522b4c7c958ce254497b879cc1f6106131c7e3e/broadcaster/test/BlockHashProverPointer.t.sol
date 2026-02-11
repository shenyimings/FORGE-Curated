// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {BlockHashProverPointer} from "../src/contracts/BlockHashProverPointer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockProver} from "./mocks/MockProver.sol";

contract BlockHashProverPointerTest is Test {
    BlockHashProverPointer public blockHashProverPointer;
    MockProver public mockProver;
    address public owner = makeAddr("owner");

    function setUp() public {
        blockHashProverPointer = new BlockHashProverPointer(owner);
        mockProver = new MockProver();
    }

    function test_checkOwner() public view {
        assertEq(blockHashProverPointer.owner(), owner);
    }

    function test_setImplementationAddress() public {
        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(mockProver));
        assertEq(blockHashProverPointer.implementationAddress(), address(mockProver));
        assertEq(blockHashProverPointer.implementationCodeHash(), address(mockProver).codehash);
    }

    function test_setImplementationAddress_reverts_if_not_owner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, makeAddr("notOwner")));
        blockHashProverPointer.setImplementationAddress(address(mockProver));
    }

    function test_setImplementationAddress_reverts_if_version_is_not_increasing() public {
        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(mockProver));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(BlockHashProverPointer.NonIncreasingVersion.selector, 1, 1));
        blockHashProverPointer.setImplementationAddress(address(mockProver));
    }
}

