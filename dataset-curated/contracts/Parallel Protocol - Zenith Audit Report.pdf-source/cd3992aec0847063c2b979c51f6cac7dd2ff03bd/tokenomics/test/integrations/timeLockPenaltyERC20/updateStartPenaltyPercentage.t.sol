// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract TimeLockPenaltyERC20_UpdateStartPenaltyPercentage_Integrations_Test is Integrations_Test {
    uint256 newStartPenaltyPercentage = 0.5e18;

    function test_TimeLockPenaltyERC20_UpdateStartPenaltyPercentage() external {
        vm.startPrank(users.admin.addr);
        vm.expectEmit(address(timeLockPenaltyERC20));
        emit TimeLockPenaltyERC20.StartPenaltyPercentageUpdated(DEFAULT_PENALTY_PERCENTAGE, newStartPenaltyPercentage);
        timeLockPenaltyERC20.updateStartPenaltyPercentage(newStartPenaltyPercentage);
    }

    function test_TimeLockPenaltyERC20_UpdateStartPenaltyPercentage_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        timeLockPenaltyERC20.updateStartPenaltyPercentage(newStartPenaltyPercentage);
    }

    function test_TimeLockPenaltyERC20_UpdateStartPenaltyPercentage_RevertWhen_NewStartPenaltyPercentageExceedMax()
        external
    {
        uint256 wrongStartPenaltyPercentage = 1e18 + 1;
        vm.startPrank(users.admin.addr);
        vm.expectRevert(
            abi.encodeWithSelector(TimeLockPenaltyERC20.PercentageOutOfRange.selector, wrongStartPenaltyPercentage)
        );
        timeLockPenaltyERC20.updateStartPenaltyPercentage(wrongStartPenaltyPercentage);
    }
}
