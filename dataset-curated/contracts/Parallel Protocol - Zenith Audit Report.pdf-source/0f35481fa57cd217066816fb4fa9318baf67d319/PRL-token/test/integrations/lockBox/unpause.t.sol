// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "test/Integrations.t.sol";

contract LockBox_UnPause_Integrations_Test is Integrations_Test {
    function setUp() public virtual override {
        super.setUp();
        address owner = users.owner.addr;
        vm.startPrank(owner);
        lockBox.pause();
    }

    function test_PrlBridge_UnPause() external {
        address owner = users.owner.addr;
        vm.startPrank(owner);
        vm.expectEmit(address(lockBox));
        emit Pausable.Unpaused(owner);
        lockBox.unpause();
        assertFalse(lockBox.paused());
    }

    function test_PrlBridge_RevertWhen_CallerNotOwner() external {
        address hacker = users.hacker.addr;
        vm.startPrank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        lockBox.unpause();
    }
}
