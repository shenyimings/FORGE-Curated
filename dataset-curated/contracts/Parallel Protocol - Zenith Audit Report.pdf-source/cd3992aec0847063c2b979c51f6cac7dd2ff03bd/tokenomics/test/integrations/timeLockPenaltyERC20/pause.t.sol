// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import "test/Integrations.t.sol";

contract TimeLockPenaltyERC20_Pause_Integrations_Test is Integrations_Test {
    function test_TimeLockPenaltyERC20_Pause() external {
        vm.startPrank(users.admin.addr);
        vm.expectEmit(address(timeLockPenaltyERC20));
        emit Pausable.Paused(users.admin.addr);
        timeLockPenaltyERC20.pause();
        assertTrue(timeLockPenaltyERC20.paused());
    }

    function test_TimeLockPenaltyERC20_Pause_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        timeLockPenaltyERC20.pause();
    }
}
