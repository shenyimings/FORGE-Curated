// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {CashbackRewardsTest} from "../../../lib/CashbackRewardsTest.sol";

import {Flywheel} from "../../../../src/Flywheel.sol";
import {SimpleRewards} from "../../../../src/hooks/SimpleRewards.sol";

contract OnWithdrawFundsTest is CashbackRewardsTest {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when unauthorized caller attempts to withdraw funds
    /// @param withdrawAmount Amount to attempt withdrawing
    /// @param unauthorizedCaller Address that is not the campaign owner
    function test_revert_unauthorizedWithdrawal(uint256 withdrawAmount, address unauthorizedCaller) public {
        withdrawAmount = bound(withdrawAmount, 1e6, DEFAULT_CAMPAIGN_BALANCE);
        vm.assume(unauthorizedCaller != owner && unauthorizedCaller != address(0));

        // Anyone other than owner should not be able to withdraw
        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(unauthorizedCaller);
        flywheel.withdrawFunds(
            unlimitedCashbackCampaign,
            address(usdc),
            abi.encode(Flywheel.Payout({recipient: unauthorizedCaller, amount: withdrawAmount, extraData: ""}))
        );
    }

    /// @dev Reverts when manager attempts to withdraw funds (only owner can)
    /// @param withdrawAmount Amount to attempt withdrawing
    function test_revert_managerCannotWithdrawFunds(uint256 withdrawAmount) public {
        withdrawAmount = bound(withdrawAmount, 1e6, DEFAULT_CAMPAIGN_BALANCE);

        // Even the manager should not be able to withdraw funds (only owner can)
        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(manager);
        flywheel.withdrawFunds(
            unlimitedCashbackCampaign,
            address(usdc),
            abi.encode(Flywheel.Payout({recipient: manager, amount: withdrawAmount, extraData: ""}))
        );
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Successfully allows owner to withdraw funds from campaign
    /// @param withdrawAmount Amount to withdraw from campaign balance
    function test_success_ownerCanWithdrawFunds(uint256 withdrawAmount) public {
        withdrawAmount = bound(withdrawAmount, 1e6, DEFAULT_CAMPAIGN_BALANCE);

        vm.prank(owner);
        flywheel.withdrawFunds(
            unlimitedCashbackCampaign,
            address(usdc),
            abi.encode(Flywheel.Payout({recipient: owner, amount: withdrawAmount, extraData: ""}))
        );

        uint256 finalBalance = usdc.balanceOf(unlimitedCashbackCampaign);
        assertEq(finalBalance, DEFAULT_CAMPAIGN_BALANCE - withdrawAmount);
    }
}
