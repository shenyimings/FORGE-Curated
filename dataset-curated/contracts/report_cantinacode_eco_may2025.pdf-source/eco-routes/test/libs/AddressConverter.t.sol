// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BaseTest} from "../BaseTest.sol";
import {AddressConverter} from "../../contracts/libs/AddressConverter.sol";

contract AddressConverterTest is BaseTest {
    using AddressConverter for address;
    using AddressConverter for bytes32;

    function setUp() public override {
        super.setUp();
    }

    function testAddressToBytes32() public {
        address testAddr = makeAddr("test");
        bytes32 converted = testAddr.toBytes32();

        // Should be padded with zeros on the left
        bytes32 expected = bytes32(uint256(uint160(testAddr)));
        assertEq(converted, expected);
    }

    function testBytes32ToAddress() public {
        bytes32 testBytes = bytes32(uint256(uint160(makeAddr("test"))));
        address converted = testBytes.toAddress();

        // Should extract the rightmost 20 bytes
        address expected = address(uint160(uint256(testBytes)));
        assertEq(converted, expected);
    }

    function testAddressToBytes32ToAddress() public {
        address original = makeAddr("original");
        bytes32 converted = original.toBytes32();
        address reverted = converted.toAddress();

        assertEq(original, reverted);
    }

    function testBytes32ToAddressToBytes32() public {
        bytes32 original = bytes32(uint256(uint160(makeAddr("original"))));
        address converted = original.toAddress();
        bytes32 reverted = converted.toBytes32();

        assertEq(original, reverted);
    }

    function testZeroAddressConversion() public pure {
        address zero = address(0);
        bytes32 converted = zero.toBytes32();
        address reverted = converted.toAddress();

        assertEq(zero, reverted);
        assertEq(converted, bytes32(0));
    }

    function testMaxAddressConversion() public pure {
        address maxAddr = address(type(uint160).max);
        bytes32 converted = maxAddr.toBytes32();
        address reverted = converted.toAddress();

        assertEq(maxAddr, reverted);
    }

    function testBytes32WithNonZeroLeadingBytes() public {
        bytes32 testBytes = 0x1234567890123456789012345678901234567890123456789012345678901234;

        // Should revert with InvalidAddress error since top 12 bytes are not zero
        vm.expectRevert(
            abi.encodeWithSelector(
                AddressConverter.InvalidAddress.selector,
                testBytes
            )
        );
        testBytes.toAddress();
    }

    function testConversionPreservesData() public {
        address[] memory testAddresses = new address[](5);
        testAddresses[0] = address(0);
        testAddresses[1] = address(1);
        testAddresses[2] = address(type(uint160).max);
        testAddresses[3] = makeAddr("test1");
        testAddresses[4] = makeAddr("test2");

        for (uint256 i = 0; i < testAddresses.length; i++) {
            bytes32 converted = testAddresses[i].toBytes32();
            address reverted = converted.toAddress();
            assertEq(testAddresses[i], reverted);
        }
    }

    function testConversionGasUsage() public {
        address testAddr = makeAddr("gasTest");

        uint256 gasBefore = gasleft();
        bytes32 converted = testAddr.toBytes32();
        uint256 gasAfter = gasleft();

        uint256 gasUsed = gasBefore - gasAfter;

        // Should be very efficient
        assertLt(gasUsed, 100);

        gasBefore = gasleft();
        converted.toAddress();
        gasAfter = gasleft();

        gasUsed = gasBefore - gasAfter;
        assertLt(gasUsed, 100);
    }

    function testConversionImmutability() public {
        address testAddr = makeAddr("immutable");
        bytes32 converted1 = testAddr.toBytes32();
        bytes32 converted2 = testAddr.toBytes32();

        // Should always produce the same result
        assertEq(converted1, converted2);

        address reverted1 = converted1.toAddress();
        address reverted2 = converted2.toAddress();

        assertEq(reverted1, reverted2);
        assertEq(testAddr, reverted1);
    }

    function testConversionWithBytes32Max() public {
        bytes32 maxBytes = bytes32(type(uint256).max);

        // Should revert with InvalidAddress error since top 12 bytes are not zero
        vm.expectRevert(
            abi.encodeWithSelector(
                AddressConverter.InvalidAddress.selector,
                maxBytes
            )
        );
        maxBytes.toAddress();
    }

    function testConversionDoesNotOverflow() public {
        bytes32 largeBytes = bytes32(type(uint256).max);

        // Should revert with InvalidAddress error since top 12 bytes are not zero
        vm.expectRevert(
            abi.encodeWithSelector(
                AddressConverter.InvalidAddress.selector,
                largeBytes
            )
        );
        largeBytes.toAddress();
    }
}
