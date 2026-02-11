// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {BitOps} from "../src/BitOps.sol";

contract BitOpsTest is Test {
    function testClzZero() pure public {
        uint256 result = BitOps.clz(0);
        assertEq(result, 256, "CLZ of 0 should be 256");
    }

    function testClzOne() pure public {
        uint256 result = BitOps.clz(1);
        assertEq(result, 255, "CLZ of 1 should be 255");
    }

    function testClzMaxUint256() pure public {
        uint256 result = BitOps.clz(type(uint256).max);
        assertEq(result, 0, "CLZ of max uint256 should be 0");
    }

    function testClzPowersOfTwo() pure public {
        for (uint16 i = 0; i < 256; i++) {
            uint256 input = 1 << i;
            uint256 result = BitOps.clz(input);
            assertEq(result, 255 - i, string(abi.encodePacked("CLZ of 2^", vm.toString(i), " should be ", vm.toString(255 - i))));
        }
    }

    function testClzSelectValues() pure public {
        assertEq(BitOps.clz(0x000F), 252, "CLZ of 0x000F should be 252");
        assertEq(BitOps.clz(0x00FF), 248, "CLZ of 0x00FF should be 248");
        assertEq(BitOps.clz(0x0100), 247, "CLZ of 0x0100 should be 247");
        assertEq(BitOps.clz(0xFFFF), 240, "CLZ of 0xFFFF should be 240");
        assertEq(BitOps.clz(0x8000), 240, "CLZ of 0x8000 should be 240");
        assertEq(BitOps.clz(0x80000000), 56*4, "CLZ of 0x80000000 should be 56*4");
        assertEq(BitOps.clz(0x8FFFFFFF), 56*4, "CLZ of 0x8FFFFFFF should be 56*4");
        assertEq(BitOps.clz(0x8000000000000000), 48*4, "CLZ of 0x8000000000000000 should be 48*4");
    }

    function testCtzZero() pure public {
        uint256 result = BitOps.ctz(0);
        assertEq(result, 256, "CTZ of 0 should be 256");
    }

    function testCtz1LShift255() pure public {
        uint256 result = BitOps.ctz(1<<254);
        assertEq(result, 254, "CTZ of 2^254 should be 254");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testCtzInputExceedsMaxInt256() public {
        // Setup
        uint256 maxInt256 = uint256(type(int256).max);
        uint256 exceedingValue = maxInt256 + 1;

        // Expect the call to revert
        vm.expectRevert("Input exceeds maximum int256 value");
        
        // Call ctz with a value exceeding max int256
        BitOps.ctz(exceedingValue);
    }

    function testCtzSelectValues() pure public {
        assertEq(BitOps.ctz(0x000F), 0, "CTZ of 0x000F should be 0");
        assertEq(BitOps.ctz(0xFF00), 8, "CTZ of 0xFF00 should be 2");
        assertEq(BitOps.ctz(0x8000), 15, "CTZ of 0x8000 should be 15");
        assertEq(BitOps.ctz(0x80000000), 31, "CLZ of 0x80000000 should be 56*4");
    }


}
