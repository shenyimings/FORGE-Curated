// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {BytesLib, Path} from "src/libraries/Path.sol";

contract PathTest is Test {
    using Path for bytes;

    function test_toBytes() public {
        address testAddr = makeAddr("test");
        bytes memory testAddrBytes = BytesLib.toBytes(testAddr);

        assertEq(testAddr, BytesLib.toAddress(testAddrBytes, 0), "Address to bytes lib");
        assertEq(testAddr, address(uint160(bytes20(testAddrBytes))), "Address to bytes typecast");
    }

    function test_decodeFirstPool() public {
        address token1 = makeAddr("TOKEN 1");
        address token2 = makeAddr("TOKEN 2");
        address token3 = makeAddr("TOKEN 3");

        bytes memory testPath = abi.encodePacked(token1, uint24(100), token2, uint24(3000), token3);

        (address tokenA, address tokenB, uint24 fee) = testPath.decodeFirstPool();

        assertEq(tokenA, token1, "Token A not properly decoded");
        assertEq(tokenB, token2, "Token B not properly decoded");
        assertEq(uint24(100), fee, "fee not properly decoded");
    }

    function test_fuzz_decodeLastPool(uint256 poolNum) public {
        poolNum = bound(poolNum, 1, 20);

        address token = makeAddr("TOKEN 0");
        address newToken;
        bytes memory path;
        for (uint256 i = 1; i <= poolNum; ++i) {
            token = newToken;
            newToken = makeAddr(string.concat("TOKEN ", vm.toString(i)));
            bytes memory newPath = abi.encodePacked(token, uint24(100), newToken);
            path = BytesLib.concat(path, newPath);
        }

        (address tokenA, address tokenB, uint24 fee) = path.decodeLastPool();

        assertEq(tokenA, token, "Token A not properly decoded");
        assertEq(tokenB, newToken, "Token B not properly decoded");
        assertEq(uint24(100), fee, "fee not properly decoded");
    }

    function test_decodeLastPool() public {
        address token1 = makeAddr("TOKEN 1");
        address token2 = makeAddr("TOKEN 2");
        address token3 = makeAddr("TOKEN 3");

        bytes memory testPath = abi.encodePacked(token1, uint24(100), token2, uint24(3000), token3);

        (address tokenA, address tokenB, uint24 fee) = testPath.decodeLastPool();

        assertEq(tokenA, token2, "Token A not properly decoded");
        assertEq(tokenB, token3, "Token B not properly decoded");
        assertEq(uint24(3000), fee, "fee not properly decoded");
    }

    function test_replaceFirstToken() public {
        address token1 = makeAddr("TOKEN 1");
        address token2 = makeAddr("TOKEN 2");
        address token3 = makeAddr("TOKEN 3");
        address replacementToken = makeAddr("TOKEN REPLACED");

        bytes memory testPath = abi.encodePacked(token1, uint24(100), token2, uint24(3000), token3);

        bytes memory replacementBytes = BytesLib.toBytes(replacementToken);
        testPath = BytesLib.concat(replacementBytes, BytesLib.slice(testPath, 20, testPath.length - 20));

        (address tokenA, address tokenB, uint24 fee) = testPath.decodeFirstPool();

        assertEq(tokenA, replacementToken, "Decode Replaced Token");
        assertEq(tokenB, token2, "Decode Token B");
        assertEq(fee, uint24(100), "Decode Fee");
    }

    function test_replaceLastToken() public {
        address token1 = makeAddr("TOKEN 1");
        address token2 = makeAddr("TOKEN 2");
        address token3 = makeAddr("TOKEN 3");
        address replacementToken = makeAddr("TOKEN REPLACED");

        bytes memory testPath = abi.encodePacked(token1, uint24(100), token2, uint24(3000), token3);

        bytes memory replacementBytes = BytesLib.toBytes(replacementToken);
        testPath = BytesLib.concat(BytesLib.slice(testPath, 0, testPath.length - 20), replacementBytes);

        (address tokenA, address tokenB, uint24 fee) = testPath.decodeLastPool();

        assertEq(tokenA, token2, "Decode Token A");
        assertEq(tokenB, replacementToken, "Decode Replaced Token");
        assertEq(fee, uint24(3000), "Decode Fee");
    }
}
