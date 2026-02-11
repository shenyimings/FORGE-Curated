// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdCheats.sol";

import {WBTCDepositManager} from "src/WBTCDepositManager.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {RedemptionLimiter} from "src/RedemptionLimiter.sol";

/// @title WBTCDepositManagerTest
/// @notice Unit tests covering core deposit and redemption flows for the WBTCDepositManager.
/// These tests exercise happy path scenarios as well as a variety of revert conditions.
contract WBTCDepositManagerTest is Test {
    WBTCDepositManager internal manager;
    MockERC20 internal token;
    address internal admin = makeAddr("0xA11CE");
    address internal operator = makeAddr("0x0P3R8"); // test operator address
    address internal receiver = makeAddr("0xBEEF"); // account used for redemption and fee collection

    bytes32 internal id1 = keccak256("deposit-one");
    bytes32 internal id2 = keccak256("deposit-two");

    /// @notice Sets up a fresh contract instance and assigns roles prior to each test
    function setUp() public {
        // Deploy a mock WBTC token with 8 decimals
        token = new MockERC20("Mock Wrapped BTC", "mWBTC", 8);
        // Deploy the deposit manager specifying the admin and WBTC token address
        manager = new WBTCDepositManager(admin, address(token));

        // Grant OPERATOR_ROLE and RECEIVER_ROLE as required
        vm.startPrank(admin);
        manager.grantRole(manager.OPERATOR_ROLE(), operator);
        manager.grantRole(manager.RECEIVER_ROLE(), receiver);
        manager.setDailyLimit(operator, 1_000_000e8);
        vm.stopPrank();

        // Seed the operator with an ample balance of WBTC and approve the manager to pull funds
        uint256 initialBalance = 10_000 * 10 ** 8; // 10,000 WBTC with 8 decimals
        token.mint(operator, initialBalance);
        vm.prank(operator);
        token.approve(address(manager), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     Deposit Tests
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test creating a single deposit successfully
    function testCreateDeposit() public {
        uint192 amount = 1_000 * 10 ** 8; // 1,000 WBTC
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        amounts[0] = amount;

        // Capture the current block timestamp for later assertions
        uint256 ts = block.timestamp;

        // Expect the DepositCreated event to fire with the correct arguments
        vm.expectEmit(true, false, false, true);
        emit WBTCDepositManager.DepositCreated(id1, amount);

        // Have the operator create the deposit
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);

        // Deposit principal and start time should be recorded
        (uint192 principal, uint64 startTime) = manager.deposits(id1);
        assertEq(principal, amount, "principal should equal amount");
        assertEq(startTime, uint64(ts), "start time should match block timestamp");

        // Total principal and product sum should reflect the new deposit
        assertEq(manager.totalPrincipal(), amount, "total principal should equal deposit amount");
        assertEq(manager.principalTimeProductSum(), amount * ts, "time product sum should match amount * ts");

        // Manager's WBTC balance should have increased by the amount
        assertEq(token.balanceOf(address(manager)), amount, "manager balance should equal deposit amount");
        // Operator's WBTC balance should have decreased accordingly
        assertEq(token.balanceOf(operator), 10_000 * 10 ** 8 - amount, "operator balance should have decreased");
    }

    /// @notice Test creating multiple deposits in a single call
    function testCreateMultipleDeposits() public {
        uint192[] memory amounts = new uint192[](2);
        bytes32[] memory ids = new bytes32[](2);
        amounts[0] = 500 * 10 ** 8;
        amounts[1] = 250 * 10 ** 8;
        ids[0] = id1;
        ids[1] = id2;

        uint256 ts = block.timestamp;

        // Call createDeposits
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);

        // Validate each deposit record
        (uint192 principal1, uint64 start1) = manager.deposits(id1);
        (uint192 principal2, uint64 start2) = manager.deposits(id2);
        assertEq(principal1, amounts[0]);
        assertEq(principal2, amounts[1]);
        assertEq(start1, uint64(ts));
        assertEq(start2, uint64(ts));

        // Check aggregated totals
        uint256 total = amounts[0] + amounts[1];
        assertEq(manager.totalPrincipal(), total);
        assertEq(manager.principalTimeProductSum(), total * ts);
        // Manager's balance equals total
        assertEq(token.balanceOf(address(manager)), total);
    }

    /// @notice Reverts when identifier and amount arrays differ in length
    function testCreateDepositsInvalidArgument() public {
        bytes32[] memory ids = new bytes32[](2);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        ids[1] = id2;
        amounts[0] = 1;

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WBTCDepositManager.InvalidArgument.selector));
        manager.createDeposits(ids, amounts, operator);
    }

    /// @notice Reverts when attempting to create a deposit with zero amount
    function testCreateDepositsZeroAmount() public {
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        amounts[0] = 0;

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WBTCDepositManager.ZeroAmount.selector));
        manager.createDeposits(ids, amounts, operator);
    }

    /// @notice Reverts when attempting to create a duplicate deposit
    function testCreateDepositsDepositAlreadyExists() public {
        // First create a deposit
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        amounts[0] = 10;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);

        // Attempt to create the same deposit again
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WBTCDepositManager.DepositAlreadyExists.selector, id1));
        manager.createDeposits(ids, amounts, operator);
    }

    /// @notice Reverts when the underlying ERC20's transferFrom fails
    function testCreateDepositsTransferFromFails() public {
        // Deploy a failing token and new manager
        MockERC20 failingToken = new MockERC20("Fail", "FAIL", 8);
        WBTCDepositManager failingManager = new WBTCDepositManager(admin, address(failingToken));
        vm.startPrank(admin);
        failingManager.grantRole(failingManager.OPERATOR_ROLE(), operator);
        vm.stopPrank();
        // Give operator tokens and approve
        failingToken.mint(operator, 1_000);
        vm.prank(operator);
        failingToken.approve(address(failingManager), 1_000);
        // Force the token to fail on transferFrom
        failingToken.setFailTransferFrom(true);
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        amounts[0] = 1_000;
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                WBTCDepositManager.TransferFromFailed.selector, operator, address(failingManager), uint256(1_000)
            )
        );
        failingManager.createDeposits(ids, amounts, operator);
    }

    /// @notice Creating a deposit from the contract's own source should fail
    function testCreateDepositsFromSelfSourceFails() public {
        // Mint tokens directly to the manager contract so it already holds funds
        uint192 amount = 100 * 10 ** 8;
        token.mint(address(manager), amount);

        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        amounts[0] = amount;

        // Use the manager itself as the source
        vm.expectRevert(abi.encodeWithSelector(WBTCDepositManager.InvalidSource.selector));
        vm.prank(operator);
        manager.createDeposits(ids, amounts, address(manager));
    }

    /// @notice Only addresses with the operator role may create deposits
    function testOnlyOperatorCanCreateDeposits() public {
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        amounts[0] = 100;
        address nonOperator = address(0xBADD1E);
        // Ensure nonOperator has a balance and approval to avoid other reverts
        token.mint(nonOperator, 100);
        vm.prank(nonOperator);
        token.approve(address(manager), 100);
        vm.prank(nonOperator);
        vm.expectRevert();
        manager.createDeposits(ids, amounts, nonOperator);
    }

    /// @notice Only addresses with the operator role may redeem deposits
    function testOnlyOperatorCanRedeemDeposits() public {
        // Create a deposit first via operator
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        amounts[0] = 100;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);
        // Try to redeem as a non‑operator
        address nonOperator = address(0xBADD2E);
        vm.prank(nonOperator);
        vm.expectRevert();
        manager.redeemDeposits(ids, receiver);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     Redemption Tests
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test redeeming a single deposit transfers the decayed value and updates state
    function testRedeemDeposit() public {
        // Create a deposit first
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        uint192 amount = 1_000 * 10 ** 8;
        amounts[0] = amount;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);

        // Advance time by one year to accrue fees
        uint256 oneYear = 365 days;
        vm.warp(block.timestamp + oneYear);

        // Compute expected value: principal minus decay (0.95% per year)
        // FEE_ANNUAL_PPM = 950_000 (0.95%) so decay = amount * 0.0095 = 9.5 WBTC
        uint256 decay = (oneYear * amount) * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days;
        uint256 expectedValue = amount > decay ? amount - decay : 0;

        // Expect the DepositRedeemed event
        vm.expectEmit(true, false, false, true);
        emit WBTCDepositManager.DepositRedeemed(id1, expectedValue);

        // Capture balances before redemption
        uint256 beforeReceiver = token.balanceOf(receiver);
        uint256 beforeManager = token.balanceOf(address(manager));

        // Redeem the deposit
        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);

        // Deposit mapping should be cleared
        (uint192 principalAfter,) = manager.deposits(id1);
        assertEq(principalAfter, 0, "deposit should be deleted");

        // Manager's total principal reduced and product sum zeroed
        assertEq(manager.totalPrincipal(), 0);
        assertEq(manager.principalTimeProductSum(), 0);

        // Verify that the receiver received the decayed value
        assertEq(token.balanceOf(receiver) - beforeReceiver, expectedValue, "receiver gained expected amount");
        // Manager's balance decreased by the value
        assertEq(beforeManager - token.balanceOf(address(manager)), expectedValue, "manager lost expected amount");
    }

    /// @notice Redeeming multiple deposits transfers the aggregate value
    function testRedeemMultipleDeposits() public {
        // Create two deposits
        bytes32[] memory ids = new bytes32[](2);
        uint192[] memory amounts = new uint192[](2);
        ids[0] = id1;
        ids[1] = id2;
        uint192 amount1 = 400 * 10 ** 8;
        uint192 amount2 = 600 * 10 ** 8;
        amounts[0] = amount1;
        amounts[1] = amount2;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);

        // Warp one year
        uint256 oneYear = 365 days;
        vm.warp(block.timestamp + oneYear);

        // Compute decayed values individually
        uint256 decay1 = (oneYear * amount1) * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days;
        uint256 decay2 = (oneYear * amount2) * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days;
        uint256 value1 = amount1 > decay1 ? amount1 - decay1 : 0;
        uint256 value2 = amount2 > decay2 ? amount2 - decay2 : 0;
        uint256 expectedTotal = value1 + value2;

        // Redeem both deposits
        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);

        // Ensure both deposit records are removed
        (uint192 p1,) = manager.deposits(id1);
        (uint192 p2,) = manager.deposits(id2);
        assertEq(p1, 0);
        assertEq(p2, 0);
        // Check aggregated totals are cleared
        assertEq(manager.totalPrincipal(), 0);
        assertEq(manager.principalTimeProductSum(), 0);
        // Receiver should have received the expected total value
        assertEq(token.balanceOf(receiver), expectedTotal, "receiver should have total value");
    }

    /// @notice Reverts when redeeming to a receiver lacking the RECEIVER_ROLE
    function testRedeemDepositInvalidReceiver() public {
        // Create a deposit
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        amounts[0] = 100;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);

        // Use an address without the receiver role
        address badReceiver = address(0xBAD);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WBTCDepositManager.InvalidReceiver.selector, badReceiver));
        manager.redeemDeposits(ids, badReceiver);
    }

    /// @notice Reverts when attempting to redeem a non‑existent deposit
    function testRedeemDepositNotFound() public {
        // No deposits exist for id1
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id1;
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WBTCDepositManager.DepositNotFound.selector, id1));
        manager.redeemDeposits(ids, receiver);
    }

    /// @notice Reverts when the underlying ERC20 transfer fails during redemption
    function testRedeemDepositTransferFails() public {
        // Use a failing token for this test
        MockERC20 failingToken = new MockERC20("Fail", "FAIL", 8);
        WBTCDepositManager failingManager = new WBTCDepositManager(admin, address(failingToken));
        vm.startPrank(admin);
        failingManager.grantRole(failingManager.OPERATOR_ROLE(), operator);
        failingManager.grantRole(failingManager.RECEIVER_ROLE(), receiver);
        failingManager.setDailyLimit(operator, 1_000_000e8);
        vm.stopPrank();
        // Provide deposit
        failingToken.mint(operator, 100);
        vm.prank(operator);
        failingToken.approve(address(failingManager), 100);
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        amounts[0] = 100;
        vm.prank(operator);
        failingManager.createDeposits(ids, amounts, operator);
        // Advance time to accrue fees
        vm.warp(block.timestamp + 10);
        // Force transfer to fail on redemption
        failingToken.setFailTransfer(true);
        vm.expectRevert(
            abi.encodeWithSelector(
                WBTCDepositManager.TransferFailed.selector, receiver, uint256(failingManager.depositValue(id1))
            )
        );
        vm.prank(operator);
        failingManager.redeemDeposits(ids, receiver);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 Deposit Value Tests
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice depositValue returns zero when queried for a missing deposit
    function testDepositValueReturnsZeroForMissing() public view {
        assertEq(manager.depositValue(id1), 0, "depositValue should be zero for nonexistent deposits");
    }

    /// @notice depositValue equals principal when queried immediately after creation
    function testDepositValueImmediate() public {
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        uint192 amount = 5 * 10 ** 8;
        amounts[0] = amount;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);
        assertEq(manager.depositValue(id1), amount, "initial deposit value should equal principal");
    }

    /// @notice depositValue decays over time according to FEE_ANNUAL_PPM
    function testDepositValueDecayOverTime() public {
        // Create a deposit
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        uint192 amount = 10_000 * 10 ** 8;
        amounts[0] = amount;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);

        // Warp half a year
        uint256 halfYear = 365 days / 2;
        vm.warp(block.timestamp + halfYear);
        // Compute expected value after half year (decay = P * FEE_ANNUAL_PPM * (0.5 year) / (1 year * 1e6))
        uint256 decay = (halfYear * amount) * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days;
        uint256 expectedValue = amount > decay ? amount - decay : 0;
        assertEq(manager.depositValue(id1), expectedValue, "deposit value after half year incorrect");
    }

    /// @notice depositValue eventually goes to zero when decay exceeds principal
    function testDepositValueEventuallyZero() public {
        // Large deposit so integer math still works
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        uint192 amount = 1 * 10 ** 8;
        amounts[0] = amount;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);

        // Warp a very long time (110 years)
        uint256 longtime = 110 * 365 days;
        vm.warp(block.timestamp + longtime);
        // depositValue should report zero
        assertEq(manager.depositValue(id1), 0, "deposit value should be zero after long duration");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 moveWBTC Tests
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Admin can move arbitrary WBTC held by the manager to a valid receiver
    function testMoveWBTC_Success() public {
        // Mint some WBTC directly to the manager (simulating idle funds or a migration balance)
        uint256 amount = 1_234_567_89; // 1.23456789 WBTC (8 decimals)
        token.mint(address(manager), amount);

        uint256 beforeManager = token.balanceOf(address(manager));
        uint256 beforeReceiver = token.balanceOf(receiver);

        // Admin calls moveWBTC to the whitelisted receiver
        vm.prank(admin);
        manager.moveWBTC(receiver, amount);

        assertEq(token.balanceOf(address(manager)), beforeManager - amount, "manager balance should decrease");
        assertEq(token.balanceOf(receiver), beforeReceiver + amount, "receiver should receive amount");
    }

    /// @notice Reverts when receiver lacks RECEIVER_ROLE
    function testMoveWBTC_RevertWhen_InvalidReceiver() public {
        // Give the manager balance so transfer would otherwise succeed
        uint256 amount = 100 * 10 ** 8;
        token.mint(address(manager), amount);

        // Receiver without role
        address bad = address(0xBAD);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(WBTCDepositManager.InvalidReceiver.selector, bad));
        manager.moveWBTC(bad, amount);
    }

    /// @notice Only DEFAULT_ADMIN_ROLE may call moveWBTC
    function testMoveWBTC_RevertWhen_NotAdmin() public {
        uint256 amount = 42;
        token.mint(address(manager), amount);

        // Operator has OPERATOR_ROLE but not DEFAULT_ADMIN_ROLE
        vm.prank(operator);
        vm.expectRevert(); // AccessControl revert (selector differs by OZ version, keep generic)
        manager.moveWBTC(receiver, amount);
    }

    /// @notice Reverts when the underlying ERC20 transfer fails
    function testMoveWBTC_RevertWhen_TransferFails() public {
        // Fresh manager wired to a token that can fail transfers
        MockERC20 failingToken = new MockERC20("Fail", "FAIL", 8);
        WBTCDepositManager failingManager = new WBTCDepositManager(admin, address(failingToken));

        // Roles
        vm.startPrank(admin);
        failingManager.grantRole(failingManager.OPERATOR_ROLE(), operator);
        failingManager.grantRole(failingManager.RECEIVER_ROLE(), receiver);
        vm.stopPrank();

        // Fund the manager and force transfer to fail
        uint256 amount = 777;
        failingToken.mint(address(failingManager), amount);
        failingToken.setFailTransfer(true);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(WBTCDepositManager.TransferFailed.selector, receiver, amount));
        failingManager.moveWBTC(receiver, amount);
    }

    /*//////////////////////////////////////////////////////////////////////////
                               rescueTokens Tests
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Rescues a non-WBTC ERC20 accidentally sent to the manager
    function testRescueTokens_ERC20_Success() public {
        // Create a random ERC20 distinct from WBTC
        MockERC20 other = new MockERC20("Other", "OTH", 18);

        // Send tokens to the manager (simulating accidental transfer)
        uint256 amount = 5_000 * 10 ** 18;
        other.mint(address(manager), amount);

        uint256 beforeManager = other.balanceOf(address(manager));
        uint256 beforeReceiver = other.balanceOf(receiver);

        // Admin rescues to an authorized receiver
        vm.startPrank(admin);
        manager.grantRole(manager.OPERATOR_ROLE(), admin); // ensure admin is also operator for this call
        manager.rescueTokens(address(other), receiver, amount);
        vm.stopPrank();

        assertEq(other.balanceOf(address(manager)), beforeManager - amount, "manager ERC20 balance should decrease");
        assertEq(other.balanceOf(receiver), beforeReceiver + amount, "receiver should receive rescued ERC20");
    }

    /// @notice Rescues ETH accidentally held by the manager to an authorized receiver
    function testRescueTokens_ETH_Success() public {
        // Fund the manager with ETH directly
        uint256 amount = 1 ether;
        vm.deal(address(manager), amount);

        uint256 beforeManager = address(manager).balance;
        uint256 beforeReceiver = receiver.balance;

        // Operator rescues ETH to receiver
        vm.prank(operator);
        manager.rescueTokens(address(0), receiver, amount);

        assertEq(address(manager).balance, beforeManager - amount, "manager ETH balance should decrease");
        assertEq(receiver.balance, beforeReceiver + amount, "receiver should receive rescued ETH");
    }

    /// @notice Reverts when attempting to rescue WBTC
    function testRescueTokens_RevertWhen_CannotRescueWBTC() public {
        // Give the manager some WBTC so the call would otherwise be valid
        uint256 amount = 100 * 10 ** 8;
        token.mint(address(manager), amount);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WBTCDepositManager.CannotRescueWBTC.selector));
        manager.rescueTokens(address(token), receiver, amount);
    }

    /// @notice Reverts when amount is zero
    function testRescueTokens_RevertWhen_ZeroAmount() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WBTCDepositManager.ZeroAmount.selector));
        manager.rescueTokens(address(0), receiver, 0);
    }

    /// @notice Reverts when receiver lacks RECEIVER_ROLE
    function testRescueTokens_RevertWhen_InvalidReceiver() public {
        // Fund manager with ETH to avoid unrelated reverts
        vm.deal(address(manager), 1 ether);

        address bad = address(0xBAD);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WBTCDepositManager.InvalidReceiver.selector, bad));
        manager.rescueTokens(address(0), bad, 0.5 ether);
    }

    /// @notice Only OPERATOR_ROLE may call rescueTokens
    function testRescueTokens_RevertWhen_CallerNotOperator() public {
        // Fund manager with some other ERC20
        MockERC20 other = new MockERC20("Other", "OTH", 8);
        other.mint(address(manager), 1_000);

        address nonOperator = address(0xBADD1E);
        // Ensure receiver is valid
        vm.startPrank(admin);
        manager.grantRole(manager.RECEIVER_ROLE(), receiver);
        vm.stopPrank();

        vm.prank(nonOperator);
        vm.expectRevert(); // AccessControl revert
        manager.rescueTokens(address(other), receiver, 100);
    }

    /*//////////////////////////////////////////////////////////////////////////
                               Withdrawal Quota Tests
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Reverts when redeeming without a daily limit set for the operator
    function testQuota_RevertWhen_LimitNotSetOnRedeem() public {
        // Fresh manager without a daily limit
        WBTCDepositManager m2 = new WBTCDepositManager(admin, address(token));
        vm.startPrank(admin);
        m2.grantRole(m2.OPERATOR_ROLE(), operator);
        m2.grantRole(m2.RECEIVER_ROLE(), receiver);
        vm.stopPrank();

        // Fund operator and approve m2
        token.mint(operator, 1_000e8);
        vm.prank(operator);
        token.approve(address(m2), type(uint256).max);

        // Create a deposit
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = keccak256("quota-no-limit");
        amounts[0] = 500e8;
        vm.prank(operator);
        m2.createDeposits(ids, amounts, operator);

        // Redeem should revert due to missing limit
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(RedemptionLimiter.LimitNotSet.selector));
        m2.redeemDeposits(ids, receiver);
    }

    /// @notice Reverts when redeeming more than the available daily quota
    function testQuota_RevertWhen_ExceedsAvailable() public {
        // Configure a small daily limit
        uint192 limit = 1_000e8;
        vm.prank(admin);
        manager.setDailyLimit(operator, limit);

        // Create a deposit larger than the limit
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = keccak256("quota-exceed");
        amounts[0] = 1_200e8;

        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);

        // Redeeming now should exceed quota and revert
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(RedemptionLimiter.WithdrawalLimitExceeded.selector));
        manager.redeemDeposits(ids, receiver);
    }

    /// @notice Consuming quota reduces availability, which refills linearly over time
    function testQuota_ConsumeAndRefillOverTime() public {
        uint192 limit = 1_000e8;
        vm.prank(admin);
        manager.setDailyLimit(operator, limit);

        // Create and redeem a deposit that consumes part of the quota
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = keccak256("quota-partial");
        amounts[0] = 600e8;

        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);

        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);

        // Immediately after redeem, available = limit - 600
        assertEq(manager.availableRedemptionQuota(operator), uint256(limit - 600e8));

        uint256 ts1 = block.timestamp + 12 hours;
        uint256 ts2 = block.timestamp + 24 hours;

        // After 12 hours, refill = limit * 0.5
        vm.warp(ts1);
        assertEq(manager.availableRedemptionQuota(operator), uint256(900e8));

        // After another 12 hours, it refills to full (clamped to limit)
        vm.warp(ts2);
        assertEq(manager.availableRedemptionQuota(operator), uint256(limit));
    }

    /// @notice setDailyLimit resets the user's window to full and updates lastRefillTime
    function testQuota_SetDailyLimitResetsWindow() public {
        // Start with a limit and consume some
        uint192 initialLimit = 1_000e8;
        vm.prank(admin);
        manager.setDailyLimit(operator, initialLimit);

        // Create and redeem 300e8
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = keccak256("quota-reset");
        amounts[0] = 300e8;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);
        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);

        // Sanity: available is initialLimit - 300
        assertEq(manager.availableRedemptionQuota(operator), uint256(initialLimit - 300e8));

        // Advance time, then reconfigure to a new limit; it should reset to full
        vm.warp(block.timestamp + 1 hours);
        uint192 newLimit = 2_000e8;
        vm.prank(admin);
        manager.setDailyLimit(operator, newLimit);

        // Window reset: available == newLimit, lastRefillTime == now
        (uint192 availableAmount, uint64 lastRefillTime) = manager.userRedemptionQuota(operator);
        assertEq(availableAmount, newLimit, "available should reset to new limit");
        assertEq(lastRefillTime, uint64(block.timestamp), "lastRefillTime should be updated");
        assertEq(manager.availableRedemptionQuota(operator), uint256(newLimit), "query should reflect reset");
    }
}
