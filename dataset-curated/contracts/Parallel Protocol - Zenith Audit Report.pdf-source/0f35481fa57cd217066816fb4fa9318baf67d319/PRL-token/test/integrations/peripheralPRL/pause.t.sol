// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "test/Integrations.t.sol";

contract PeripheralPRL_Pause_Integrations_Test is Integrations_Test {
    function test_PeripheralPRL_Pause() external {
        address owner = users.owner.addr;
        vm.startPrank(owner);
        vm.expectEmit(address(peripheralPRLA));
        emit Pausable.Paused(owner);
        peripheralPRLA.pause();
        assertTrue(peripheralPRLA.paused());
    }

    function test_PeripheralPRL_RevertWhen_CallerNotOwner() external {
        address hacker = users.hacker.addr;
        vm.startPrank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        peripheralPRLA.pause();
    }
}
