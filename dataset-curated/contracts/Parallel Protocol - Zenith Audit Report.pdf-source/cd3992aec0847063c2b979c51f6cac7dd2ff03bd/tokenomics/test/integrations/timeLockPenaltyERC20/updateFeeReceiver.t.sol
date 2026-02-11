// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract TimeLockPenaltyERC20_UpdateFeeReceiver_Integrations_Test is Integrations_Test {
    address internal newPaymentReceiver = makeAddr("newPaymentReceiver");

    function test_TimeLockPenaltyERC20_UpdateFeeReceiver() external {
        vm.startPrank(users.admin.addr);
        vm.expectEmit(address(timeLockPenaltyERC20));
        emit TimeLockPenaltyERC20.FeeReceiverUpdated(newPaymentReceiver);
        timeLockPenaltyERC20.updateFeeReceiver(newPaymentReceiver);
    }

    function test_TimeLockPenaltyERC20_UpdateFeeReceiver_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        timeLockPenaltyERC20.updateFeeReceiver(newPaymentReceiver);
    }
}
