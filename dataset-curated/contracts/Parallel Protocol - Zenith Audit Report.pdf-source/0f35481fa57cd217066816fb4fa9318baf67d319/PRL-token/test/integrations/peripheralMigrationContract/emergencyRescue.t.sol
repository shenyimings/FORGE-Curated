// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "test/Integrations.t.sol";

contract PeripheralMigrationContract_EmergencyRescue_Integrations_Test is Integrations_Test {
    function setUp() public override {
        super.setUp();
        deal(address(mimo), address(peripheralMigrationContractA), INITIAL_BALANCE);
    }

    modifier pauseContract() {
        address owner = users.owner.addr;
        vm.startPrank(owner);
        peripheralMigrationContractA.pause();
        _;
    }

    function test_PeripheralMigrationContract_EmergencyRescue() external pauseContract {
        address owner = users.owner.addr;
        vm.startPrank(owner);
        vm.expectEmit(address(peripheralMigrationContractA));
        emit PeripheralMigrationContract.EmergencyRescued(address(mimo), INITIAL_BALANCE, owner);
        peripheralMigrationContractA.emergencyRescue(address(mimo), INITIAL_BALANCE);
        assertEq(mimo.balanceOf(address(peripheralMigrationContractA)), 0);
    }

    function test_PeripheralMigrationContract_EmergencyRescue_RevertWhen_NotPaused() external {
        address owner = users.owner.addr;
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(Pausable.ExpectedPause.selector));
        peripheralMigrationContractA.emergencyRescue(address(mimo), INITIAL_BALANCE);
    }

    function test_PeripheralMigrationContract_EmergencyRescue_RevertWhen_CallerNotOwner() external {
        address hacker = users.hacker.addr;
        vm.startPrank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        peripheralMigrationContractA.emergencyRescue(address(mimo), INITIAL_BALANCE);
    }
}
