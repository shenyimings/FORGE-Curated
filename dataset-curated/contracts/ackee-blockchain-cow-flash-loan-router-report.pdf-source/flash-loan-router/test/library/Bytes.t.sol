// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {Bytes} from "src/library/Bytes.sol";

/// @dev We use a separate contract for encoding and decoding instead of
/// direcly using the library in the test to avoid corrupting memory in the
/// execution of the test itself.
contract Allocator {
    using Bytes for bytes;

    function allocate(uint256 length) external pure returns (bytes memory) {
        return Bytes.allocate(length);
    }

    function allocateWithDirtyMemory(uint256 length) external pure returns (bytes memory) {
        assembly ("memory-safe") {
            let freeMemoryPointer := mload(0x40)
            mstore(freeMemoryPointer, 0x1111111111111111111111111111111111111111111111111111111111111111)
            mstore(add(freeMemoryPointer, 32), 0x2222222222222222222222222222222222222222222222222222222222222222)
        }
        return Bytes.allocate(length);
    }
}

contract BytesTest is Test {
    using Bytes for bytes;

    Allocator private allocator;

    function setUp() external {
        allocator = new Allocator();
    }

    function testFuzz_allocatedArrayHasExpectedLength(uint24 length) external view {
        // This is exactly the maximum length before allocating reverts with
        // `MemoryOOG` error.
        uint256 maxAllocationBeforeMemoryOOGError = 8366830;
        vm.assume(length <= maxAllocationBeforeMemoryOOGError);
        assertEq(allocator.allocate(length).length, length);
    }

    function testFuzz_allocatedArrayHasExpectedLengthDespiteDirtyMemory(uint24 length) external view {
        // This is exactly the maximum length before allocating reverts with
        // `MemoryOOG` error.
        uint256 maxAllocationBeforeMemoryOOGError = 8366830;
        vm.assume(length <= maxAllocationBeforeMemoryOOGError);
        assertEq(allocator.allocateWithDirtyMemory(length).length, length);
    }

    function test_pointsToMemoryContent() external pure {
        bytes memory array = hex"3133333333333333333333333333333333333333333333333333333333333333333333333333333337";
        uint256 content;
        uint256 pointer = array.memoryPointerToContent();
        assembly ("memory-safe") {
            content := mload(pointer)
        }
        assertEq(content, 0x3133333333333333333333333333333333333333333333333333333333333333);
    }
}
