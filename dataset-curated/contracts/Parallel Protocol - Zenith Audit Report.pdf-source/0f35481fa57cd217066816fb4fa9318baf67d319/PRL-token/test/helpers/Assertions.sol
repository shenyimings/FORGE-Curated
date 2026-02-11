// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from "@forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract Assertions is Test {
    //----------------------------------------
    // Events
    //----------------------------------------

    event Log(string err);
    event LogNamedUint64(string key, uint64 value);
    event LogNamedUint8(string key, uint8 value);
    event LogNamedInt256(string key, int256 value);
    event LogNamedString(string key, string value);

    //----------------------------------------
    // Assertions
    //----------------------------------------

    /// @dev Compares two {IERC20} values.
    function assertEq(IERC20 a, IERC20 b) internal pure {
        assertEq(address(a), address(b));
    }

    /// @dev Compares two `uint64` numbers.
    function assertEqUint64(uint64 a, uint64 b) internal {
        if (a != b) {
            emit Log("Error: a == b not satisfied [uint64]");
            emit LogNamedUint64("   Left", b);
            emit LogNamedUint64("  Right", a);
            fail();
        }
    }

    /// @dev Compares two `uint64` numbers.
    function assertEqUint64(uint64 a, uint64 b, string memory err) internal {
        if (a != b) {
            emit LogNamedString("Error", err);
            assertEqUint64(a, b);
        }
    }
    /// @dev Compares two `uint8` numbers.

    function assertEqUint8(uint8 a, uint8 b) internal {
        if (a != b) {
            emit Log("Error: a == b not satisfied [uint8]");
            emit LogNamedUint8("   Left", b);
            emit LogNamedUint8("  Right", a);
            fail();
        }
    }

    /// @dev Compares two `uint8` numbers.
    function assertEqUint8(uint8 a, uint8 b, string memory err) internal {
        if (a != b) {
            emit LogNamedString("Error", err);
            assertEqUint8(a, b);
        }
    }
}
