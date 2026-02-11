// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import "test/Integrations.t.sol";

contract SPRL2_RequestWithdraw_Integrations_Test is Integrations_Test {
    function setUp() public override {
        super.setUp();
        vm.startPrank(users.alice.addr);

        deal(address(bpt), address(users.alice.addr), INITIAL_BALANCE);
        bpt.approve(address(sprl2), type(uint256).max);
        sprl2.depositBPT(INITIAL_BALANCE);
    }

    function test_SPRL2_RequestWithdraw() external {
        vm.expectEmit(address(sprl2));
        emit TimeLockPenaltyERC20.WithdrawalRequested(0, users.alice.addr, INITIAL_BALANCE);
        sprl2.requestWithdraw(INITIAL_BALANCE);

        assertEq(sprl2.balanceOf(users.alice.addr), 0);
        assertEq(sprl2.unlockingAmount(), INITIAL_BALANCE);

        (uint256 requestAmount, uint64 requestTime, uint64 releaseTime, TimeLockPenaltyERC20.WITHDRAW_STATUS status) =
            sprl2.userVsWithdrawals(users.alice.addr, 0);

        assertEq(requestAmount, INITIAL_BALANCE);
        assertEq(requestTime, block.timestamp);
        assertEq(releaseTime, block.timestamp + sprl2.timeLockDuration());
        assertEq(status, TimeLockPenaltyERC20.WITHDRAW_STATUS.UNLOCKING);

        uint256[] memory requestIds = sprl2.findUnlockingIDs(users.alice.addr, 0, false, 1);
        assertEq(requestIds.length, 1);
        assertEq(requestIds[0], 0);
    }

    function testFuzz_SPRL2_RequestWithdraw_Several(uint16 requestTime) external {
        requestTime = _boundUint16(requestTime, 1, 100);
        uint256 withdrawAmount = INITIAL_BALANCE / requestTime;
        uint256 expectedAmount = withdrawAmount * requestTime;
        for (uint16 i = 0; i < requestTime; i++) {
            sprl2.requestWithdraw(withdrawAmount);
        }
        assertEq(sprl2.balanceOf(users.alice.addr), INITIAL_BALANCE - expectedAmount);
        assertEq(sprl2.unlockingAmount(), expectedAmount);

        uint256[] memory requestIds = sprl2.findUnlockingIDs(users.alice.addr, 0, false, requestTime);
        assertEq(requestIds.length, requestTime);
    }
}
