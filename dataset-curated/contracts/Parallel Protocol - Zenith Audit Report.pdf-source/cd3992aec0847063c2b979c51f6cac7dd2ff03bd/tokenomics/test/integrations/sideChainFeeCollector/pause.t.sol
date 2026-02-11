// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import "test/Integrations.t.sol";

contract SideChainFeeCollector_Pause_Integrations_Test is Integrations_Test {
    function test_SideChainFeeCollector_Pause() external {
        vm.startPrank(users.admin.addr);
        vm.expectEmit(address(sideChainFeeCollector));
        emit Pausable.Paused(users.admin.addr);
        sideChainFeeCollector.pause();
        assertTrue(sideChainFeeCollector.paused());
    }

    function test_SideChainFeeCollector_Pause_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        sideChainFeeCollector.pause();
    }
}
