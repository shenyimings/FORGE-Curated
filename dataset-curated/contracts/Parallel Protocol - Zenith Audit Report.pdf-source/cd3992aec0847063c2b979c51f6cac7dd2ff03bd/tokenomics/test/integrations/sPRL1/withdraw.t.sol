// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import "test/Integrations.t.sol";

contract SPRL1_Withdraw_Integrations_Test is Integrations_Test {
    uint256 WITHDRAW_AMOUNT = 1e18;

    function setUp() public override {
        super.setUp();

        vm.startPrank(users.alice.addr);
        prl.approve(address(sprl1), type(uint256).max);
        sprl1.deposit(INITIAL_BALANCE);
    }

    modifier requestSingleWithdraw() {
        sprl1.requestWithdraw(WITHDRAW_AMOUNT);
        _;
    }

    function test_SPRL1_Withdraw_SingleRequest_AfterReleaseTime() external requestSingleWithdraw {
        skip(sprl1.timeLockDuration());
        uint256 aliceBalanceBefore = prl.balanceOf(users.alice.addr);
        uint256 contractBalanceBefore = prl.balanceOf(address(sprl1));
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = 0;

        sprl1.withdraw(requestIds);

        uint256 aliceBalanceAfter = prl.balanceOf(users.alice.addr);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, WITHDRAW_AMOUNT);

        uint256 contractBalanceAfter = prl.balanceOf(address(sprl1));
        assertEq(contractBalanceBefore - contractBalanceAfter, WITHDRAW_AMOUNT);
    }

    function test_SPRL1_Withdraw_SingleRequest_HalfReleaseTime() external requestSingleWithdraw {
        skip(sprl1.timeLockDuration() / 2);
        uint256 aliceBalanceBefore = prl.balanceOf(users.alice.addr);
        uint256 contractBalanceBefore = prl.balanceOf(address(sprl1));
        uint256 expectedFee = WITHDRAW_AMOUNT / 2;

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = 0;
        sprl1.withdraw(requestIds);

        uint256 aliceBalanceAfter = prl.balanceOf(users.alice.addr);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, expectedFee);

        uint256 contractBalanceAfter = prl.balanceOf(address(sprl1));
        assertEq(contractBalanceBefore - contractBalanceAfter, WITHDRAW_AMOUNT);
        assertEq(prl.balanceOf(users.daoTreasury.addr), expectedFee);
    }

    function test_SPRL1_Withdraw_SingleRequest_AtRequestTime() external requestSingleWithdraw {
        uint256 aliceBalanceBefore = prl.balanceOf(users.alice.addr);
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = 0;
        sprl1.withdraw(requestIds);

        uint256 aliceBalanceAfter = prl.balanceOf(users.alice.addr);
        assertEq(aliceBalanceAfter, aliceBalanceBefore);

        assertEq(prl.balanceOf(address(sprl1)), INITIAL_BALANCE - WITHDRAW_AMOUNT);
        assertEq(sprl1.totalSupply(), INITIAL_BALANCE - WITHDRAW_AMOUNT);
        assertEq(prl.balanceOf(users.daoTreasury.addr), WITHDRAW_AMOUNT);
    }

    modifier requestMultiWithdraw() {
        sprl1.requestWithdraw(WITHDRAW_AMOUNT);
        sprl1.requestWithdraw(WITHDRAW_AMOUNT);
        sprl1.requestWithdraw(WITHDRAW_AMOUNT);
        _;
    }

    function test_SPRL1_Withdraw_MultipleRequests_AfterReleaseTime() external requestMultiWithdraw {
        skip(sprl1.timeLockDuration());
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = 0;
        requestIds[1] = 1;
        requestIds[2] = 2;
        uint256 expectedAmount = WITHDRAW_AMOUNT * 3;
        uint256 aliceBalanceBefore = prl.balanceOf(users.alice.addr);
        uint256 contractBalanceBefore = prl.balanceOf(address(sprl1));

        sprl1.withdraw(requestIds);

        uint256 aliceBalanceAfter = prl.balanceOf(users.alice.addr);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, expectedAmount);

        uint256 contractBalanceAfter = prl.balanceOf(address(sprl1));
        assertEq(contractBalanceBefore - contractBalanceAfter, expectedAmount);

        assertEq(sprl1.balanceOf(users.daoTreasury.addr), 0);
    }

    function test_SPRL1_Withdraw_MultipleRequests_HalfReleaseTime() external requestMultiWithdraw {
        skip(sprl1.timeLockDuration() / 2);
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = 0;
        requestIds[1] = 1;
        requestIds[2] = 2;
        uint256 expectedAmount = (WITHDRAW_AMOUNT * 3) / 2;
        uint256 aliceBalanceBefore = prl.balanceOf(users.alice.addr);

        sprl1.withdraw(requestIds);

        uint256 aliceBalanceAfter = prl.balanceOf(users.alice.addr);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, expectedAmount);

        assertEq(prl.balanceOf(address(sprl1)), INITIAL_BALANCE - (WITHDRAW_AMOUNT * 3));
        assertEq(prl.balanceOf(users.daoTreasury.addr), expectedAmount);
    }

    function test_SPRL1_Withdraw_MultipleRequests_AtRequestTime() external requestMultiWithdraw {
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = 0;
        requestIds[1] = 1;
        requestIds[2] = 2;
        uint256 aliceBalanceBefore = prl.balanceOf(users.alice.addr);

        sprl1.withdraw(requestIds);

        uint256 aliceBalanceAfter = prl.balanceOf(users.alice.addr);
        assertEq(aliceBalanceAfter, aliceBalanceBefore);

        assertEq(prl.balanceOf(address(sprl1)), INITIAL_BALANCE - WITHDRAW_AMOUNT * 3);
        assertEq(prl.balanceOf(users.daoTreasury.addr), WITHDRAW_AMOUNT * 3);
    }

    function test_SPRL1_Withdraw_MultipleRequests_RevertWhen_StatusNotUnlocking() external {
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = 0;
        vm.expectRevert(abi.encodeWithSelector(TimeLockPenaltyERC20.CannotWithdraw.selector, requestIds[0]));
        sprl1.withdraw(requestIds);
    }

    modifier PauseContract() {
        vm.startPrank(users.admin.addr);
        sprl1.pause();
        _;
    }

    function test_SPRL1_EmergencyWithdraw() external PauseContract {
        vm.startPrank(users.alice.addr);
        uint256 aliceBalanceBefore = prl.balanceOf(users.alice.addr);
        uint256 contractBalanceBefore = prl.balanceOf(address(sprl1));

        sprl1.emergencyWithdraw(WITHDRAW_AMOUNT);

        uint256 aliceBalanceAfter = prl.balanceOf(users.alice.addr);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, WITHDRAW_AMOUNT);

        uint256 contractBalanceAfter = prl.balanceOf(address(sprl1));
        assertEq(contractBalanceBefore - contractBalanceAfter, WITHDRAW_AMOUNT);

        assertEq(sprl1.balanceOf(users.daoTreasury.addr), 0);
    }
}
