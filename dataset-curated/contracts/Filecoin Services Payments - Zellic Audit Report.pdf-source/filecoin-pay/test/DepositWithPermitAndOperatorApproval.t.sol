// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Payments} from "../src/Payments.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PaymentsTestHelpers} from "./helpers/PaymentsTestHelpers.sol";
import {BaseTestHelper} from "./helpers/BaseTestHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {Errors} from "../src/Errors.sol";

contract DepositWithPermitAndOperatorApproval is Test, BaseTestHelper {
    MockERC20 testToken;
    PaymentsTestHelpers helper;
    Payments payments;

    uint256 constant DEPOSIT_AMOUNT = 1000 ether;
    uint256 constant RATE_ALLOWANCE = 100 ether;
    uint256 constant LOCKUP_ALLOWANCE = 1000 ether;
    uint256 constant MAX_LOCKUP_PERIOD = 100;
    uint256 internal constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        helper = new PaymentsTestHelpers();
        helper.setupStandardTestEnvironment();
        payments = helper.payments();

        testToken = helper.testToken();
    }

    function testDepositWithPermitAndOperatorApproval_HappyPath() public {
        helper.makeDepositWithPermitAndOperatorApproval(
            user1Sk, DEPOSIT_AMOUNT, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD
        );
    }

    function testDepositWithPermitAndOperatorApproval_ZeroAmount() public {
        helper.makeDepositWithPermitAndOperatorApproval(
            user1Sk, 0, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD
        );
    }

    function testDepositWithPermitAndOperatorApproval_MultipleDeposits() public {
        uint256 firstDepositAmount = 500 ether;
        uint256 secondDepositAmount = 300 ether;

        helper.makeDepositWithPermitAndOperatorApproval(
            user1Sk, firstDepositAmount, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD
        );
        helper.makeDepositWithPermitAndOperatorApproval(
            user1Sk, secondDepositAmount, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD
        );
    }

    function testDepositWithPermitAndOperatorApproval_InvalidPermitReverts() public {
        helper.expectInvalidPermitAndOperatorApprovalToRevert(
            user1Sk, DEPOSIT_AMOUNT, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD
        );
    }

    // SECTION: Deposit With Permit And Increase Operator Approval Tests

    function testDepositWithPermitAndIncreaseOperatorApproval_HappyPath() public {
        // Step 1: First establish initial operator approval with deposit
        helper.makeDepositWithPermitAndOperatorApproval(
            user1Sk, DEPOSIT_AMOUNT, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD
        );

        // Step 2: Verify initial approval state
        (bool isApproved, uint256 initialRateAllowance, uint256 initialLockupAllowance,,,) =
            payments.operatorApprovals(address(testToken), USER1, OPERATOR);
        assertEq(isApproved, true);
        assertEq(initialRateAllowance, RATE_ALLOWANCE);
        assertEq(initialLockupAllowance, LOCKUP_ALLOWANCE);

        // Step 3: Prepare for the increase operation
        uint256 additionalDeposit = 500 ether;
        uint256 rateIncrease = 50 ether;
        uint256 lockupIncrease = 500 ether;

        // Give USER1 more tokens for the additional deposit
        testToken.mint(USER1, additionalDeposit);

        // Get permit signature for the additional deposit
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            helper.getPermitSignature(user1Sk, USER1, address(payments), additionalDeposit, deadline);

        // Record initial account state
        (uint256 initialFunds,,,) = payments.accounts(address(testToken), USER1);

        // Step 4: Execute depositWithPermitAndIncreaseOperatorApproval
        vm.startPrank(USER1);
        payments.depositWithPermitAndIncreaseOperatorApproval(
            address(testToken), USER1, additionalDeposit, deadline, v, r, s, OPERATOR, rateIncrease, lockupIncrease
        );
        vm.stopPrank();

        // Step 5: Verify results
        // Check deposit was successful
        (uint256 finalFunds,,,) = payments.accounts(address(testToken), USER1);
        assertEq(finalFunds, initialFunds + additionalDeposit);

        // Check operator approval was increased
        (, uint256 finalRateAllowance, uint256 finalLockupAllowance,,,) =
            payments.operatorApprovals(address(testToken), USER1, OPERATOR);
        assertEq(finalRateAllowance, initialRateAllowance + rateIncrease);
        assertEq(finalLockupAllowance, initialLockupAllowance + lockupIncrease);
    }

    function testDepositWithPermitAndIncreaseOperatorApproval_ZeroIncrease() public {
        // First establish initial operator approval with deposit
        helper.makeDepositWithPermitAndOperatorApproval(
            user1Sk, DEPOSIT_AMOUNT, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD
        );

        // Verify initial approval state
        (bool isApproved, uint256 initialRateAllowance, uint256 initialLockupAllowance,,,) =
            payments.operatorApprovals(address(testToken), USER1, OPERATOR);
        assertEq(isApproved, true);
        assertEq(initialRateAllowance, RATE_ALLOWANCE);
        assertEq(initialLockupAllowance, LOCKUP_ALLOWANCE);

        // Setup for additional deposit with zero increases
        uint256 additionalDeposit = 500 ether;
        testToken.mint(USER1, additionalDeposit);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            helper.getPermitSignature(user1Sk, USER1, address(payments), additionalDeposit, deadline);

        (uint256 initialFunds,,,) = payments.accounts(address(testToken), USER1);

        // Execute with zero increases
        vm.startPrank(USER1);
        payments.depositWithPermitAndIncreaseOperatorApproval(
            address(testToken),
            USER1,
            additionalDeposit,
            deadline,
            v,
            r,
            s,
            OPERATOR,
            0, // Zero rate increase
            0 // Zero lockup increase
        );
        vm.stopPrank();

        // Verify deposit occurred but allowances unchanged
        (uint256 finalFunds,,,) = payments.accounts(address(testToken), USER1);
        assertEq(finalFunds, initialFunds + additionalDeposit);

        (, uint256 finalRateAllowance, uint256 finalLockupAllowance,,,) =
            payments.operatorApprovals(address(testToken), USER1, OPERATOR);
        assertEq(finalRateAllowance, initialRateAllowance); // No change
        assertEq(finalLockupAllowance, initialLockupAllowance); // No change
    }

    function testDepositWithPermitAndIncreaseOperatorApproval_InvalidPermit() public {
        // First establish initial operator approval with deposit
        helper.makeDepositWithPermitAndOperatorApproval(
            user1Sk, DEPOSIT_AMOUNT, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD
        );

        // Setup for additional deposit with invalid permit
        uint256 additionalDeposit = 500 ether;
        testToken.mint(USER1, additionalDeposit);

        uint256 deadline = block.timestamp + 1 hours;

        // Create invalid permit signature (wrong private key)
        (uint8 v, bytes32 r, bytes32 s) =
            helper.getPermitSignature(user2Sk, USER1, address(payments), additionalDeposit, deadline);

        vm.startPrank(USER1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC2612InvalidSigner(address,address)",
                vm.addr(user2Sk), // Wrong signer address
                USER1 // Intended recipient
            )
        );
        payments.depositWithPermitAndIncreaseOperatorApproval(
            address(testToken), USER1, additionalDeposit, deadline, v, r, s, OPERATOR, 50 ether, 500 ether
        );
        vm.stopPrank();
    }

    function testDepositWithPermitAndIncreaseOperatorApproval_WithExistingUsage() public {
        // First establish initial operator approval with deposit
        helper.makeDepositWithPermitAndOperatorApproval(
            user1Sk, DEPOSIT_AMOUNT, OPERATOR, RATE_ALLOWANCE, LOCKUP_ALLOWANCE, MAX_LOCKUP_PERIOD
        );

        // Create rail and use some allowance to establish existing usage
        uint256 railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);
        uint256 paymentRate = 30 ether;
        uint256 lockupFixed = 200 ether;

        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, paymentRate, 0);
        payments.modifyRailLockup(railId, 0, lockupFixed);
        vm.stopPrank();

        // Verify some allowance is used
        (, uint256 preRateAllowance, uint256 preLockupAllowance, uint256 preRateUsage, uint256 preLockupUsage,) =
            payments.operatorApprovals(address(testToken), USER1, OPERATOR);
        assertEq(preRateUsage, paymentRate);
        assertEq(preLockupUsage, lockupFixed);

        // Setup for additional deposit with increase
        uint256 additionalDeposit = 500 ether;
        uint256 rateIncrease = 70 ether;
        uint256 lockupIncrease = 800 ether;

        testToken.mint(USER1, additionalDeposit);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            helper.getPermitSignature(user1Sk, USER1, address(payments), additionalDeposit, deadline);

        (uint256 initialFunds,,,) = payments.accounts(address(testToken), USER1);

        // Execute increase with existing usage
        vm.startPrank(USER1);
        payments.depositWithPermitAndIncreaseOperatorApproval(
            address(testToken), USER1, additionalDeposit, deadline, v, r, s, OPERATOR, rateIncrease, lockupIncrease
        );
        vm.stopPrank();

        // Verify results
        (uint256 finalFunds,,,) = payments.accounts(address(testToken), USER1);
        assertEq(finalFunds, initialFunds + additionalDeposit);

        (, uint256 finalRateAllowance, uint256 finalLockupAllowance, uint256 finalRateUsage, uint256 finalLockupUsage,)
        = payments.operatorApprovals(address(testToken), USER1, OPERATOR);
        assertEq(finalRateAllowance, preRateAllowance + rateIncrease);
        assertEq(finalLockupAllowance, preLockupAllowance + lockupIncrease);
        assertEq(finalRateUsage, preRateUsage); // Usage unchanged
        assertEq(finalLockupUsage, preLockupUsage); // Usage unchanged
    }
}
