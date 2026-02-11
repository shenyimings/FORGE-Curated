// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import "test/Integrations.t.sol";

contract MainFeeDistributor_Pause_Integrations_Test is Integrations_Test {
    function test_MainFeeDistributor_Pause() external {
        vm.startPrank(users.admin.addr);
        vm.expectEmit(address(mainFeeDistributor));
        emit Pausable.Paused(users.admin.addr);
        mainFeeDistributor.pause();
        assertTrue(mainFeeDistributor.paused());
    }

    function test_MainFeeDistributor_Pause_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        mainFeeDistributor.pause();
    }
}
