// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "test/Integrations.t.sol";

contract LockBox_Pause_Integrations_Test is Integrations_Test {
    function test_LockBox_Pause() external {
        address owner = users.owner.addr;
        vm.startPrank(owner);
        vm.expectEmit(address(lockBox));
        emit Pausable.Paused(owner);
        lockBox.pause();
        assertTrue(lockBox.paused());
    }

    function test_LockBox_RevertWhen_CallerNotOwner() external {
        address hacker = users.hacker.addr;
        vm.startPrank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        lockBox.pause();
    }
}
