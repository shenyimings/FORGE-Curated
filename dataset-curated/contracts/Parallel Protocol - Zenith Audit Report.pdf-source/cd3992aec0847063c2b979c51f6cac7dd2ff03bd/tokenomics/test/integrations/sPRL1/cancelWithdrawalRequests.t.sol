// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import "test/Integrations.t.sol";

contract SPRL1_CancelWithdrawalRequests_Integrations_Test is Integrations_Test {
    function setUp() public override {
        super.setUp();
        vm.startPrank(users.alice.addr);
        prl.approve(address(sprl1), type(uint256).max);
        sprl1.deposit(INITIAL_BALANCE);
    }

    modifier requestOneWithdraw() {
        sprl1.requestWithdraw(INITIAL_BALANCE);
        _;
    }

    function test_SPRL1_CancelWithdrawalRequests_SingleRequest() external requestOneWithdraw {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        vm.expectEmit(address(sprl1));
        emit TimeLockPenaltyERC20.WithdrawalRequestCancelled(ids[0], users.alice.addr, INITIAL_BALANCE);
        sprl1.cancelWithdrawalRequests(ids);
        assertEq(sprl1.balanceOf(users.alice.addr), INITIAL_BALANCE);
        assertEq(sprl1.unlockingAmount(), 0);
        assertEq(prl.balanceOf(address(sprl1)), INITIAL_BALANCE);

        (uint256 requestAmount, uint64 requestTime, uint64 releaseTime, TimeLockPenaltyERC20.WITHDRAW_STATUS status) =
            sprl1.userVsWithdrawals(users.alice.addr, ids[0]);

        assertEq(requestAmount, INITIAL_BALANCE);
        assertEq(requestTime, block.timestamp);
        assertEq(releaseTime, block.timestamp + sprl1.timeLockDuration());
        assertEq(status, TimeLockPenaltyERC20.WITHDRAW_STATUS.CANCELLED);

        uint256[] memory requestIds = sprl1.findUnlockingIDs(users.alice.addr, 0, false, 1);
        assertEq(requestIds.length, 0);
    }

    modifier requestMultiWithdraw() {
        sprl1.requestWithdraw(1);
        sprl1.requestWithdraw(2);
        sprl1.requestWithdraw(3);
        sprl1.requestWithdraw(4);
        sprl1.requestWithdraw(5);
        _;
    }

    function test_SPRL1_CancelWithdrawalRequests_MultipleRequests() external requestMultiWithdraw {
        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 2;
        ids[2] = 4;
        sprl1.cancelWithdrawalRequests(ids);

        assertEq(sprl1.balanceOf(users.alice.addr), INITIAL_BALANCE - 6);
        assertEq(sprl1.unlockingAmount(), 6);
        assertEq(prl.balanceOf(address(sprl1)), INITIAL_BALANCE);

        uint256[] memory requestIds = sprl1.findUnlockingIDs(users.alice.addr, 0, false, 10);
        assertEq(requestIds.length, 2);
        assertEq(requestIds[0], 1);
        assertEq(requestIds[1], 3);
    }

    function test_SPRL1_CancelWithdrawalRequests_RevertWhen_WrongRequestStatus() external {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        vm.expectRevert(abi.encodeWithSelector(TimeLockPenaltyERC20.CannotCancelWithdrawalRequest.selector, ids[0]));
        sprl1.cancelWithdrawalRequests(ids);
    }
}
