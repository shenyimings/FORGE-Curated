// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import "test/Integrations.t.sol";

contract TimeLockPenaltyERC20_UnPause_Integrations_Test is Integrations_Test {
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(users.admin.addr);
        timeLockPenaltyERC20.pause();
    }

    function test_TimeLockPenaltyERC20_UnPause() external {
        vm.expectEmit(address(timeLockPenaltyERC20));
        emit Pausable.Unpaused(users.admin.addr);
        timeLockPenaltyERC20.unpause();
        assertFalse(timeLockPenaltyERC20.paused());
    }

    function test_TimeLockPenaltyERC20_UnPause_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        timeLockPenaltyERC20.unpause();
    }
}
