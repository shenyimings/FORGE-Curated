// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Cids} from "../src/Cids.sol";

contract CidsTest is Test {
    function testDigestRoundTrip() pure public {
        bytes memory prefix = "prefix";
        bytes32 digest = 0xbeadcafefacedeedfeedbabedeadbeefbeadcafefacedeedfeedbabedeadbeef;
        Cids.Cid memory c = Cids.cidFromDigest(prefix, digest);
        assertEq(c.data.length, 6 + 32);
        bytes32 foundDigest = Cids.digestFromCid(c);
        assertEq(foundDigest, digest);
    }
}
