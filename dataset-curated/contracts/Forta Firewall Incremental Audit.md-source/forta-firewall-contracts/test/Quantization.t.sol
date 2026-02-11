// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console, Vm} from "forge-std/Test.sol";
import {Quantization} from "../src/Quantization.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract QuantizationTest is Test {
    function testQuantize() public view {
        /// 0x000000000000000000000000000000000000000000000000000000000148bd9b
        uint256 num1 = 21544347;
        console.logBytes32(bytes32(num1));
        uint256 num1q = Quantization.quantize(num1);
        console.logBytes32(bytes32(num1q));
        assertEq(0x0000000000000000000000000000000000000000000000000000000001ffffff, num1q);

        /// 0x0000000000000000000000000000000000000000000000000000000000989680
        uint256 num2 = 10000000;
        console.logBytes32(bytes32(num2));
        uint256 num2q = Quantization.quantize(num2);
        console.logBytes32(bytes32(num2q));
        assertEq(0x000000000000000000000000000000000000000000000000000000000098ffff, num2q);
    }
}
