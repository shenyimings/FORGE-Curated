// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Payments} from "../src/Payments.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PaymentsTestHelpers} from "./helpers/PaymentsTestHelpers.sol";
import {BaseTestHelper} from "./helpers/BaseTestHelper.sol";
import {console} from "forge-std/console.sol";

contract AccountLockupSettlementTest is Test, BaseTestHelper {
    PaymentsTestHelpers helper;
    Payments payments;

    // Define constants
    uint256 internal constant DEPOSIT_AMOUNT = 100 ether;
    uint256 internal constant MAX_LOCKUP_PERIOD = 100;

    function setUp() public {
        helper = new PaymentsTestHelpers();
        helper.setupStandardTestEnvironment();
        payments = helper.payments();
        // Setup operator approval for potential rails
        helper.setupOperatorApproval(
            USER1,
            OPERATOR,
            10 ether, // rateAllowance
            100 ether, // lockupAllowance
            MAX_LOCKUP_PERIOD // maxLockupPeriod
        );
    }

    function testSettlementWithNoLockupRate() public {
        // Setup: deposit funds
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // No rails created, so lockup rate should be 0

        // Advance blocks to create a settlement gap without a rate
        helper.advanceBlocks(10);

        // Trigger settlement with a new deposit
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Verify settlement occurred
        helper.assertAccountState(USER1, DEPOSIT_AMOUNT * 2, 0, 0, block.number);
    }

    function testSimpleLockupAccumulation() public {
        // Setup: deposit funds
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Define a lockup rate
        uint256 lockupRate = 2 ether;
        uint256 lockupPeriod = 2;

        // Create rail with the desired rate
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            lockupRate, // payment rate
            lockupPeriod, // lockup period
            0, // no fixed lockup
            address(0), // no fixed lockup
            SERVICE_FEE_RECIPIENT // operator comission fee receiver
        );
        assertEq(railId, 1);

        // Note: Settlement begins at the current block
        // Advance blocks to create a settlement gap
        uint256 elapsedBlocks = 5;
        helper.advanceBlocks(elapsedBlocks);

        // Trigger settlement with a new deposit
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // The correct expected value is:
        uint256 initialLockup = lockupRate * lockupPeriod;
        uint256 accumulatedLockup = lockupRate * elapsedBlocks;
        uint256 expectedLockup = initialLockup + accumulatedLockup;

        // Verify settlement occurred
        helper.assertAccountState(USER1, DEPOSIT_AMOUNT * 2, expectedLockup, lockupRate, block.number);
    }

    function testPartialSettlement() public {
        uint256 lockupRate = 20 ether;

        helper.makeDeposit(
            USER1,
            USER1,
            DEPOSIT_AMOUNT / 2 // 50
        );

        // Create rail with the high rate (this will set the railway's settledUpTo to the current block)
        helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            lockupRate, // Very high payment rate (20 ether per block)
            1, // lockup period
            0, // no fixed lockup
            address(0), // no fixed lockup
            SERVICE_FEE_RECIPIENT
        );

        // When a rail is created, its settledUpTo is set to the current block
        // Initial account lockup value should be lockupRate * lockupPeriod = 20 ether * 1 = 20 ether
        // Initial funds are DEPOSIT_AMOUNT / 2 = 50 ether

        // Advance many blocks to exceed available funds
        uint256 advancedBlocks = 10;
        helper.advanceBlocks(advancedBlocks);

        // Deposit additional funds, which will trigger settlement
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT / 2);

        // Verify partial settlement
        uint256 expectedSettlementBlock = 5; // lockupRate is 20, so we only have enough funds to pay for 5 epochs)
        uint256 expectedLockup = DEPOSIT_AMOUNT;

        // Verify settlement state using helper function
        helper.assertAccountState(
            USER1,
            DEPOSIT_AMOUNT, // expected funds
            expectedLockup, // expected lockup
            lockupRate, // expected lockup rate
            expectedSettlementBlock // expected settlement block
        );
    }

    function testSettlementAfterGap() public {
        helper.makeDeposit(
            USER1,
            USER1,
            DEPOSIT_AMOUNT * 2 // 200 ether
        );

        uint256 lockupRate = 1 ether; // 1 token per block
        uint256 lockupPeriod = 30;
        uint256 initialLockup = 10 ether;

        // Create rail
        helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            lockupRate, // 1 token per block
            lockupPeriod, // Lockup period of 30 blocks
            initialLockup, // initial fixed lockup of 10 ether
            address(0), // no fixed lockup
            SERVICE_FEE_RECIPIENT // operator comission fee receiver
        );

        // Roll forward many blocks
        helper.advanceBlocks(30);

        // Trigger settlement with a new deposit
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Verify settlement occurred
        uint256 expectedLockup = initialLockup + (lockupRate * 30) + (lockupRate * lockupPeriod); // accumulated lockup // future lockup

        // Verify settlement occurred
        helper.assertAccountState(
            USER1,
            DEPOSIT_AMOUNT * 3, // expected funds
            expectedLockup, // expected lockup
            lockupRate, // expected lockup rate
            block.number // expected settlement block
        );
    }

    function testSettlementInvariants() public {
        // Setup: deposit a specific amount
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Scenario 1: Lockup exactly matches funds by creating a rail with fixed lockup
        // exactly matching the deposit amount

        // Create a rail with fixed lockup = all available funds
        helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            0, // no payment rate
            10, // Lockup period
            DEPOSIT_AMOUNT, // fixed lockup equal to all funds
            address(0), // no fixed lockup
            SERVICE_FEE_RECIPIENT // operator comission fee receiver
        );

        // Verify the account state
        // Verify the account state using helper function
        helper.assertAccountState(
            USER1,
            DEPOSIT_AMOUNT,
            DEPOSIT_AMOUNT,
            0, // no payment rate
            block.number
        );

        helper.makeDeposit(USER1, USER1, 1); // Adding more funds

        // Scenario 2: Verify we can't create a situation where lockup > funds
        // We'll try to create a rail with an impossibly high fixed lockup

        // Increase operator approval allowance

        helper.setupOperatorApproval(
            USER1,
            OPERATOR,
            0, // no rate allowance needed
            DEPOSIT_AMOUNT * 3, // much higher lockup allowance
            MAX_LOCKUP_PERIOD // max lockup period
        );

        // Try to set up a rail with lockup > funds which should fail
        vm.startPrank(OPERATOR);
        uint256 railId = payments.createRail(
            address(helper.testToken()),
            USER1,
            USER2,
            address(0),
            0,
            SERVICE_FEE_RECIPIENT // operator comission fee receiver
        );

        // This should fail because lockupFixed > available funds
        vm.expectRevert("invariant failure: insufficient funds to cover lockup after function execution");
        payments.modifyRailLockup(railId, 10, DEPOSIT_AMOUNT * 2);
        vm.stopPrank();
    }

    function testWithdrawWithLockupSettlement() public {
        helper.makeDeposit(
            USER1,
            USER1,
            DEPOSIT_AMOUNT * 2 // Deposit 200 ether
        );
        // Set a lockup rate and an existing lockup via a rail
        uint256 lockupRate = 1 ether;
        uint256 initialLockup = 50 ether;
        uint256 lockupPeriod = 10;

        // Create rail with fixed + rate-based lockup
        helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            lockupRate, // 1 ether per block
            lockupPeriod, // Lockup period of 10 blocks
            initialLockup, // 50 ether fixed lockup
            address(0), // no fixed lockup
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Total lockup at rail creation: 50 ether fixed + (1 ether * 10 blocks) = 60 ether
        // Available for withdrawal at creation: 200 ether - 60 ether = 140 ether

        // Try to withdraw more than available (should fail)
        helper.expectWithdrawalToFail(USER1, 140 ether, 150 ether);

        // Withdraw exactly the available amount (should succeed and also settle account lockup)
        helper.makeWithdrawal(USER1, 140 ether);

        // Verify account state after withdrawal
        // Remaining funds: 200 - 140 = 60 ether
        // Remaining lockup: 60 ether (unchanged because no blocks passed)
        helper.assertAccountState(
            USER1,
            60 ether, // expected funds
            60 ether, // expected lockup
            lockupRate, // expected lockup rate
            block.number // expected settlement block
        );
    }
}
