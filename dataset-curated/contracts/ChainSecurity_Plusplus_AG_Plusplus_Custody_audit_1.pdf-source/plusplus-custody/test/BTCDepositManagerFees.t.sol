// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdCheats.sol";

import {WBTCDepositManager} from "src/WBTCDepositManager.sol";
import {MockERC20} from "test/utils/MockERC20.sol";

/// @title WBTCDepositManagerFeesTest
/// @notice Tests covering aggregate value, fee accumulation and fee collection logic.
contract WBTCDepositManagerFeesTest is Test {
    WBTCDepositManager internal manager;
    MockERC20 internal token;
    address internal admin = makeAddr("0xA11CE");
    address internal operator = makeAddr("0x0P3R8"); // test operator address
    address internal receiver = makeAddr("0xBEEF"); // account used for redemption and fee collection

    bytes32 internal id1 = bytes32(uint256(1));
    bytes32 internal id2 = bytes32(uint256(2));

    function setUp() public {
        token = new MockERC20("Mock WBTC", "mWBTC", 8);
        manager = new WBTCDepositManager(admin, address(token));
        vm.startPrank(admin);
        manager.grantRole(manager.OPERATOR_ROLE(), operator);
        manager.grantRole(manager.RECEIVER_ROLE(), receiver);
        manager.setDailyLimit(operator, 1_000_000e8);
        vm.stopPrank();
        // Provide operator with large balance and approval
        token.mint(operator, 100_000 * 10 ** 8);
        vm.prank(operator);
        token.approve(address(manager), type(uint256).max);
    }

    /// @notice totalDepositValue returns the decayed total across all deposits
    function testTotalDepositValueAggregated() public {
        // Schedule
        vm.warp(1_700_000_000);
        uint256 ts1 = block.timestamp + 1 days;
        uint256 ts2 = block.timestamp + 2 days;

        // Create two deposits at different times
        bytes32[] memory ids1 = new bytes32[](1);
        uint192[] memory amounts1 = new uint192[](1);
        ids1[0] = id1;
        amounts1[0] = 1 * 10 ** 8;
        vm.prank(operator);
        manager.createDeposits(ids1, amounts1, operator);

        // Warp ahead by one day and add second deposit
        vm.warp(ts1);
        bytes32[] memory ids2 = new bytes32[](1);
        uint192[] memory amounts2 = new uint192[](1);
        ids2[0] = id2;
        amounts2[0] = 2 * 10 ** 8;
        vm.prank(operator);
        manager.createDeposits(ids2, amounts2, operator);

        // Warp ahead by another day to compute total value
        vm.warp(ts2);

        // // Compute expected aggregated value
        // uint256 t = block.timestamp;
        // uint256 principalSum = amounts1[0] + amounts2[0];
        // principalTimeProductSum should equal amounts1*creationTime1 + amounts2*creationTime2
        // uint256 ptpSum = amounts1[0] * (t - 1 days - 1 days) + amounts2[0] * (t - 1 days);
        // // Wait: we changed warp to t, but we need startTimes individually: start1 at time t-2 days, start2 at time t-1 day; we can't compute by referencing manager storage? We'll compute using formula: elapsedProduct = t * totalPrincipal - principalTimeProductSum
        // uint256 totalPrincipalStored = manager.totalPrincipal();
        // uint256 ptpStored = manager.principalTimeProductSum();
        // uint256 elapsedProduct = t * totalPrincipalStored - ptpStored;
        // uint256 decay = elapsedProduct * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days;
        // uint256 expected = totalPrincipalStored > decay ? totalPrincipalStored - decay : 0;

        // Fully manual computation
        uint256 value1 = amounts1[0] - ((2 days * amounts1[0]) * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days);
        uint256 value2 = amounts2[0] - ((1 days * amounts2[0]) * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days);
        uint256 expected = value1 + value2;

        // Compare computed expected and contract output
        assertEq(manager.totalDepositValue(), expected, "totalDepositValue should equal expected value");
    }

    /// @notice accumulatedFees reflects the difference between contract balance and totalDepositValue
    function testAccumulatedFees() public {
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        uint192 amount = 1_000 * 10 ** 8;
        amounts[0] = amount;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);

        // Immediately after deposit creation there should be zero fees
        assertEq(manager.accumulatedFees(), 0, "no fees immediately after deposit creation");

        // Warp half year; deposit decays
        uint256 halfYear = 365 days / 2;
        vm.warp(block.timestamp + halfYear);

        // Compute expected deposit value and fees
        uint256 decay = (halfYear * amount) * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days;
        uint256 value = amount > decay ? amount - decay : 0;
        uint256 expectedFees = amount - value;
        // Contract holds full amount still
        assertEq(token.balanceOf(address(manager)), amount);
        assertEq(manager.totalDepositValue(), value);
        assertEq(manager.accumulatedFees(), expectedFees, "accumulatedFees should equal decay");
    }

    /// @notice accumulatedFees after redemption equals leftover decayed amount
    function testAccumulatedFeesAfterRedeem() public {
        // Create a deposit and warp
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        uint192 amount = 1_000 * 10 ** 8;
        amounts[0] = amount;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);
        uint256 halfYear = 365 days / 2;
        vm.warp(block.timestamp + halfYear);
        uint256 decay = (halfYear * amount) * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days;
        uint256 value = amount > decay ? amount - decay : 0;
        uint256 expectedFee = amount - value;

        // Redeem deposit
        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);

        // After redemption there should be no deposits
        assertEq(manager.totalPrincipal(), 0);
        // Contract balance equals the decay amount (fees)
        assertEq(token.balanceOf(address(manager)), expectedFee);
        // totalDepositValue should be zero
        assertEq(manager.totalDepositValue(), 0);
        // accumulatedFees should now equal full balance
        assertEq(manager.accumulatedFees(), expectedFee, "fees equal leftover balance");
    }

    /// @notice collectFees transfers fees to a receiver and returns the amount collected
    function testCollectFees() public {
        // Create deposit and accrue some fees
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        uint192 amount = 2_000 * 10 ** 8;
        amounts[0] = amount;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);
        uint256 oneYear = 365 days;
        vm.warp(block.timestamp + oneYear);
        uint256 decay = (oneYear * amount) * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days;
        uint256 value = amount > decay ? amount - decay : 0;
        uint256 fee = amount - value;
        // Redeem deposit leaving fees behind
        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);
        // The manager now holds the decayed amount as fees
        assertEq(token.balanceOf(address(manager)), fee);

        // Collect fees as operator into receiver (receiver already has RECEIVER_ROLE)
        vm.prank(operator);
        uint256 collected = manager.collectFees(receiver);
        assertEq(collected, fee, "collectFees should return full fee amount");
        // Receiver balance should have increased by fee
        assertEq(token.balanceOf(receiver), value + fee, "receiver should now hold deposit value plus fee");
        // Manager should have no leftover balance
        assertEq(token.balanceOf(address(manager)), 0, "manager balance should be zero after fee collection");
    }

    /// @notice Only an operator may call collectFees
    function testCollectFeesOnlyOperator() public {
        // Create deposit and accrue fees
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        amounts[0] = 1_000;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);
        // Warp to accrue fees then redeem leaving fees
        vm.warp(block.timestamp + 1 days);
        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);
        // Attempt to collect fees from non‑operator should revert with AccessControl
        address nonOperator = address(0x1234);
        vm.prank(nonOperator);
        vm.expectRevert();
        manager.collectFees(receiver);
    }

    /// @notice Reverts when collecting fees to a receiver lacking the RECEIVER_ROLE
    function testCollectFeesInvalidReceiver() public {
        // Create a deposit to trigger fee logic
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        amounts[0] = 100;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);

        // Advance time to accrue (some) fees
        vm.warp(block.timestamp + 1 days);

        // Call collectFees to an address that does not have RECEIVER_ROLE
        address badReceiver = makeAddr("invalid receiver");
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WBTCDepositManager.InvalidReceiver.selector, badReceiver));
        manager.collectFees(badReceiver);
    }

    /// @notice collectFees returns zero when no fees are available
    function testCollectFeesReturnsZeroWhenNone() public {
        // Attempt to collect fees when there are no deposits/fees
        vm.prank(operator);
        uint256 collected = manager.collectFees(receiver);
        assertEq(collected, 0, "collectFees should return zero when no fees");
    }

    /// @notice Reverts when the underlying token transfer fails during fee collection
    function testCollectFeesTransferFails() public {
        // Deploy a failing token and manager
        MockERC20 failingToken = new MockERC20("Fail", "FAIL", 8);
        WBTCDepositManager failingManager = new WBTCDepositManager(admin, address(failingToken));
        vm.startPrank(admin);
        failingManager.grantRole(failingManager.OPERATOR_ROLE(), operator);
        failingManager.grantRole(failingManager.RECEIVER_ROLE(), receiver);
        failingManager.setDailyLimit(operator, 1_000_000e8);
        vm.stopPrank();
        // Create deposit to generate fees
        failingToken.mint(operator, 1_000);
        vm.prank(operator);
        failingToken.approve(address(failingManager), 1_000);
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id1;
        amounts[0] = 1_000;
        vm.prank(operator);
        failingManager.createDeposits(ids, amounts, operator);
        // Warp and redeem deposit to leave fees behind
        vm.warp(block.timestamp + 365 days);
        vm.prank(operator);
        failingManager.redeemDeposits(ids, receiver);
        // Force transfer fail
        failingToken.setFailTransfer(true);
        // Attempt to collect fees; expect revert with custom TransferFailed error
        vm.expectRevert(
            abi.encodeWithSelector(
                WBTCDepositManager.TransferFailed.selector,
                receiver,
                uint256(failingToken.balanceOf(address(failingManager)))
            )
        );
        vm.prank(operator);
        failingManager.collectFees(receiver);
    }
}
