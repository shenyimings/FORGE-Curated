// SPDX-License-Identifier: GPL-3.0-or-later

// Chief.t.sol - tests for Chief.sol

// Copyright (C) 2017 DappHub, LLC
// Copyright (C) 2023 Dai Foundation

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

import "forge-std/Test.sol";

import "src/Chief.sol";
import "test/mocks/TokenMock.sol";

contract ChiefTest is Test {
    uint256 constant electionSize = 3;

    // c prefix: candidate
    address constant c1 = address(0x1);
    address constant c2 = address(0x2);
    address constant c3 = address(0x3);
    address constant c4 = address(0x4);
    uint256 constant initialBalance = 1_000_000 ether;
    uint256 constant uLargeInitialBalance = initialBalance / 3;
    uint256 constant uMediumInitialBalance = initialBalance / 4;
    uint256 constant uSmallInitialBalance = initialBalance / 5;

    Chief chief;
    TokenMock gov;

    // u prefix: user
    address uLarge;
    address uMedium;
    address uSmall;

    event Launch();
    event Lock(address indexed usr, uint256 wad);
    event Free(address indexed usr, uint256 wad);
    event Etch(bytes32 indexed slate, address[] yays);
    event Vote(address indexed usr, bytes32 indexed slate);
    event Lift(address indexed whom);

    function setUp() public {
        gov = new TokenMock();
        deal(address(gov), address(this), initialBalance);

        chief = new Chief(address(gov), electionSize, 80_000 ether, 10);

        uLarge = address(123);
        uMedium = address(456);
        uSmall = address(789);

        assertGt(initialBalance, uLargeInitialBalance + uMediumInitialBalance + uSmallInitialBalance);
        assertLt(uLargeInitialBalance, uMediumInitialBalance + uSmallInitialBalance);

        gov.transfer(uLarge, uLargeInitialBalance);
        gov.transfer(uMedium, uMediumInitialBalance);
        gov.transfer(uSmall, uSmallInitialBalance);
        vm.roll(1_000); // Block number = 1000
    }

    function _enableSystem() internal {
        address[] memory yays = new address[](1);
        yays[0] = address(0);
        gov.approve(address(chief), 80_000 ether);
        vm.expectEmit();
        emit Lock(address(this), 80_000 ether);
        chief.lock(80_000 ether);
        bytes32 slate = keccak256(abi.encodePacked(yays));
        emit Etch(slate, yays);
        vm.expectEmit();
        emit Vote(address(this), slate);
        chief.vote(yays);

        vm.expectEmit();
        emit Launch();
        chief.launch();
    }

    function _initialVote() internal returns (bytes32 slate) {
        vm.startPrank(uMedium);
        gov.approve(address(chief), uMediumInitialBalance);
        vm.expectEmit();
        emit Lock(uMedium, uMediumInitialBalance);
        chief.lock(uMediumInitialBalance);

        address[] memory uMediumYays = new address[](3);
        uMediumYays[0] = c1;
        uMediumYays[1] = c2;
        uMediumYays[2] = c3;
        slate = chief.vote(uMediumYays);
        vm.stopPrank();

        // Lift the new hat
        chief.lift(c1);
    }

    function testCompatibilityGetters() public view {
        assertEq(address(chief.GOV()), address(chief.gov()));
        assertEq(chief.MAX_YAYS(), chief.maxYays());
    }

    function testSlateLengthGetter() public {
        address[] memory yays0 = new address[](0);
        address[] memory yays1 = new address[](1);
        yays1[0] = address(1);
        address[] memory yays2 = new address[](2);
        yays2[0] = address(1);
        yays2[1] = address(2);
        address[] memory yays3 = new address[](3);
        yays3[0] = address(1);
        yays3[1] = address(2);
        yays3[2] = address(3);
        bytes32 slate0 = chief.etch(yays0);
        bytes32 slate1 = chief.etch(yays1);
        bytes32 slate2 = chief.etch(yays2);
        bytes32 slate3 = chief.etch(yays3);
        assertEq(chief.length(slate0), 0);
        assertEq(chief.length(slate1), 1);
        assertEq(chief.length(slate2), 2);
        assertEq(chief.length(slate3), 3);
    }

    function testLaunchAlreadyLive() public {
        assertEq(chief.live(), 0);
        _enableSystem();
        assertEq(chief.live(), 1);

        vm.expectRevert("Chief/already-live");
        chief.launch();
    }

    function testLaunchHatNotZero() public {
        address[] memory yays = new address[](1);
        yays[0] = address(1);
        gov.approve(address(chief), 80_000 ether);
        chief.lock(80_000 ether);
        chief.vote(yays);
        chief.lift(address(1));
        assertEq(chief.hat(), address(1));
        assertFalse(chief.canCall(address(1), address(0), bytes4(0)));

        vm.roll(block.number + chief.liftCooldown() + 1);

        vm.expectRevert("Chief/not-address-zero");
        chief.launch();
        yays[0] = address(0);
        chief.vote(yays);
        chief.lift(address(0));
        assertEq(chief.hat(), address(0));
        assertEq(chief.live(), 0);
        assertFalse(chief.canCall(address(0), address(0), bytes4(0)));
        chief.launch();
        assertEq(chief.live(), 1);
        assertTrue(chief.canCall(address(0), address(0), bytes4(0)));
    }

    function testLaunchBelowThreshold() public {
        address[] memory yays = new address[](1);
        yays[0] = address(0);
        gov.approve(address(chief), 80_000 ether);
        chief.lock(80_000 ether - 1);
        chief.vote(yays);

        vm.expectRevert("Chief/less-than-threshold");
        chief.launch();
        chief.lock(1);
        assertEq(chief.hat(), address(0));
        assertEq(chief.live(), 0);
        assertFalse(chief.canCall(address(0), address(0), bytes4(0)));
        chief.launch();
        assertEq(chief.live(), 1);
        assertTrue(chief.canCall(address(0), address(0), bytes4(0)));
    }

    function testEtchReturnsSameSlateForSameYays() public {
        address[] memory yays = new address[](3);
        yays[0] = c1;
        yays[1] = c2;
        yays[2] = c3;

        vm.prank(uSmall);
        bytes32 slate = chief.etch(yays);
        assertNotEq(slate, bytes32(0));
        vm.prank(uMedium);
        assertEq32(chief.etch(yays), slate);
    }

    function testSizeZeroSlate() public {
        address[] memory yays = new address[](0);
        vm.startPrank(uSmall);
        bytes32 slate = chief.etch(yays);
        chief.vote(slate);
        vm.stopPrank();
    }

    function testSizeOneSlate() public {
        address[] memory yays = new address[](1);
        yays[0] = c1;
        vm.startPrank(uSmall);
        bytes32 slate = chief.etch(yays);
        chief.vote(slate);
        vm.stopPrank();
    }

    function testEtchRequiresLessThanMaxYays() public {
        address[] memory yays = new address[](4);
        yays[0] = c2;
        yays[1] = c1;
        yays[2] = c3;
        yays[3] = address(0xFFF);

        vm.expectRevert("Chief/greater-max-yays");
        vm.prank(uSmall);
        chief.etch(yays);
    }

    function testEtchRequiresOrderedSets() public {
        address[] memory yays = new address[](3);
        yays[0] = c2;
        yays[1] = c1;
        yays[2] = c3;

        vm.expectRevert("Chief/yays-not-ordered");
        vm.prank(uSmall);
        chief.etch(yays);
    }

    function testLockFree() public {
        assertEq(gov.balanceOf(uLarge), uLargeInitialBalance);
        uint256 lockedAmt = uLargeInitialBalance / 10;
        vm.startPrank(uLarge);
        gov.approve(address(chief), 2 * lockedAmt);
        chief.lock(lockedAmt);
        assertEq(gov.balanceOf(uLarge), uLargeInitialBalance - lockedAmt);
        assertEq(chief.deposits(uLarge), lockedAmt);
        chief.lock(lockedAmt);
        assertEq(gov.balanceOf(uLarge), uLargeInitialBalance - 2 * lockedAmt);
        assertEq(chief.deposits(uLarge), 2 * lockedAmt);
        chief.free(lockedAmt);
        assertEq(gov.balanceOf(uLarge), uLargeInitialBalance - lockedAmt);
        assertEq(chief.deposits(uLarge), lockedAmt);
        vm.stopPrank();
    }

    function testFreeAfterLaunch() public {
        _enableSystem();
        vm.expectRevert("Chief/cant-free-same-block");
        chief.free(1);
        vm.roll(block.number + 1);
        chief.free(1);
    }

    function testFreeAfterLift() public {
        _enableSystem();
        vm.roll(block.number + 1);
        chief.free(1);
        vm.roll(block.number + chief.liftCooldown());
        _initialVote();
        vm.expectRevert("Chief/cant-free-same-block");
        chief.free(1);
        vm.roll(block.number + 1);
        chief.free(1);
    }

    function testChangingWeightAfterVoting() public {
        uint256 uLargeLockedAmt = uLargeInitialBalance / 2;
        vm.startPrank(uLarge);
        gov.approve(address(chief), uLargeLockedAmt);
        chief.lock(uLargeLockedAmt);

        address[] memory uLargeYays = new address[](1);
        uLargeYays[0] = c1;
        vm.expectEmit();
        emit Vote(uLarge, keccak256(abi.encodePacked(uLargeYays)));
        chief.vote(uLargeYays);

        assertEq(chief.approvals(c1), uLargeLockedAmt);

        // Changing weight should update the weight of our candidate.
        vm.expectEmit();
        emit Free(uLarge, uLargeLockedAmt);
        chief.free(uLargeLockedAmt);
        assertEq(chief.approvals(c1), 0);

        uLargeLockedAmt = uLargeInitialBalance / 4;
        gov.approve(address(chief), uLargeLockedAmt);
        chief.lock(uLargeLockedAmt);
        vm.stopPrank();

        assertEq(chief.approvals(c1), uLargeLockedAmt);
    }

    function testVotingAndReordering() public {
        assertEq(gov.balanceOf(uLarge), uLargeInitialBalance);

        _initialVote();

        // Upset the order.
        vm.startPrank(uLarge);
        gov.approve(address(chief), uLargeInitialBalance);
        chief.lock(uLargeInitialBalance);

        address[] memory uLargeYays = new address[](1);
        uLargeYays[0] = c3;
        chief.vote(uLargeYays);
        vm.stopPrank();
    }

    function testAuthEnabledSystem() public {
        vm.startPrank(uLarge);
        gov.approve(address(chief), uLargeInitialBalance);
        chief.lock(uLargeInitialBalance);

        address[] memory uLargeYays = new address[](1);
        uLargeYays[0] = c1;
        chief.vote(uLargeYays);
        vm.stopPrank();

        _enableSystem();

        vm.roll(block.number + chief.liftCooldown() + 1);

        vm.expectEmit();
        emit Lift(c1);
        chief.lift(c1);
        assertTrue(chief.canCall(c1, address(0), bytes4(0)));
    }

    function testAuthNotEnabledSystem() public {
        vm.startPrank(uLarge);
        gov.approve(address(chief), uLargeInitialBalance);
        chief.lock(uLargeInitialBalance);

        address[] memory uLargeYays = new address[](1);
        uLargeYays[0] = c1;
        chief.vote(uLargeYays);
        vm.stopPrank();

        chief.lift(c1);
        assertFalse(chief.canCall(c1, address(0), bytes4(0)));
    }

    function testLiftCooldown() public {
        _enableSystem();

        gov.approve(address(chief), 100_000 ether);
        chief.lock(100_000 ether);

        address[] memory yays = new address[](1);
        yays[0] = c1;
        chief.vote(yays);

        vm.roll(block.number + 1);
        vm.expectRevert("Chief/cant-lift-again-yet"); // Limited by prev block launch
        chief.lift(c1);
        vm.roll(block.number + chief.liftCooldown() - 1);
        vm.expectRevert("Chief/cant-lift-again-yet");
        chief.lift(c1);
        vm.roll(block.number + 1);
        chief.lift(c1);

        yays[0] = c2;
        chief.vote(yays);

        assertEq(chief.hat(), c1);
        vm.roll(block.number + 1);
        vm.expectRevert("Chief/cant-lift-again-yet"); // Limited by prev block lift
        chief.lift(c2);
        vm.roll(block.number + chief.liftCooldown() - 1);
        vm.expectRevert("Chief/cant-lift-again-yet");
        chief.lift(c2);
        vm.roll(block.number + 1);
        chief.lift(c2);
        assertEq(chief.hat(), c2);
    }

    function testLiftCooldownSameBlock() public {
        _enableSystem();

        gov.approve(address(chief), 100_000 ether);
        chief.lock(100_000 ether);

        address[] memory yays = new address[](1);
        yays[0] = c1;
        chief.vote(yays);

        chief.lift(c1); // can lift in the same block than launch
        yays[0] = c2;
        chief.vote(yays);
        chief.lift(c2); // can lift in the same block than prev lift
    }

    function testLiftHalfApprovals() public {
        _enableSystem();
        vm.roll(block.number + chief.liftCooldown() + 1);
        _initialVote();

        // Upset the order.
        vm.startPrank(uSmall);
        gov.approve(address(chief), uSmallInitialBalance);
        chief.lock(uSmallInitialBalance);

        address[] memory uSmallYays = new address[](1);
        uSmallYays[0] = c3;
        chief.vote(uSmallYays);

        vm.stopPrank();
        vm.startPrank(uMedium);
        vm.roll(block.number + 1);
        chief.free(uMediumInitialBalance);
        vm.stopPrank();

        vm.roll(block.number + chief.liftCooldown());

        chief.lift(c3);

        assertFalse(chief.canCall(c1, address(0), bytes4(0)));
        assertFalse(chief.canCall(c2, address(0), bytes4(0)));
        assertTrue(chief.canCall(c3, address(0), bytes4(0)));
    }

    function testVotingAndReorderingWithoutWeight() public {
        assertEq(gov.balanceOf(uLarge), uLargeInitialBalance);

        _initialVote();

        vm.roll(block.number + chief.liftCooldown() + 1);

        // Vote without weight.
        address[] memory uLargeYays = new address[](1);
        uLargeYays[0] = c3;
        vm.prank(uLarge);
        chief.vote(uLargeYays);

        // Attempt to update the elected set.
        vm.expectRevert("Chief/not-higher-current-hat");
        chief.lift(c3);
    }

    function testVotingBySlate() public {
        assertEq(gov.balanceOf(uLarge), uLargeInitialBalance);

        bytes32 slate = _initialVote();

        vm.roll(block.number + chief.liftCooldown() + 1);

        // Upset the order.
        vm.startPrank(uLarge);
        gov.approve(address(chief), uLargeInitialBalance);
        chief.lock(uLargeInitialBalance);

        address[] memory uLargeYays = new address[](1);
        uLargeYays[0] = c4;
        chief.vote(uLargeYays);
        vm.stopPrank();

        // Update the elected set to reflect the new order.
        chief.lift(c4);

        // Now restore the old order using a slate.
        vm.startPrank(uSmall);
        gov.approve(address(chief), uSmallInitialBalance);
        chief.lock(uSmallInitialBalance);
        chief.vote(slate);
        vm.stopPrank();

        vm.roll(block.number + chief.liftCooldown() + 1);

        // Update the elected set to reflect the restored order.
        chief.lift(c1);
    }

    function testVoteSlateEmptyAndNotEtched() public {
        address[] memory emptyYays = new address[](0);
        chief.vote(emptyYays);

        vm.expectRevert("Chief/invalid-slate");
        chief.vote(0x1010101010101010101010101010101010101010101010101010101010101010);
    }

    function testOverflow() public {
        deal(address(gov), address(this), type(uint256).max);
        gov.approve(address(chief), type(uint256).max);
        chief.lock(type(uint256).max);
        deal(address(gov), address(this), type(uint256).max);
        gov.approve(address(chief), type(uint256).max);
        vm.expectRevert(stdError.arithmeticError);
        chief.lock(1);
    }
}
