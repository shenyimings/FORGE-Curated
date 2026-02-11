// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract SideChainFeeCollector_UpdateDestinationReceiver_Integrations_Test is Integrations_Test {
    address newDestinationReceiver = makeAddr("newDestinationReceiver");

    function test_SideChainFeeCollector_UpdateDestinationReceiver() external {
        vm.startPrank(users.admin.addr);

        sideChainFeeCollector.updateDestinationReceiver(newDestinationReceiver);
        assertEq(sideChainFeeCollector.destinationReceiver(), newDestinationReceiver);
    }

    function test_SideChainFeeCollector_UpdateDestinationReceiver_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        sideChainFeeCollector.updateDestinationReceiver(users.hacker.addr);
    }
}
