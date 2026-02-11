// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract TimeLockPenaltyERC20_UpdateTimeLockDuration_Integrations_Test is Integrations_Test {
    uint64 newLockDuration = 1 days;

    function test_TimeLockPenaltyERC20_UpdateTimeLockDuration() external {
        vm.startPrank(users.admin.addr);
        vm.expectEmit(address(timeLockPenaltyERC20));
        emit TimeLockPenaltyERC20.TimeLockUpdated(DEFAULT_TIME_LOCK_DURATION, newLockDuration);
        timeLockPenaltyERC20.updateTimeLockDuration(newLockDuration);
    }

    function test_TimeLockPenaltyERC20_UpdateTimeLockDuration_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        timeLockPenaltyERC20.updateTimeLockDuration(newLockDuration);
    }

    function test_TimeLockPenaltyERC20_UpdateTimeLockDuration_RevertWhen_NewTimeLockBelowMin() external {
        uint64 wrongLockDuration = 1 days - 1;
        vm.startPrank(users.admin.addr);
        vm.expectRevert(abi.encodeWithSelector(TimeLockPenaltyERC20.TimelockOutOfRange.selector, wrongLockDuration));
        timeLockPenaltyERC20.updateTimeLockDuration(wrongLockDuration);
    }

    function test_TimeLockPenaltyERC20_UpdateTimeLockDuration_RevertWhen_NewTimeLockExceedMax() external {
        uint64 wrongLockDuration = 365 days + 1;
        vm.startPrank(users.admin.addr);
        vm.expectRevert(abi.encodeWithSelector(TimeLockPenaltyERC20.TimelockOutOfRange.selector, wrongLockDuration));
        timeLockPenaltyERC20.updateTimeLockDuration(wrongLockDuration);
    }
}
