// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {ICowSettlement} from "src/interface/ICowSettlement.sol";

contract ICowSettlementTest is Test {
    function test_settleSelectorMatches() external pure {
        // The selector bytes can be extracted from any settlement transaction.
        // For example:
        // https://etherscan.io/tx/0xecf9c7f1492652f0a4e66c744e9f6111500d6fdc3c6d6fa1c6d01d7ec2f37119
        assertEq(ICowSettlement.settle.selector, bytes4(hex"13d79a0b"));
    }
}
