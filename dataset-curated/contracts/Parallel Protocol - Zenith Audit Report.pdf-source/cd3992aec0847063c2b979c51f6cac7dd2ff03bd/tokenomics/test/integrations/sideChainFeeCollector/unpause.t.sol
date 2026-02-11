// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import "test/Integrations.t.sol";

contract SideChainFeeCollector_UnPause_Integrations_Test is Integrations_Test {
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(users.admin.addr);
        sideChainFeeCollector.pause();
    }

    function test_SideChainFeeCollector_UnPause() external {
        vm.expectEmit(address(sideChainFeeCollector));
        emit Pausable.Unpaused(users.admin.addr);
        sideChainFeeCollector.unpause();
        assertFalse(sideChainFeeCollector.paused());
    }

    function test_SideChainFeeCollector_UnPause_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        sideChainFeeCollector.unpause();
    }
}
