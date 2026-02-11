// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {BytesLib} from "src/libraries/BytesLib.sol";

contract BytesLibTest is Test {
    // Can't import errors from libraries, so we redefine the error here
    error InvalidOffset(uint256 offset);

    /// forge-config: default.allow_internal_expect_revert = true
    function testFuzz_get_RevertIf_InvalidOffset(bytes memory data, uint256 offset) public {
        vm.assume(data.length >= 32);
        vm.assume(offset > data.length - 32);
        vm.expectRevert(abi.encodeWithSelector(InvalidOffset.selector, offset));
        BytesLib.get(data, offset);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testFuzz_set_RevertIf_InvalidOffset(bytes memory data, uint256 offset) public {
        vm.assume(data.length >= 32);
        vm.assume(offset > data.length - 32);
        vm.expectRevert(abi.encodeWithSelector(InvalidOffset.selector, offset));
        BytesLib.set(data, offset, 0);
    }

    function testFuzz_get_ValidOffset(uint256 length, uint256 offset, uint256 value) public pure {
        length = bound(length, 32, type(uint16).max);
        offset = bound(offset, 0, length - 32);
        bytes memory data = bytes.concat(new bytes(offset), bytes32(value), new bytes(length - offset - 32));
        uint256 retrievedValue = BytesLib.get(data, offset);
        assertEq(value, retrievedValue);
    }

    function testFuzz_set_ValidOffset(uint256 length, uint256 offset, uint256 value) public pure {
        length = bound(length, 32, type(uint16).max);
        offset = bound(offset, 0, length - 32);
        bytes memory expectedBytes = bytes.concat(new bytes(offset), bytes32(value), new bytes(length - offset - 32));
        bytes memory actualBytes = new bytes(length);
        BytesLib.set(actualBytes, offset, value);
        assertEq(expectedBytes, actualBytes);
    }
}
