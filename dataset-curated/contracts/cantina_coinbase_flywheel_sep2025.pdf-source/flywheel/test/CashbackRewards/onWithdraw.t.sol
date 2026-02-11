// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {CashbackRewardsBase} from "./CashbackRewardsBase.sol";
import {Flywheel} from "../../src/Flywheel.sol";
import {SimpleRewards} from "../../src/hooks/SimpleRewards.sol";

contract OnWithdrawTest is CashbackRewardsBase {
    function test_ownerCanWithdrawFunds(uint256 withdrawAmount) public {
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

    function test_revertsOnUnauthorizedWithdrawal(uint256 withdrawAmount, address unauthorizedCaller) public {
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

    function test_managerCannotWithdrawFunds(uint256 withdrawAmount) public {
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
}
