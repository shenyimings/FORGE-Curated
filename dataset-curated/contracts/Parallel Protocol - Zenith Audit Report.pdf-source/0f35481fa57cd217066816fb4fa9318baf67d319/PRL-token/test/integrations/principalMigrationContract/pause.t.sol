// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "test/Integrations.t.sol";

contract PrincipalMigrationContract_Pause_Integrations_Test is Integrations_Test {
    function test_PrincipalMigrationContract_Pause() external {
        address owner = users.owner.addr;
        vm.startPrank(owner);
        vm.expectEmit(address(principalMigrationContract));
        emit Pausable.Paused(owner);
        principalMigrationContract.pause();
        assertTrue(principalMigrationContract.paused());
    }

    function test_PrincipalMigrationContract_RevertWhen_CallerNotOwner() external {
        address hacker = users.hacker.addr;
        vm.startPrank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        principalMigrationContract.pause();
    }
}
