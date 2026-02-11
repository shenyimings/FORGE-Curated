// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract SideChainFeeCollector_UpdateBridgeableToken_Integrations_Test is Integrations_Test {
    address newBridgeableToken = makeAddr("newBridgeableToken");

    function test_SideChainFeeCollector_UpdateBridgeableToken() external {
        vm.startPrank(users.admin.addr);

        sideChainFeeCollector.updateBridgeableToken(newBridgeableToken);
        assertEq(address(sideChainFeeCollector.bridgeableToken()), newBridgeableToken);
    }

    function test_SideChainFeeCollector_UpdateBridgeableToken_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        sideChainFeeCollector.updateBridgeableToken(users.hacker.addr);
    }
}
