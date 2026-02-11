// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "test/Integrations.t.sol";

contract PrincipalMigrationContract_EmergencyRescue_Integrations_Test is Integrations_Test {
    function setUp() public override {
        super.setUp();
        deal(address(mimo), address(principalMigrationContract), INITIAL_BALANCE);
    }

    modifier pauseContract() {
        address owner = users.owner.addr;
        vm.startPrank(owner);
        principalMigrationContract.pause();
        _;
    }

    function test_PrincipalMigrationContract_EmergencyRescue() external pauseContract {
        address owner = users.owner.addr;
        vm.startPrank(owner);
        vm.expectEmit(address(principalMigrationContract));
        emit PrincipalMigrationContract.EmergencyRescued(address(mimo), INITIAL_BALANCE, owner);
        principalMigrationContract.emergencyRescue(address(mimo), INITIAL_BALANCE);
        assertEq(mimo.balanceOf(address(principalMigrationContract)), 0);
    }

    function test_PrincipalMigrationContract_EmergencyRescue_RevertWhen_NotPaused() external {
        address owner = users.owner.addr;
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(Pausable.ExpectedPause.selector));
        principalMigrationContract.emergencyRescue(address(mimo), INITIAL_BALANCE);
    }

    function test_PrincipalMigrationContract_EmergencyRescue_RevertWhen_CallerNotOwner() external {
        address hacker = users.hacker.addr;
        vm.startPrank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        principalMigrationContract.emergencyRescue(address(mimo), INITIAL_BALANCE);
    }
}
