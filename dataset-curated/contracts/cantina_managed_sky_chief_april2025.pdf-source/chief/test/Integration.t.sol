// SPDX-License-Identifier: GPL-3.0-or-later

// Integration.t.sol - tests for Integration.sol

// Copyright (C) 2025 Dai Foundation

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

import "dss-test/DssTest.sol";
import "dss-interfaces/Interfaces.sol";

import "src/Chief.sol";

interface TokenLike {
    function approve(address, uint256) external;
}

contract ChiefTest is DssTest {
    DssInstance dss;
    Chief chief;
    address sky;
    DSPauseAbstract pause;
    ClipperMomAbstract mom;

    address spell = address(0xfff);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        dss = MCD.loadFromChainlog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
    
        sky = dss.chainlog.getAddress("SKY");
        pause = DSPauseAbstract(dss.chainlog.getAddress("MCD_PAUSE"));
        mom = ClipperMomAbstract(dss.chainlog.getAddress("CLIPPER_MOM"));
        chief = new Chief(sky, 5, 2 * 10**9 * 10**18, 10);

        address pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");
        vm.prank(pauseProxy); pause.setAuthority(address(chief));
        vm.prank(pauseProxy); mom.setAuthority(address(chief));

        deal(sky, address(this), 2 * 10**9 * 10**18);
        TokenLike(sky).approve(address(chief), 2 * 10**9 * 10**18);
        chief.lock(2 * 10**9 * 10**18);
        address[] memory yays = new address[](1);
        yays[0] = address(0);
        chief.vote(yays);
        chief.launch();
        yays[0] = spell;
        chief.vote(yays);
    }

    function testPausePlot() public {
        uint256 eta = block.timestamp + pause.delay();
        assertFalse(pause.plans(keccak256(abi.encode(address(123), bytes32(uint256(456)), "", eta))));
        vm.expectRevert("ds-auth-unauthorized");
        vm.prank(spell); pause.plot(address(123), bytes32(uint256(456)), "", eta);
        chief.lift(spell);
        vm.prank(spell); pause.plot(address(123), bytes32(uint256(456)), "", eta);
        assertTrue(pause.plans(keccak256(abi.encode(address(123), bytes32(uint256(456)), "", eta))));
    }

    function testMomAction() public {
        ClipAbstract clip = ClipAbstract(dss.chainlog.getAddress("MCD_CLIP_ETH_A"));
        assertEq(clip.stopped(), 0);
        vm.expectRevert("ClipperMom/not-authorized");
        vm.prank(spell); mom.setBreaker(address(clip), 3 , 1);
        chief.lift(spell);
        vm.prank(spell); mom.setBreaker(address(clip), 3 , 1);
        assertEq(clip.stopped(), 3);
    }
}
