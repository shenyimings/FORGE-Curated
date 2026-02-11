// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { Bytes32AddressLib } from "../../../src/utils/Bytes32AddressLib.sol";

contract Bytes32AddressLibTest is Test {
    function test_roundTripFixedAddress() external {
        address original = makeAddr("roundtrip");

        bytes32 encoded = Bytes32AddressLib.toBytes32WithLowAddress(original);
        address decoded = Bytes32AddressLib.toAddressFromLowBytes(encoded);

        assertEq(decoded, original, "round-trip should return the original address");
    }

    function testFuzz_roundTrip(address original) external pure {
        bytes32 encoded = Bytes32AddressLib.toBytes32WithLowAddress(original);
        address decoded = Bytes32AddressLib.toAddressFromLowBytes(encoded);

        assertEq(decoded, original, "fuzzed round-trip should return the original address");
    }
}
