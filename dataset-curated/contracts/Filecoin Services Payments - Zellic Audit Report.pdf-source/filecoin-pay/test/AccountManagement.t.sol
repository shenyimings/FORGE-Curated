// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Payments} from "../src/Payments.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PaymentsTestHelpers} from "./helpers/PaymentsTestHelpers.sol";
import {BaseTestHelper} from "./helpers/BaseTestHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Errors} from "../src/Errors.sol";

contract AccountManagementTest is Test, BaseTestHelper {
    PaymentsTestHelpers helper;
    Payments payments;

    uint256 internal constant DEPOSIT_AMOUNT = 100 ether;
    uint256 internal constant INITIAL_BALANCE = 1000 ether;
    uint256 internal constant MAX_LOCKUP_PERIOD = 100;

    function setUp() public {
        // Create test helpers and setup environment
        helper = new PaymentsTestHelpers();
        helper.setupStandardTestEnvironment();
        payments = helper.payments();
    }

    function testBasicDeposit() public {
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);
    }

    function testNativeDeposit() public {
        helper.makeNativeDeposit(USER1, USER1, DEPOSIT_AMOUNT);
    }

    function testMultipleDeposits() public {
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT + 1);
    }

    function testDepositToAnotherUser() public {
        helper.makeDeposit(USER1, USER2, DEPOSIT_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT WITH PERMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositWithPermit() public {
        helper.makeDepositWithPermit(user1Sk, USER1, DEPOSIT_AMOUNT);
    }

    function testDepositWithPermitExpiredPermitReverts() public {
        helper.expectExpiredPermitToRevert(user1Sk, USER1, DEPOSIT_AMOUNT);
    }

    function testDepositWithPermitZeroAmountNoEffect() public {
        helper.makeDepositWithPermit(user1Sk, USER1, 0);
    }

    function testDepositWithPermitMultiple() public {
        helper.makeDepositWithPermit(user1Sk, USER1, DEPOSIT_AMOUNT);
        helper.makeDepositWithPermit(user1Sk, USER1, DEPOSIT_AMOUNT);
    }

    function testDepositWithPermitRevertsForNativeToken() public {
        helper.expectNativeTokenDepositWithPermitToRevert(user1Sk, USER1, DEPOSIT_AMOUNT);
    }

    function testDepositWithPermitInvalidPermitReverts() public {
        helper.expectInvalidPermitToRevert(user1Sk, USER1, DEPOSIT_AMOUNT);
    }

    function testDepositWithPermitToAnotherUserReverts() public {
        helper.expectDepositWithPermitToAnotherUserToRevert(user1Sk, USER2, DEPOSIT_AMOUNT);
    }

    function testNativeDepositWithInsufficientNativeTokens() public {
        vm.startPrank(USER1);

        // Test zero token address
        vm.expectRevert(
            abi.encodeWithSelector(Errors.MustSendExactNativeAmount.selector, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT - 1)
        );
        payments.deposit{value: DEPOSIT_AMOUNT - 1}(address(0), USER1, DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function testDepositWithZeroRecipient() public {
        address testTokenAddr = address(helper.testToken());
        vm.startPrank(USER1);

        // Using straightforward expectRevert without message
        vm.expectRevert();
        payments.deposit(testTokenAddr, address(0), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function testDepositWithInsufficientBalance() public {
        vm.startPrank(USER1);
        vm.expectRevert();
        helper.makeDeposit(USER1, USER1, INITIAL_BALANCE + 1);
        vm.stopPrank();
    }

    function testDepositWithInsufficientAllowance() public {
        // Reset allowance to a small amount
        vm.startPrank(USER1);
        IERC20 testToken = helper.testToken();
        testToken.approve(address(payments), DEPOSIT_AMOUNT / 2);

        // Attempt deposit with more than approved
        vm.expectRevert();
        payments.deposit(address(testToken), USER1, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testBasicWithdrawal() public {
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);
        helper.makeWithdrawal(USER1, DEPOSIT_AMOUNT / 2);
    }

    function testNativeWithdrawal() public {
        helper.makeNativeDeposit(USER1, USER1, DEPOSIT_AMOUNT);
        helper.makeNativeWithdrawal(USER1, DEPOSIT_AMOUNT / 2);
    }

    function testMultipleWithdrawals() public {
        // Setup: deposit first
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Test multiple withdrawals
        helper.makeWithdrawal(USER1, DEPOSIT_AMOUNT / 4);
        helper.makeWithdrawal(USER1, DEPOSIT_AMOUNT / 4);
    }

    function testWithdrawToAnotherAddress() public {
        // Setup: deposit first
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Test withdrawTo
        helper.makeWithdrawalTo(USER1, USER2, DEPOSIT_AMOUNT / 2);
    }

    function testWithdrawEntireBalance() public {
        // Setup: deposit first
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Withdraw everything
        helper.makeWithdrawal(USER1, DEPOSIT_AMOUNT);
    }

    function testWithdrawExcessAmount() public {
        // Setup: deposit first
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Try to withdraw more than available
        helper.expectWithdrawalToFail(USER1, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT + 1);
    }

    function testWithdrawToWithZeroRecipient() public {
        address testTokenAddr = address(helper.testToken());
        vm.startPrank(USER1);

        // Test zero recipient address
        vm.expectRevert();
        payments.withdrawTo(testTokenAddr, address(0), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          LOCKUP/SETTLEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testWithdrawWithLockedFunds() public {
        // First, deposit funds
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Define locked amount to be half of the deposit
        uint256 lockedAmount = DEPOSIT_AMOUNT / 2;

        // Create a rail with a fixed lockup amount to achieve the required locked funds
        helper.setupOperatorApproval(
            USER1,
            OPERATOR,
            100 ether, // rateAllowance
            lockedAmount, // lockupAllowance exactly matches what we need
            MAX_LOCKUP_PERIOD // max lockup period
        );

        // Create rail with the fixed lockup
        helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            0, // no payment rate
            0, // no lockup period
            lockedAmount, // fixed lockup of half the deposit
            address(0), // no fixed lockup
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Verify lockup worked by checking account state
        helper.assertAccountState(
            USER1,
            DEPOSIT_AMOUNT, // expected funds
            lockedAmount, // expected lockup
            0, // expected rate (not set in this test)
            block.number // expected last settled
        );

        // Try to withdraw more than unlocked funds
        helper.expectWithdrawalToFail(USER1, DEPOSIT_AMOUNT - lockedAmount, DEPOSIT_AMOUNT);

        // Should be able to withdraw up to unlocked amount
        helper.makeWithdrawal(USER1, DEPOSIT_AMOUNT - lockedAmount);
    }

    function testSettlementDuringDeposit() public {
        // First deposit
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Setup operator approval with sufficient allowances
        helper.setupOperatorApproval(
            USER1,
            OPERATOR,
            100 ether, // rateAllowance
            1000 ether, // lockupAllowance
            MAX_LOCKUP_PERIOD // max lockup period
        );

        uint256 lockupRate = 0.5 ether; // 0.5 token per block

        // Create a rail that will set the lockup rate to 0.5 ether per block
        // This creates a lockup rate of 0.5 ether/block for the account
        helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            lockupRate, // payment rate (creates lockup rate)
            10, // lockup period
            0, // no fixed lockup
            address(0), // no fixed lockup
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Create a second rail to get to 1 ether lockup rate on the account
        helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            lockupRate, // payment rate (creates another 0.5 ether/block lockup rate)
            10, // lockup period
            0, // no fixed lockup
            address(0), // no fixed lockup
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance 10 blocks to create settlement gap
        helper.advanceBlocks(10);

        // Make another deposit to trigger settlement
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Check all states match expectations using assertAccountState helper
        helper.assertAccountState(
            USER1,
            DEPOSIT_AMOUNT * 2, // expected funds
            20 ether, // expected lockup (2 rails × 0.5 ether per block × 10 blocks + future lockup of 10 ether)
            lockupRate * 2, // expected rate (2 * 0.5 ether)
            block.number // expected last settled
        );
    }

    /*//////////////////////////////////////////////////////////////
                          ACCOUNT INFO TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetAccountInfoNoLockups() public {
        // Setup: deposit funds
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Get account info
        (uint256 fundedUntil, uint256 totalBalance, uint256 availableBalance, uint256 lockupRate) =
            payments.getAccountInfoIfSettled(address(helper.testToken()), USER1);

        // Verify account state
        assertEq(totalBalance, DEPOSIT_AMOUNT, "total balance mismatch");
        assertEq(availableBalance, DEPOSIT_AMOUNT, "available balance mismatch");
        assertEq(lockupRate, 0, "lockup rate should be 0");
        assertEq(fundedUntil, type(uint256).max, "funded until should be max");
    }

    function testGetAccountInfoWithFixedLockup() public {
        // Setup: deposit funds
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Setup operator approval
        helper.setupOperatorApproval(USER1, OPERATOR, 100 ether, DEPOSIT_AMOUNT, MAX_LOCKUP_PERIOD);

        // Create rail with fixed lockup
        uint256 fixedLockup = DEPOSIT_AMOUNT / 2;
        helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            0,
            0,
            fixedLockup,
            address(0),
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Get account info
        (uint256 fundedUntil, uint256 totalBalance, uint256 availableBalance, uint256 lockupRate) =
            payments.getAccountInfoIfSettled(address(helper.testToken()), USER1);

        // Verify account state
        assertEq(totalBalance, DEPOSIT_AMOUNT, "total balance mismatch");
        assertEq(availableBalance, DEPOSIT_AMOUNT - fixedLockup, "available balance mismatch");
        assertEq(lockupRate, 0, "lockup rate should be 0");
        assertEq(fundedUntil, type(uint256).max, "funded until should be max with no rate");
    }

    // Helper function to calculate simulated lockup and available balance
    function calculateSimulatedLockupAndBalance(
        uint256 funds,
        uint256 lockupCurrent,
        uint256 lockupRate,
        uint256 lockupLastSettledAt
    ) internal view returns (uint256 simulatedLockupCurrent, uint256 availableBalance) {
        uint256 currentEpoch = block.number;
        uint256 elapsedTime = currentEpoch - lockupLastSettledAt;
        simulatedLockupCurrent = lockupCurrent;

        if (elapsedTime > 0 && lockupRate > 0) {
            uint256 additionalLockup = lockupRate * elapsedTime;

            if (funds >= lockupCurrent + additionalLockup) {
                simulatedLockupCurrent = lockupCurrent + additionalLockup;
            } else {
                uint256 availableFunds = funds - lockupCurrent;
                if (availableFunds > 0) {
                    uint256 fractionalEpochs = availableFunds / lockupRate;
                    simulatedLockupCurrent = lockupCurrent + (lockupRate * fractionalEpochs);
                }
            }
        }

        availableBalance = funds > simulatedLockupCurrent ? funds - simulatedLockupCurrent : 0;
    }

    function testGetAccountInfoWithRateLockup() public {
        // Setup: deposit funds
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Setup operator approval
        helper.setupOperatorApproval(USER1, OPERATOR, 100 ether, DEPOSIT_AMOUNT, MAX_LOCKUP_PERIOD);

        uint256 lockupRate = 1 ether; // 1 token per block
        uint256 lockupPeriod = 10;

        // Create rail with rate lockup
        helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            lockupRate,
            lockupPeriod,
            0,
            address(0),
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance 5 blocks
        helper.advanceBlocks(5);

        // Get raw account data for debugging
        (uint256 funds, uint256 lockupCurrent, uint256 lockupRate2, uint256 lockupLastSettledAt) =
            payments.accounts(address(helper.testToken()), USER1);

        (, uint256 availableBalance) =
            calculateSimulatedLockupAndBalance(funds, lockupCurrent, lockupRate2, lockupLastSettledAt);

        // Get account info
        (uint256 fundedUntil, uint256 totalBalance1, uint256 availableBalance1, uint256 lockupRate1) =
            payments.getAccountInfoIfSettled(address(helper.testToken()), USER1);

        // Verify account state
        assertEq(totalBalance1, DEPOSIT_AMOUNT, "total balance mismatch");
        assertEq(availableBalance1, availableBalance, "available balance mismatch");
        assertEq(lockupRate1, lockupRate, "lockup rate mismatch");
        assertEq(fundedUntil, block.number + (availableBalance / lockupRate), "funded until mismatch");
    }

    function testGetAccountInfoWithPartialSettlement() public {
        // Setup: deposit funds
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Setup operator approval
        helper.setupOperatorApproval(USER1, OPERATOR, 100 ether, DEPOSIT_AMOUNT, MAX_LOCKUP_PERIOD);

        uint256 lockupRate = 2 ether; // 2 tokens per block
        uint256 lockupPeriod = 10;

        // Create rail with rate lockup
        helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            lockupRate,
            lockupPeriod,
            0,
            address(0),
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance blocks to create partial settlement
        helper.advanceBlocks(5);

        // Get raw account data for debugging
        (uint256 funds, uint256 lockupCurrent, uint256 lockupRate2, uint256 lockupLastSettledAt) =
            payments.accounts(address(helper.testToken()), USER1);

        (, uint256 availableBalance) =
            calculateSimulatedLockupAndBalance(funds, lockupCurrent, lockupRate2, lockupLastSettledAt);

        // Get account info
        (uint256 fundedUntil, uint256 totalBalance2, uint256 availableBalance2, uint256 lockupRate3) =
            payments.getAccountInfoIfSettled(address(helper.testToken()), USER1);

        // Verify account state
        assertEq(totalBalance2, DEPOSIT_AMOUNT, "total balance mismatch");
        assertEq(availableBalance2, availableBalance, "available balance mismatch");
        assertEq(lockupRate3, lockupRate, "lockup rate mismatch");
        assertEq(fundedUntil, block.number + (availableBalance / lockupRate), "funded until mismatch");
    }

    function testGetAccountInfoInDebt() public {
        // Setup: deposit funds
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Setup operator approval
        helper.setupOperatorApproval(USER1, OPERATOR, 100 ether, DEPOSIT_AMOUNT, MAX_LOCKUP_PERIOD);

        uint256 lockupRate = 2 ether; // 2 tokens per block
        uint256 lockupPeriod = 10;

        // Create rail with rate lockup
        helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            lockupRate,
            lockupPeriod,
            0,
            address(0),
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance blocks to create debt
        helper.advanceBlocks(60); // This will create debt as 60 * 2 > DEPOSIT_AMOUNT

        // Get account info
        (uint256 fundedUntil, uint256 totalBalance3, uint256 availableBalance3, uint256 lockupRate3) =
            payments.getAccountInfoIfSettled(address(helper.testToken()), USER1);

        // Verify account state
        assertEq(totalBalance3, DEPOSIT_AMOUNT, "total balance mismatch");
        assertEq(availableBalance3, 0, "available balance should be 0");
        assertEq(lockupRate3, lockupRate, "lockup rate mismatch");
        assertTrue(fundedUntil < block.number, "funded until should be in the past");
    }

    function testGetAccountInfoAfterRateChange() public {
        // Setup: deposit funds
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Setup operator approval
        helper.setupOperatorApproval(USER1, OPERATOR, 100 ether, DEPOSIT_AMOUNT, MAX_LOCKUP_PERIOD);

        uint256 initialRate = 1 ether; // 1 token per block
        uint256 lockupPeriod = 10;

        // Create rail with initial rate
        uint256 railId = helper.setupRailWithParameters(
            USER1,
            USER2,
            OPERATOR,
            initialRate,
            lockupPeriod,
            0,
            address(0),
            SERVICE_FEE_RECIPIENT // operator commision receiver
        );

        // Advance some blocks
        helper.advanceBlocks(5);

        // Change the rate
        uint256 newRate = 2 ether; // 2 tokens per block
        vm.prank(OPERATOR);
        payments.modifyRailPayment(railId, newRate, 0);

        // Get raw account data for debugging
        (uint256 funds, uint256 lockupCurrent, uint256 lockupRate2, uint256 lockupLastSettledAt) =
            payments.accounts(address(helper.testToken()), USER1);

        (, uint256 availableBalance) =
            calculateSimulatedLockupAndBalance(funds, lockupCurrent, lockupRate2, lockupLastSettledAt);

        // Get account info
        (uint256 fundedUntil, uint256 totalBalance4, uint256 availableBalance4, uint256 lockupRate4) =
            payments.getAccountInfoIfSettled(address(helper.testToken()), USER1);

        // Verify account state
        assertEq(totalBalance4, DEPOSIT_AMOUNT, "total balance mismatch");
        assertEq(availableBalance4, availableBalance, "available balance mismatch");
        assertEq(lockupRate4, newRate, "lockup rate mismatch");
        assertEq(fundedUntil, block.number + (availableBalance / newRate), "funded until mismatch");
    }
}
