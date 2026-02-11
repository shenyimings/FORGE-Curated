// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Constants} from "../../../src/Constants.sol";
import {Flywheel} from "../../../src/Flywheel.sol";
import {FlywheelTest} from "../../lib/FlywheelTestBase.sol";

import {FailingERC20} from "../../lib/mocks/FailingERC20.sol";
import {RevertingReceiver} from "../../lib/mocks/RevertingReceiver.sol";

/// @title WithdrawFundsTest
/// @notice Tests for Flywheel.withdrawFunds
contract WithdrawFundsTest is FlywheelTest {
    function setUp() public {
        setUpFlywheelBase();
    }
    /// @dev Expects CampaignDoesNotExist
    /// @dev Reverts when campaign does not exist
    /// @param nonExistentCampaign Campaign address

    function test_reverts_whenCampaignDoesNotExist(address nonExistentCampaign) public {
        vm.assume(nonExistentCampaign != campaign);
        address recipient = makeAddr("recipient");
        uint256 amount = 1000;

        Flywheel.Payout memory payout = Flywheel.Payout({recipient: recipient, amount: amount, extraData: "withdraw"});
        bytes memory hookData = abi.encode(payout);

        vm.expectRevert(Flywheel.CampaignDoesNotExist.selector);
        flywheel.withdrawFunds(nonExistentCampaign, address(mockToken), hookData);
    }

    /// @dev Expects ZeroAmount
    /// @dev Reverts on zero amount
    function test_reverts_whenZeroAmount() public {
        // Activate campaign manually (manager can update status)
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        address recipient = makeAddr("recipient");

        vm.expectRevert(Flywheel.ZeroAmount.selector);
        ownerWithdraw(campaign, address(mockToken), recipient, 0); // Zero amount should revert
    }

    /// @dev Expects SendFailed when Campaign.sendTokens returns false (ERC20)
    /// @param amount Withdraw amount
    /// @param recipient Recipient address
    function test_reverts_whenSendFailed_ERC20(uint256 amount, address recipient) public {
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);

        // Activate campaign manually (manager can update status)
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        // Fund campaign with the failing token
        failingERC20.mint(campaign, amount);

        Flywheel.Payout memory payout = Flywheel.Payout({recipient: recipient, amount: amount, extraData: "withdraw"});
        bytes memory hookData = abi.encode(payout);

        vm.expectRevert(abi.encodeWithSelector(Flywheel.SendFailed.selector, address(failingERC20), recipient, amount));
        vm.prank(owner); // Campaign owner calls withdraw
        flywheel.withdrawFunds(campaign, address(failingERC20), hookData);
    }

    /// @dev Expects SendFailed when Campaign.sendTokens returns false (native token)
    /// @param amount Withdraw amount
    function test_reverts_whenSendFailed_native(uint256 amount) public {
        address recipient = address(revertingRecipient);
        amount = boundToValidAmount(amount);

        // Activate campaign manually (manager can update status)
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        // Fund campaign with native token
        vm.deal(campaign, amount);

        Flywheel.Payout memory payout = Flywheel.Payout({recipient: recipient, amount: amount, extraData: "withdraw"});
        bytes memory hookData = abi.encode(payout);

        vm.expectRevert(abi.encodeWithSelector(Flywheel.SendFailed.selector, Constants.NATIVE_TOKEN, recipient, amount));
        vm.prank(owner); // Campaign owner calls withdraw
        flywheel.withdrawFunds(campaign, Constants.NATIVE_TOKEN, hookData);
    }

    /// @dev Expects InsufficientCampaignFunds
    /// @dev Verifies that withdraw funds enforces solvency before FINALIZED
    /// @dev Solvency incorporates both total allocated payouts and total allocated fees
    /// @param amount Withdraw amount
    function test_reverts_whenCampaignIsNotSolvent_beforeFinalized(uint256 amount) public {
        address recipient = boundToValidPayableAddress(makeAddr("recipient"));
        amount = boundToValidAmount(amount);
        vm.assume(amount > 1); // Need at least 2 to create insolvency

        // Activate campaign manually (manager can update status)
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        // Fund campaign with exact amount
        fundCampaign(campaign, amount, address(this));

        // Allocate all funds to create tight solvency
        address payoutRecipient = makeAddr("payoutRecipient");
        Flywheel.Payout[] memory payouts = buildSinglePayout(payoutRecipient, amount, "payout");
        managerAllocate(campaign, address(mockToken), payouts);

        // Try to withdraw 1 token - this would make campaign insolvent
        // Balance: amount, Allocated: amount, Withdraw: 1 -> Balance after: amount-1 < amount (allocated)
        Flywheel.Payout memory withdrawPayout =
            Flywheel.Payout({recipient: recipient, amount: 1, extraData: "withdraw"});
        bytes memory hookData = abi.encode(withdrawPayout);

        vm.expectRevert(Flywheel.InsufficientCampaignFunds.selector);
        vm.prank(owner); // Campaign owner calls withdraw
        flywheel.withdrawFunds(campaign, address(mockToken), hookData);
    }

    /// @dev Expects InsufficientCampaignFunds
    /// @dev Respects solvency rule in FINALIZED state (ignore payouts, require fees only)
    /// @param amount Withdraw amount
    /// @param recipient Recipient address
    /// @param feeRecipient Fee recipient address
    function test_reverts_whenCampaignIsNotSolvent_finalizedIgnoresPayouts(
        uint256 amount,
        address recipient,
        address feeRecipient
    ) public {
        recipient = boundToValidPayableAddress(recipient);
        feeRecipient = boundToValidPayableAddress(feeRecipient);
        vm.assume(recipient != feeRecipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        vm.assume(feeRecipient != campaign); // Avoid campaign as fee recipient
        amount = boundToValidAmount(amount);
        vm.assume(amount > 1); // Need at least 2 to create insolvency

        // Activate campaign manually (manager can update status)
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        // Fund campaign with exact amount
        fundCampaign(campaign, amount, address(this));

        // Allocate fees (these must be respected even in FINALIZED state)
        bytes32 feeKey = bytes32(bytes20(feeRecipient));
        Flywheel.Distribution[] memory feeAllocations = buildSingleFee(feeRecipient, feeKey, amount, "fee");
        vm.prank(manager);
        flywheel.send(campaign, address(mockToken), abi.encode(new Flywheel.Payout[](0), feeAllocations, false));

        // Move campaign to FINALIZED state (first FINALIZING, then FINALIZED)
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");

        // Try to withdraw 1 token - this would make campaign insolvent
        // Even though payouts are ignored in FINALIZED, fees still count
        // Balance: amount, Allocated fees: amount, Withdraw: 1 -> Balance after: amount-1 < amount (allocated fees)
        Flywheel.Payout memory withdrawPayout =
            Flywheel.Payout({recipient: recipient, amount: 1, extraData: "withdraw"});
        bytes memory hookData = abi.encode(withdrawPayout);

        vm.expectRevert(Flywheel.InsufficientCampaignFunds.selector);
        vm.prank(owner); // Campaign owner calls withdraw
        flywheel.withdrawFunds(campaign, address(mockToken), hookData);
    }

    /// @dev Verifies withdrawal succeeds (ERC20)
    /// @param recipient Recipient address
    /// @param amount Withdraw amount
    function test_succeeds_withERC20(address recipient, uint256 amount) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        amount = boundToValidAmount(amount);
        vm.assume(amount > 0);

        // Activate campaign manually (manager can update status)
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        // Fund campaign with more than withdraw amount to maintain solvency
        fundCampaign(campaign, amount * 2, address(this));

        Flywheel.Payout memory withdrawPayout =
            Flywheel.Payout({recipient: recipient, amount: amount, extraData: "withdraw_data"});
        bytes memory hookData = abi.encode(withdrawPayout);

        uint256 initialRecipientBalance = mockToken.balanceOf(recipient);
        uint256 initialCampaignBalance = mockToken.balanceOf(campaign);

        vm.prank(owner); // Campaign owner calls withdraw
        flywheel.withdrawFunds(campaign, address(mockToken), hookData);

        // Verify withdrawal was successful
        assertEq(mockToken.balanceOf(recipient), initialRecipientBalance + amount);
        assertEq(mockToken.balanceOf(campaign), initialCampaignBalance - amount);
    }

    /// @dev Verifies withdrawal succeeds (native token)
    /// @param recipient Recipient address
    /// @param amount Withdraw amount
    function test_succeeds_withNative(address recipient, uint256 amount) public {
        // Use a simple, clean address to avoid any edge cases
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        amount = boundToValidAmount(amount);
        vm.assume(amount > 0);

        // Activate campaign manually (manager can update status)
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        // Fund campaign with native token (more than withdraw amount for solvency)
        vm.deal(campaign, amount * 2);

        Flywheel.Payout memory withdrawPayout =
            Flywheel.Payout({recipient: recipient, amount: amount, extraData: "withdraw_data"});
        bytes memory hookData = abi.encode(withdrawPayout);

        uint256 initialRecipientBalance = recipient.balance;
        uint256 initialCampaignBalance = campaign.balance;

        vm.prank(owner); // Campaign owner calls withdraw
        flywheel.withdrawFunds(campaign, Constants.NATIVE_TOKEN, hookData);

        // Verify withdrawal was successful
        assertEq(recipient.balance, initialRecipientBalance + amount);
        assertEq(campaign.balance, initialCampaignBalance - amount);
    }

    /// @dev Verifies that the FundsWithdrawn event is emitted
    /// @param recipient Recipient address
    /// @param amount Withdraw amount
    /// @param eventTestData Extra data for the payout to attach in events
    function test_emitsFundsWithdrawnEvent(address recipient, uint256 amount, bytes memory eventTestData) public {
        recipient = boundToValidPayableAddress(recipient);
        vm.assume(recipient != campaign); // Avoid self-transfers
        amount = boundToValidAmount(amount);
        vm.assume(amount > 0);

        // Activate campaign manually (manager can update status)
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        // Fund campaign with more than withdraw amount to maintain solvency
        fundCampaign(campaign, amount * 2, address(this));

        Flywheel.Payout memory withdrawPayout =
            Flywheel.Payout({recipient: recipient, amount: amount, extraData: eventTestData});
        bytes memory hookData = abi.encode(withdrawPayout);

        vm.expectEmit(true, true, true, true);
        emit Flywheel.FundsWithdrawn(campaign, address(mockToken), recipient, amount, eventTestData);

        vm.prank(owner); // Campaign owner calls withdraw
        flywheel.withdrawFunds(campaign, address(mockToken), hookData);
    }
}
