// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../../../../src/Flywheel.sol";
import {BridgeReferralFeesTest} from "../../../lib/BridgeReferralFeesTest.sol";

contract OnWithdrawFundsTest is BridgeReferralFeesTest {
    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Returns payout struct decoded directly from hookData
    /// @param recipient Address to receive withdrawn funds
    /// @param amount Amount to withdraw
    /// @param extraData Additional payout data
    function test_success_passesThoughPayoutData(address recipient, uint256 amount, bytes memory extraData) public {
        vm.assume(amount > 0); // Flywheel rejects zero amount withdrawals
        Flywheel.Payout memory expectedPayout =
            Flywheel.Payout({recipient: recipient, amount: amount, extraData: extraData});

        bytes memory hookData = abi.encode(expectedPayout);

        // Fund campaign to enable withdrawal
        usdc.mint(bridgeReferralFeesCampaign, amount);

        uint256 recipientBalanceBefore = usdc.balanceOf(recipient);

        vm.prank(address(flywheel));
        Flywheel.Payout memory returnedPayout =
            bridgeReferralFees.onWithdrawFunds(address(this), bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(returnedPayout.recipient, recipient, "Returned payout recipient should match expected");
        assertEq(returnedPayout.amount, amount, "Returned payout amount should match expected");
        assertEq(returnedPayout.extraData, extraData, "Returned payout extraData should match expected");
    }
}
