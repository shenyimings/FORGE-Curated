// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ZCHFSavingsManagerTestBase} from "./helpers/ZCHFSavingsManagerTestBase.sol";
import {IZCHFErrors} from "./interfaces/IZCHFErrors.sol";

/// @title ZCHFSavingsManager_CreateDeposits
/// @notice Unit tests covering the createDeposits() function of the
/// ZCHFSavingsManager contract. These tests exercise normal flows, edge
/// cases and revert conditions for batch deposit creation.
contract ZCHFSavingsManager_CreateDeposits is ZCHFSavingsManagerTestBase {
    // Events copied from the contract for use with expectEmit. They must
    // match the definitions in ZCHFSavingsManager exactly.
    event DepositCreated(bytes32 indexed identifier, uint192 amount);
    event DepositRedeemed(bytes32 indexed identifier, uint192 totalAmount);
    /// @notice Verify that non-operators cannot call createDeposits().

    function testRevertWhenCallerNotOperator() public {
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = bytes32(uint256(1));
        amounts[0] = 100;
        vm.prank(user);
        // Expect the standard AccessControl revert. We cannot match the
        // exact revert reason because AccessControl formats it with the
        // account and role. Instead we simply expect a revert.
        vm.expectRevert();
        manager.createDeposits(ids, amounts, user);
    }

    /// @notice Ensure that mismatched identifier and amount array lengths revert.
    function testRevertWhenArrayLengthsMismatch() public {
        bytes32[] memory ids = new bytes32[](2);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = bytes32(uint256(1));
        ids[1] = bytes32(uint256(2));
        amounts[0] = 100;
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IZCHFErrors.InvalidArgument.selector));
        manager.createDeposits(ids, amounts, user);
    }

    /// @notice Ensure that deposits cannot be created with an amount of zero.
    function testRevertWhenAnyAmountIsZero() public {
        bytes32[] memory ids = new bytes32[](2);
        uint192[] memory amounts = new uint192[](2);
        ids[0] = bytes32(uint256(1));
        ids[1] = bytes32(uint256(2));
        amounts[0] = 0;
        amounts[1] = 10;
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IZCHFErrors.ZeroAmount.selector));
        manager.createDeposits(ids, amounts, user);
    }

    /// @notice Ensure that attempting to create a deposit with an identifier
    /// that already exists reverts.
    function testRevertWhenDepositAlreadyExists() public {
        // First create a deposit
        bytes32 d1 = bytes32(uint256(1));
        depositExample(d1, 100, user);
        // Attempt to create another deposit with the same id
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = d1;
        amounts[0] = 50;
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IZCHFErrors.DepositAlreadyExists.selector, d1));
        manager.createDeposits(ids, amounts, user);
    }

    /// @notice Ensure that when the source is the contract itself, no transferFrom
    /// call is made and deposits are still recorded correctly.
    function testCreatesDepositsUsingManagerBalance() public {
        // Pre-fund the manager contract to cover the deposit
        // Transfer tokens from this test contract to the manager
        uint256 amount = 1e6;
        token.transfer(address(manager), amount);

        bytes32[] memory ids = new bytes32[](2);
        uint192[] memory amounts = new uint192[](2);
        ids[0] = bytes32(uint256(1));
        ids[1] = bytes32(uint256(2));
        amounts[0] = 200;
        amounts[1] = 300;

        // Expect two DepositCreated events
        vm.expectEmit(true, false, false, true);
        emit DepositCreated(bytes32(uint256(1)), 200);
        vm.expectEmit(true, false, false, true);
        emit DepositCreated(bytes32(uint256(2)), 300);

        vm.prank(operator);
        manager.createDeposits(ids, amounts, address(manager));

        // Verify the deposits were stored
        (uint192 a1,) = manager.getDepositDetails(bytes32(uint256(1)));
        (uint192 a2,) = manager.getDepositDetails(bytes32(uint256(2)));
        assertEq(a1, 200);
        assertEq(a2, 300);
        // The savings module should have recorded the total amount
        assertEq(savings.saved(), 500);
        // The mock saving contract doesn't actually pull any tokens, so we can't test that here.
        // assertEq(token.balanceOf(address(manager)), amount - 500);
    }

    /// @notice Ensure that the total amount of all deposits is transferred
    /// and saved in the savings module when the source is not the manager.
    function testCreatesDepositsTransfersAndSaves() public {
        // Prepare two deposits from the user
        bytes32[] memory ids = new bytes32[](2);
        uint192[] memory amounts = new uint192[](2);
        ids[0] = bytes32(uint256(42));
        ids[1] = bytes32(uint256(43));
        amounts[0] = 1000;
        amounts[1] = 2000;
        uint192 total = amounts[0] + amounts[1];

        // Expect DepositCreated events
        vm.expectEmit(true, false, false, true);
        emit DepositCreated(ids[0], amounts[0]);
        vm.expectEmit(true, false, false, true);
        emit DepositCreated(ids[1], amounts[1]);

        // When calling createDeposits the manager pulls tokens from the source
        vm.prank(operator);
        manager.createDeposits(ids, amounts, user);

        // Verify tokens were pulled from the user
        assertEq(token.balanceOf(user), 1e24 - total);
        assertEq(token.balanceOf(address(manager)), total);

        // The savings module should record the total saved amount
        assertEq(savings.saved(), total);

        // Check deposit structs
        (uint192 amt0,) = manager.getDepositDetails(ids[0]);
        (uint192 amt1,) = manager.getDepositDetails(ids[1]);
        assertEq(amt0, amounts[0]);
        assertEq(amt1, amounts[1]);
    }

    /// @notice Ensure that createDeposits reverts and does not persist state
    /// if transferFrom fails on the token.
    function testRevertWhenTransferFromFails() public {
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = bytes32(uint256(1));
        amounts[0] = 100;
        // Set the mock token to fail the next transferFrom
        token.setFailTransferFrom(true);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IZCHFErrors.TransferFromFailed.selector, user, manager, amounts[0]));
        manager.createDeposits(ids, amounts, user);
        // After revert, ensure no deposits were stored and no funds were saved
        (uint192 amt,) = manager.getDepositDetails(ids[0]);
        assertEq(amt, 0);
        assertEq(savings.saved(), 0);
    }

    function testRevertWhenDuplicateIdsInSingleBatch() public {
        bytes32 dup = bytes32(uint256(777));
        bytes32[] memory ids = new bytes32[](2);
        uint192[] memory amounts = new uint192[](2);
        ids[0] = dup;
        ids[1] = dup; // duplicate in the same call
        amounts[0] = 100;
        amounts[1] = 200;

        uint256 userBalBefore = token.balanceOf(user);
        uint256 mgrBalBefore = token.balanceOf(address(manager));

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IZCHFErrors.DepositAlreadyExists.selector, dup));
        manager.createDeposits(ids, amounts, user);

        // Ensure nothing was persisted
        (uint192 amtDup,) = manager.getDepositDetails(dup);
        assertEq(amtDup, 0);
        assertEq(savings.saved(), 0);
        assertEq(token.balanceOf(user), userBalBefore);
        assertEq(token.balanceOf(address(manager)), mgrBalBefore);
    }
}
