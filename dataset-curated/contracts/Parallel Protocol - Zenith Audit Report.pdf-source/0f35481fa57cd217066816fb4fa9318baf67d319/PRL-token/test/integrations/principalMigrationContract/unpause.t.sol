// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "test/Integrations.t.sol";

contract PrincipalMigrationContract_UnPause_Integrations_Test is Integrations_Test {
    function setUp() public virtual override {
        super.setUp();
        address owner = users.owner.addr;
        vm.startPrank(owner);
        principalMigrationContract.pause();
    }

    function test_PrincipalMigrationContract_UnPause() external {
        address owner = users.owner.addr;
        vm.startPrank(owner);
        vm.expectEmit(address(principalMigrationContract));
        emit Pausable.Unpaused(owner);
        principalMigrationContract.unpause();
        assertFalse(principalMigrationContract.paused());
    }

    function test_PrincipalMigrationContract_RevertWhen_CallerNotOwner() external {
        address hacker = users.hacker.addr;
        vm.startPrank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        principalMigrationContract.unpause();
    }
}
