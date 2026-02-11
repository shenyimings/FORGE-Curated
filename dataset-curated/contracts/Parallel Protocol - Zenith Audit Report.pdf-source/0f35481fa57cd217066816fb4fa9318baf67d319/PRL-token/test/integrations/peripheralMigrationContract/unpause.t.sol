// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "test/Integrations.t.sol";

contract PeripheralMigrationContract_UnPause_Integrations_Test is Integrations_Test {
    function setUp() public virtual override {
        super.setUp();
        address owner = users.owner.addr;
        vm.startPrank(owner);
        peripheralMigrationContractA.pause();
    }

    function test_PeripheralMigrationContract_UnPause() external {
        address owner = users.owner.addr;
        vm.startPrank(owner);
        vm.expectEmit(address(peripheralMigrationContractA));
        emit Pausable.Unpaused(owner);
        peripheralMigrationContractA.unpause();
        assertFalse(peripheralMigrationContractA.paused());
    }

    function test_PeripheralMigrationContract_RevertWhen_CallerNotOwner() external {
        address hacker = users.hacker.addr;
        vm.startPrank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        peripheralMigrationContractA.unpause();
    }
}
