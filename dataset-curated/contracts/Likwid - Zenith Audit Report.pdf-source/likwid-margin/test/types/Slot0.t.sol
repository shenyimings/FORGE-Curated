// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Forge
import {Test} from "forge-std/Test.sol";
// Likwid Contracts
import {Slot0} from "../../src/types/Slot0.sol";

contract Slot0Test is Test {
    Slot0 private slot0;

    function setUp() public {
        slot0 = Slot0.wrap(0);
    }

    function testSetAndGetTotalSupply() public {
        uint128 totalSupply = 100 ether;
        slot0 = slot0.setTotalSupply(totalSupply);
        assertEq(slot0.totalSupply(), totalSupply);
    }

    function testSetAndGetLastUpdated() public {
        uint32 lastUpdated = 1711123225;
        slot0 = slot0.setLastUpdated(lastUpdated);
        assertEq(slot0.lastUpdated(), lastUpdated);
    }

    function testSetAndGetLpFee() public {
        uint24 lpFee = 3000; // 0.3%
        slot0 = slot0.setLpFee(lpFee);
        assertEq(slot0.lpFee(), lpFee);
    }

    function testSetAndGetProtocolFee() public {
        uint24 protocolFee = 1500; // 0.15%
        slot0 = slot0.setProtocolFee(protocolFee);
        assertEq(slot0.protocolFee(0), protocolFee);
    }

    function testSetAndGetMarginFee() public {
        uint24 marginFee = 15000; // 1.5%
        slot0 = slot0.setMarginFee(marginFee);
        assertEq(slot0.marginFee(), marginFee);
    }
}
