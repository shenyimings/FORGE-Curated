// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import "test/Integrations.t.sol";

contract SPRL1_RequestWithdraw_Integrations_Test is Integrations_Test {
    function setUp() public override {
        super.setUp();
        vm.startPrank(users.alice.addr);

        prl.approve(address(sprl1), type(uint256).max);
        sprl1.deposit(INITIAL_BALANCE);
    }

    function test_SPRL1_RequestWithdraw() external {
        vm.expectEmit(address(sprl1));
        emit TimeLockPenaltyERC20.WithdrawalRequested(0, users.alice.addr, INITIAL_BALANCE);
        sprl1.requestWithdraw(INITIAL_BALANCE);

        assertEq(sprl1.balanceOf(users.alice.addr), 0);
        assertEq(sprl1.unlockingAmount(), INITIAL_BALANCE);
        assertEq(prl.balanceOf(address(sprl1)), INITIAL_BALANCE);

        (uint256 requestAmount, uint64 requestTime, uint64 releaseTime, TimeLockPenaltyERC20.WITHDRAW_STATUS status) =
            sprl1.userVsWithdrawals(users.alice.addr, 0);

        assertEq(requestAmount, INITIAL_BALANCE);
        assertEq(requestTime, block.timestamp);
        assertEq(releaseTime, block.timestamp + sprl1.timeLockDuration());
        assertEq(status, TimeLockPenaltyERC20.WITHDRAW_STATUS.UNLOCKING);

        uint256[] memory requestIds = sprl1.findUnlockingIDs(users.alice.addr, 0, false, 1);
        assertEq(requestIds.length, 1);
        assertEq(requestIds[0], 0);
    }

    function testFuzz_SPRL1_RequestWithdraw_Several(uint16 requestTime) external {
        requestTime = _boundUint16(requestTime, 1, 100);
        uint256 withdrawAmount = INITIAL_BALANCE / requestTime;
        uint256 expectedAmount = withdrawAmount * requestTime;
        for (uint16 i = 0; i < requestTime; i++) {
            sprl1.requestWithdraw(withdrawAmount);
        }
        assertEq(sprl1.balanceOf(users.alice.addr), INITIAL_BALANCE - expectedAmount);
        assertEq(sprl1.unlockingAmount(), expectedAmount);

        uint256[] memory requestIds = sprl1.findUnlockingIDs(users.alice.addr, 0, false, requestTime);
        assertEq(requestIds.length, requestTime);
    }
}
