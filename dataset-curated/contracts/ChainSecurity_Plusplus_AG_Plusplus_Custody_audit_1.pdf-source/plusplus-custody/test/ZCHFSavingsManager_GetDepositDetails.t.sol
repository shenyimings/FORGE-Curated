// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ZCHFSavingsManagerTestBase} from "./helpers/ZCHFSavingsManagerTestBase.sol";
import {ZCHFSavingsManager} from "src/ZCHFSavingsManager.sol";

/// @title ZCHFSavingsManager_GetDepositDetails
/// @notice Tests for the view functions getDepositDetails().
/// This test verifies that interest and fees are
/// computed correctly under various scenarios, including boundary cases.
contract ZCHFSavingsManager_GetDepositDetails is ZCHFSavingsManagerTestBase {
    /// @notice Non-existent deposits should return (0,0).
    function testGetDepositDetailsNonexistent() public view {
        bytes32 id = bytes32(uint256(999));
        (uint192 principal, uint192 net) = manager.getDepositDetails(id);
        assertEq(principal, 0);
        assertEq(net, 0);
    }

    /// @notice Before any interest has accrued, net interest should be zero.
    function testGetDepositDetailsBeforeInterest() public {
        bytes32 id = bytes32(uint256(1));
        uint192 amount = 1_000;
        depositExample(id, amount, user);
        // Retrieve the deposit struct to know ticksAtDeposit
        (,, uint64 ticksAtDeposit) = manager.deposits(id);
        // Set the mock savings tick equal to ticksAtDeposit so deltaTicks = 0
        savings.setTick(ticksAtDeposit);
        // No need to warp time; call getDepositDetails now
        (uint192 principal, uint192 netInterest) = manager.getDepositDetails(id);
        assertEq(principal, amount);
        assertEq(netInterest, 0);
    }

    /// @notice Interest should accrue when ticks exceed ticksAtDeposit and time
    /// has passed. Fees should be deducted according to the FEE_ANNUAL_PPM.
    function testGetDepositDetailsAfterInterest() public {
        bytes32 id = bytes32(uint256(2));
        uint192 amount = 5_000;
        depositExample(id, amount, user);
        // Retrieve deposit values
        (uint192 initAmt,, uint64 ticksAtDeposit) = manager.deposits(id);
        // Simulate deltaTicks
        uint64 deltaTicks = 4_000_000;
        savings.setTick(ticksAtDeposit + deltaTicks);
        // Warp time by 20 days
        uint256 duration = 20 days;
        vm.warp(block.timestamp + duration);
        // Compute expected net interest
        uint256 totalInterest = uint256(deltaTicks) * initAmt / 1_000_000 / 365 days;
        uint256 feeableTicks = duration * manager.FEE_ANNUAL_PPM();
        uint256 feeTicks = feeableTicks < deltaTicks ? feeableTicks : deltaTicks;
        uint256 fee = feeTicks * initAmt / 1_000_000 / 365 days;
        uint256 net = totalInterest > fee ? totalInterest - fee : 0;
        // Query details
        (uint192 principal, uint192 netInterest) = manager.getDepositDetails(id);
        assertEq(principal, initAmt);
        assertEq(netInterest, uint192(net));
    }

    /// @notice When the fee equals or exceeds the accrued interest, the net
    /// interest returned should be zero.
    function testGetDepositDetailsFeeGreaterThanInterest() public {
        bytes32 id = bytes32(uint256(3));
        uint192 amount = 10_000;
        depositExample(id, amount, user);
        // Retrieve the deposit struct
        (uint192 initAmt,, uint64 ticksAtDeposit) = manager.deposits(id);
        // Choose a very small deltaTicks so totalInterest is small
        uint64 deltaTicks = 100;
        savings.setTick(ticksAtDeposit + deltaTicks);
        // Warp time by 100 days to make feeableTicks huge
        uint256 duration = 100 days;
        vm.warp(block.timestamp + duration);
        // Compute expected
        uint256 totalInterest = uint256(deltaTicks) * initAmt / 1_000_000 / 365 days;
        uint256 feeableTicks = duration * manager.FEE_ANNUAL_PPM();
        uint256 feeTicks = feeableTicks < deltaTicks ? feeableTicks : deltaTicks;
        uint256 fee = feeTicks * initAmt / 1_000_000 / 365 days;
        uint256 net = totalInterest > fee ? totalInterest - fee : 0;
        // In this scenario fee should be >= interest, so net = 0
        assertEq(net, 0);
        // Query contract and expect zero net interest
        (, uint192 netInterestContract) = manager.getDepositDetails(id);
        assertEq(netInterestContract, 0);
    }
}
