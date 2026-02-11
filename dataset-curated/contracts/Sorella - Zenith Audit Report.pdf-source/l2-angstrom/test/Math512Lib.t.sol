// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Math512Lib} from "src/libraries/Math512Lib.sol";

contract Math512LibTest is Test {
    function test_fuzzing_ffi_div512by256(uint256 x1, uint256 x0, uint256 d) public {
        d = bound(d, 1, type(uint256).max);
        (uint256 y1, uint256 y0) = pythonDiv512by256(x1, x0, d);
        (uint256 z1, uint256 z0) = Math512Lib.div512by256(x1, x0, d);
        assertEq(y1, z1, "y1 != z1");
        assertEq(y0, z0, "y0 != z0");
    }

    function test_fuzzing_ffi_sqrt512(uint256 x1, uint256 x0) public {
        uint256 root = Math512Lib.sqrt512(x1, x0);
        assertEq(pythonSqrt512(x1, x0), root);
    }

    function pythonDiv512by256(uint256 x1, uint256 x0, uint256 d)
        internal
        returns (uint256 y1, uint256 y0)
    {
        uint256[] memory args = new uint256[](3);
        args[0] = x1;
        args[1] = x0;
        args[2] = d;
        uint256[] memory result = ffiPython("div512by256", args);
        require(result.length == 2, "Python div512by256 Length Error");
        return (result[0], result[1]);
    }

    function pythonSqrt512(uint256 x1, uint256 x0) internal returns (uint256 root) {
        uint256[] memory args = new uint256[](2);
        args[0] = x1;
        args[1] = x0;
        uint256[] memory result = ffiPython("sqrt512", args);
        require(result.length == 1, "Python sqrt512 Length Error");
        return result[0];
    }

    function ffiPython(string memory func, uint256[] memory args)
        internal
        returns (uint256[] memory result)
    {
        string[] memory inputs = new string[](3 + args.length);
        inputs[0] = "python3";
        inputs[1] = "script/math512.py";
        inputs[2] = func;
        for (uint256 i = 0; i < args.length; i++) {
            inputs[3 + i] = vm.toString(args[i]);
        }

        bytes memory pythonResultBytes = vm.ffi(inputs);
        bytes1 firstByte = pythonResultBytes[0];
        require(firstByte == 0x00, "Python Error");
        require(pythonResultBytes.length % 32 == 1, "Python Result Length Error");

        assembly ("memory-safe") {
            result := mload(0x40)
            mstore(result, shr(5, mload(pythonResultBytes)))
            mcopy(add(result, 0x20), add(pythonResultBytes, 0x21), sub(mload(pythonResultBytes), 1))
            mstore(0x40, add(result, sub(mload(pythonResultBytes), 1)))
        }
    }
}
