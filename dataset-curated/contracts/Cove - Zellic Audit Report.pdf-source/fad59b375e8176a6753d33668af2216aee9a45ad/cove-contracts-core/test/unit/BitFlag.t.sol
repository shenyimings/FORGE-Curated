// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { BaseTest } from "test/utils/BaseTest.t.sol";

import { BitFlag } from "src/libraries/BitFlag.sol";

contract BitFlagTest is BaseTest {
    function testFuzz_popCount(uint256 bitFlag) public {
        uint256 manualCount = countBitsManually(bitFlag);
        uint256 libraryCount = BitFlag.popCount(bitFlag);

        assertEq(manualCount, libraryCount, "Manual count should match library count");
    }

    function test_popCount_AllOnes() public {
        uint256 allOnes = type(uint256).max;
        uint256 manualCount = countBitsManually(allOnes);
        uint256 libraryCount = BitFlag.popCount(allOnes);

        assertEq(manualCount, 256, "Manual count for all ones should be 256");
        assertEq(libraryCount, 256, "Library count for all ones should be 256");
    }

    function test_popCount_AllZeros() public {
        uint256 allZeros = 0;
        uint256 manualCount = countBitsManually(allZeros);
        uint256 libraryCount = BitFlag.popCount(allZeros);

        assertEq(manualCount, 0, "Manual count for all zeros should be 0");
        assertEq(libraryCount, 0, "Library count for all zeros should be 0");
    }

    function countBitsManually(uint256 n) internal pure returns (uint256) {
        uint256 count = 0;
        while (n != 0) {
            count += n & 1;
            n >>= 1;
        }
        return count;
    }
}
