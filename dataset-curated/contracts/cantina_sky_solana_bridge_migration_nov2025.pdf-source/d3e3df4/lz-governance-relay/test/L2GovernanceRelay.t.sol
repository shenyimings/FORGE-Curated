// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2025 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.22;

import "dss-test/DssTest.sol";

import { L2GovernanceRelay } from "src/L2GovernanceRelay.sol";
import { GovernanceRelayDeploy } from "deploy/GovernanceRelayDeploy.sol";
import { OappReceiverMock } from "test/mocks/OappReceiverMock.sol";

contract L2SpellMock {
    function exec() external {}
    function revt() pure external { revert("L2SpellMock/revt"); }
}

contract L2GovernanceRelayTest is DssTest {
    L2GovernanceRelay relay;
    address l1GovernanceRelay = address(0x111);
    address l2Oapp;
    address spell;

    function setUp() public {
        l2Oapp = address(new OappReceiverMock());
        spell = address(new L2SpellMock());
        relay = L2GovernanceRelay(GovernanceRelayDeploy.deployL2(1, l2Oapp, l1GovernanceRelay));
    }

    function testConstructor() public {
        L2GovernanceRelay r = new L2GovernanceRelay(123, address(0x1), address(0x2));
        assertEq(r.l1Eid(), 123);
        assertEq(address(r.l2Oapp()), address(0x1));
        assertEq(r.l1GovernanceRelay(), address(0x2));
    }

    function testFile() public {
        vm.expectRevert("L2GovernanceRelay/sender-not-this");
        relay.file("l2Oapp", address(0x1));
        vm.expectEmit(true, true, true, true);
        emit File("l2Oapp", address(0x1));
        vm.prank(address(relay)); relay.file("l2Oapp", address(0x1));
        assertEq(address(relay.l2Oapp()), address(0x1));

        vm.expectRevert("L2GovernanceRelay/sender-not-this");
        relay.file("l1GovernanceRelay", address(0x2));
        vm.expectEmit(true, true, true, true);
        emit File("l1GovernanceRelay", address(0x2));
        vm.prank(address(relay)); relay.file("l1GovernanceRelay", address(0x2));
        assertEq(relay.l1GovernanceRelay(), address(0x2));

        vm.expectRevert("L2GovernanceRelay/file-unrecognized-param");
        vm.prank(address(relay)); relay.file("bad", address(0x1));
    }

    function testRelay() public {
        OappReceiverMock(l2Oapp).setMessageOrigin(1, bytes32(uint256(uint160(l1GovernanceRelay))));

        vm.prank(l2Oapp); relay.relay(spell, abi.encodeCall(L2SpellMock.exec, ()));
    }

    function testRelayNotFromL2Oapp() public {
        OappReceiverMock(l2Oapp).setMessageOrigin(1, bytes32(uint256(uint160(l1GovernanceRelay))));

        vm.expectRevert("L2GovernanceRelay/bad-message-auth");
        relay.relay(spell, abi.encodeCall(L2SpellMock.exec, ()));
    }

    function testRelayNotFromEid() public {
        OappReceiverMock(l2Oapp).setMessageOrigin(2, bytes32(uint256(uint160(l1GovernanceRelay))));

        vm.expectRevert("L2GovernanceRelay/bad-message-auth");
        vm.prank(l2Oapp); relay.relay(spell, abi.encodeCall(L2SpellMock.exec, ()));
    }

    function testRelayNotFromL1GovRelay() public {
        OappReceiverMock(l2Oapp).setMessageOrigin(1, bytes32(uint256(uint160(address(0)))));

        vm.expectRevert("L2GovernanceRelay/bad-message-auth");
        vm.prank(l2Oapp); relay.relay(spell, abi.encodeCall(L2SpellMock.exec, ()));
    }

    function testRelayDelegateCallError() public {
        OappReceiverMock(l2Oapp).setMessageOrigin(1, bytes32(uint256(uint160(l1GovernanceRelay))));

        vm.expectRevert("L2GovernanceRelay/delegatecall-error");
        vm.prank(l2Oapp); relay.relay(spell, abi.encodeWithSignature("bad()"));
    }

    function testRelayRevert() public {
        OappReceiverMock(l2Oapp).setMessageOrigin(1, bytes32(uint256(uint160(l1GovernanceRelay))));

        vm.expectRevert("L2SpellMock/revt");
        vm.prank(l2Oapp); relay.relay(spell, abi.encodeCall(L2SpellMock.revt, ()));
    }
}
