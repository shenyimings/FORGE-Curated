// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract MainFeeDistributor_UpdateBridgeableToken_Integrations_Test is Integrations_Test {
    address newBridgeableToken = makeAddr("newBridgeableToken");

    function test_MainFeeDistributor_UpdateBridgeableToken() external {
        vm.startPrank(users.admin.addr);

        mainFeeDistributor.updateBridgeableToken(newBridgeableToken);
        assertEq(address(mainFeeDistributor.bridgeableToken()), newBridgeableToken);
    }

    function test_MainFeeDistributor_UpdateBridgeableToken_RevertWhen_LzBalanceNotZero() external {
        bridgeableTokenMock.mint(address(mainFeeDistributor), 1);
        vm.startPrank(users.admin.addr);
        vm.expectRevert(abi.encodeWithSelector(MainFeeDistributor.NeedToSwapAllLzTokenFirst.selector));
        mainFeeDistributor.updateBridgeableToken(newBridgeableToken);
    }

    function test_MainFeeDistributor_UpdateBridgeableToken_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        mainFeeDistributor.updateBridgeableToken(users.hacker.addr);
    }
}
