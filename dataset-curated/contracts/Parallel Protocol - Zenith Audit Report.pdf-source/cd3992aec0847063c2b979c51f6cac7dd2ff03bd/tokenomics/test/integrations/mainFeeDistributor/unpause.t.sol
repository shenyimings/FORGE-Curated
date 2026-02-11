// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import "test/Integrations.t.sol";

contract MainFeeDistributor_UnPause_Integrations_Test is Integrations_Test {
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(users.admin.addr);
        mainFeeDistributor.pause();
    }

    function test_MainFeeDistributor_UnPause() external {
        vm.expectEmit(address(mainFeeDistributor));
        emit Pausable.Unpaused(users.admin.addr);
        mainFeeDistributor.unpause();
        assertFalse(mainFeeDistributor.paused());
    }

    function test_MainFeeDistributor_UnPause_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        mainFeeDistributor.unpause();
    }
}
