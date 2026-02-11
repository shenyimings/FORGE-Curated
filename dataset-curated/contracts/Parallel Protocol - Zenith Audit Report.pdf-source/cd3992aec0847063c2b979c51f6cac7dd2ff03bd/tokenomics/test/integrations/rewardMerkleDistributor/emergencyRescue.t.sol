// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import "test/Integrations.t.sol";

contract RewardMerkleDistributor_EmergencyRescue_Integrations_Test is Integrations_Test {
    address internal receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        vm.startPrank(users.admin.addr);
        par.mint(address(rewardMerkleDistributor), INITIAL_BALANCE);
    }

    modifier pauseContract() {
        vm.startPrank(users.admin.addr);
        rewardMerkleDistributor.pause();
        _;
    }

    function test_RewardMerkleDistributor_EmergencyRescue() external pauseContract {
        vm.expectEmit(true, true, true, true);
        emit RewardMerkleDistributor.EmergencyRescued(address(par), receiver, INITIAL_BALANCE);
        rewardMerkleDistributor.emergencyRescue(address(par), receiver, INITIAL_BALANCE);
        assertEq(par.balanceOf(address(rewardMerkleDistributor)), 0);
        assertEq(par.balanceOf(receiver), INITIAL_BALANCE);
    }

    function test_RewardMerkleDistributor_EmergencyRescue_RevertWhen_CallerNotAuthorized() external pauseContract {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        rewardMerkleDistributor.emergencyRescue(address(par), users.hacker.addr, INITIAL_BALANCE);
    }

    function test_RewardMerkleDistributor_EmergencyRescue_RevertWhen_ContractNotPaused() external {
        vm.startPrank(users.admin.addr);
        vm.expectRevert(abi.encodeWithSelector(Pausable.ExpectedPause.selector));
        rewardMerkleDistributor.emergencyRescue(address(par), receiver, INITIAL_BALANCE);
    }
}
