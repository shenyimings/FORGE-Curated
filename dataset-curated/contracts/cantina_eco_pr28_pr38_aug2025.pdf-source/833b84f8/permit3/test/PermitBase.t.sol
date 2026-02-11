// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../src/interfaces/IPermit.sol";
import "./utils/TestBase.sol";

/**
 * @title PermitBaseTest
 * @notice Consolidated tests for PermitBase functionality
 */
contract PermitBaseTest is TestBase {
    uint48 constant FUTURE_EXPIRATION = NOW + 1000;

    function test_allowance() public {
        // Test initial allowance
        (uint160 amount, uint48 expiration, uint48 nonce) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, 0);
        assertEq(expiration, 0);
        assertEq(nonce, 0);

        // Set allowance
        uint48 futureExpiration = NOW + 1000;
        vm.prank(owner);
        permit3.approve(address(token), spender, AMOUNT, futureExpiration);

        // Check updated allowance
        (amount, expiration, nonce) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, AMOUNT);
        assertEq(expiration, futureExpiration);
        assertEq(nonce, NOW); // block timestamp is NOW
    }

    function test_approve() public {
        uint48 futureExpiration = NOW + 1000;
        vm.prank(owner);
        permit3.approve(address(token), spender, AMOUNT, futureExpiration);

        (uint160 amount, uint48 expiration,) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, AMOUNT);
        assertEq(expiration, futureExpiration);
    }

    function test_approveEmitsEvent() public {
        uint48 futureExpiration = NOW + 1000;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPermit.Approval(owner, address(token), spender, AMOUNT, futureExpiration);
        permit3.approve(address(token), spender, AMOUNT, futureExpiration);
    }

    function test_transferFrom() public {
        // Setup approval
        vm.prank(owner);
        permit3.approve(address(token), spender, AMOUNT, FUTURE_EXPIRATION);

        // Reset recipient balance
        deal(address(token), recipient, 0);

        // Perform transfer
        vm.prank(spender);
        permit3.transferFrom(owner, recipient, AMOUNT, address(token));

        // Check balances
        assertEq(token.balanceOf(recipient), AMOUNT);

        // Check remaining allowance
        (uint160 amount,,) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, 0);
    }

    function test_transferFromBatch() public {
        // Setup approval for double the amount
        vm.prank(owner);
        permit3.approve(address(token), spender, AMOUNT * 2, FUTURE_EXPIRATION);

        // Reset recipient balances
        address recipient2 = address(0x5);
        deal(address(token), recipient, 0);
        deal(address(token), recipient2, 0);

        // Create transfer batch
        IPermit.AllowanceTransferDetails[] memory transfers = new IPermit.AllowanceTransferDetails[](2);

        transfers[0] =
            IPermit.AllowanceTransferDetails({ from: owner, token: address(token), to: recipient, amount: AMOUNT });

        transfers[1] =
            IPermit.AllowanceTransferDetails({ from: owner, token: address(token), to: recipient2, amount: AMOUNT });

        // Perform batch transfer
        vm.prank(spender);
        permit3.transferFrom(transfers);

        // Check balances
        assertEq(token.balanceOf(recipient), AMOUNT);
        assertEq(token.balanceOf(recipient2), AMOUNT);

        // Batch transfer now properly updates allowance
        (uint160 amount,,) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, 0);
    }

    function test_transferFromInsufficientAllowance() public {
        // Setup approval with less than needed
        vm.prank(owner);
        permit3.approve(address(token), spender, AMOUNT - 1, FUTURE_EXPIRATION);

        // Attempt transfer should fail
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IPermit.InsufficientAllowance.selector, AMOUNT, AMOUNT - 1));
        permit3.transferFrom(owner, recipient, AMOUNT, address(token));
    }

    function test_transferFromExpiredAllowance() public {
        // Setup approval with a short expiration
        uint48 shortExpiration = NOW + 100;
        vm.prank(owner);
        permit3.approve(address(token), spender, AMOUNT, shortExpiration);

        // Warp time to after expiration
        vm.warp(shortExpiration + 1);

        // Attempt transfer should fail
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IPermit.AllowanceExpired.selector, shortExpiration));
        permit3.transferFrom(owner, recipient, AMOUNT, address(token));
    }

    function test_maxAllowance() public {
        // Setup max allowance
        vm.prank(owner);
        permit3.approve(address(token), spender, type(uint160).max, FUTURE_EXPIRATION);

        // Reset recipient balance
        deal(address(token), recipient, 0);

        // Perform multiple transfers without reducing allowance
        vm.startPrank(spender);
        permit3.transferFrom(owner, recipient, AMOUNT, address(token));
        permit3.transferFrom(owner, recipient, AMOUNT, address(token));
        vm.stopPrank();

        // Check max allowance remains unchanged
        (uint160 amount,,) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, type(uint160).max);

        // Check recipient received tokens
        assertEq(token.balanceOf(recipient), AMOUNT * 2);
    }

    function test_lockdown() public {
        // Setup approvals
        vm.prank(owner);
        permit3.approve(address(token), spender, AMOUNT, FUTURE_EXPIRATION);

        IPermit.TokenSpenderPair[] memory pairs = new IPermit.TokenSpenderPair[](1);
        pairs[0] = IPermit.TokenSpenderPair({ token: address(token), spender: spender });

        vm.prank(owner);
        permit3.lockdown(pairs);

        // Verify approvals are revoked
        (uint160 amount,,) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, 0);
    }

    function test_lockdownEmitsEvent() public {
        // Setup approvals
        vm.prank(owner);
        permit3.approve(address(token), spender, AMOUNT, FUTURE_EXPIRATION);

        IPermit.TokenSpenderPair[] memory pairs = new IPermit.TokenSpenderPair[](1);
        pairs[0] = IPermit.TokenSpenderPair({ token: address(token), spender: spender });

        vm.expectEmit(true, true, true, true);
        emit IPermit.Lockdown(owner, address(token), spender);

        vm.prank(owner);
        permit3.lockdown(pairs);
    }

    function test_multipleLockdowns() public {
        address spender2 = address(0x5);

        // Setup multiple approvals
        vm.startPrank(owner);
        permit3.approve(address(token), spender, AMOUNT, FUTURE_EXPIRATION);
        permit3.approve(address(token), spender2, AMOUNT, FUTURE_EXPIRATION);

        IPermit.TokenSpenderPair[] memory pairs = new IPermit.TokenSpenderPair[](2);
        pairs[0] = IPermit.TokenSpenderPair({ token: address(token), spender: spender });
        pairs[1] = IPermit.TokenSpenderPair({ token: address(token), spender: spender2 });

        permit3.lockdown(pairs);
        vm.stopPrank();

        // Verify all approvals are revoked
        (uint160 amount1,,) = permit3.allowance(owner, address(token), spender);
        (uint160 amount2,,) = permit3.allowance(owner, address(token), spender2);
        assertEq(amount1, 0);
        assertEq(amount2, 0);
    }

    function test_transferFromLockedAllowance() public {
        // Setup approval
        vm.prank(owner);
        permit3.approve(address(token), spender, AMOUNT, FUTURE_EXPIRATION);

        // Lock the allowance
        IPermit.TokenSpenderPair[] memory pairs = new IPermit.TokenSpenderPair[](1);
        pairs[0] = IPermit.TokenSpenderPair({ token: address(token), spender: spender });

        vm.prank(owner);
        permit3.lockdown(pairs);

        // Attempt transfer should fail due to locked allowance
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IPermit.AllowanceLocked.selector, owner, address(token), spender));
        permit3.transferFrom(owner, recipient, AMOUNT, address(token));

        // Verify allowance is still locked
        (uint160 amount, uint48 expiration,) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, 0);
        assertEq(expiration, 2); // LOCKED_ALLOWANCE = 2
    }

    function test_approveRevertTokenZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IPermit.ZeroToken.selector);
        permit3.approve(address(0), spender, AMOUNT, NOW + 1000);
    }

    function test_approveRevertAmountZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPermit.InvalidAmount.selector, 0));
        permit3.approve(address(token), spender, 0, FUTURE_EXPIRATION);
    }

    function test_approveRevertExpirationInPast() public {
        uint48 pastExpiration = NOW - 100;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPermit.InvalidExpiration.selector, pastExpiration));
        permit3.approve(address(token), spender, AMOUNT, pastExpiration);
    }

    function test_approveAllowsZeroExpiration() public {
        // Zero expiration should be allowed (means no expiration)
        vm.prank(owner);
        permit3.approve(address(token), spender, AMOUNT, 0);

        (uint160 amount, uint48 expiration,) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, AMOUNT);
        assertEq(expiration, 0);
    }

    function test_approveAllowsFutureExpiration() public {
        uint48 futureExpiration = NOW + 1000;
        vm.prank(owner);
        permit3.approve(address(token), spender, AMOUNT, futureExpiration);

        (uint160 amount, uint48 expiration,) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, AMOUNT);
        assertEq(expiration, futureExpiration);
    }

    function test_approveRevertExpirationAtCurrentTime() public {
        // Expiration at exactly current time should fail (not greater than block.timestamp)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPermit.InvalidExpiration.selector, NOW));
        permit3.approve(address(token), spender, AMOUNT, NOW);
    }

    function test_transferFromWithZeroExpirationNeverExpires() public {
        // Setup approval with zero expiration (never expires)
        vm.prank(owner);
        permit3.approve(address(token), spender, AMOUNT, 0);

        // Reset recipient balance
        deal(address(token), recipient, 0);

        // Warp time far into the future
        vm.warp(block.timestamp + 365 days);

        // Transfer should still work even after a long time
        vm.prank(spender);
        permit3.transferFrom(owner, recipient, AMOUNT, address(token));

        // Check balances
        assertEq(token.balanceOf(recipient), AMOUNT);

        // Check remaining allowance
        (uint160 amount,,) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, 0);
    }

    function test_transferFromBatchWithZeroExpirationNeverExpires() public {
        // Setup approval with zero expiration for double the amount
        vm.prank(owner);
        permit3.approve(address(token), spender, AMOUNT * 2, 0);

        // Reset recipient balances
        address recipient2 = address(0x5);
        deal(address(token), recipient, 0);
        deal(address(token), recipient2, 0);

        // Warp time far into the future
        vm.warp(block.timestamp + 365 days);

        // Create transfer batch
        IPermit.AllowanceTransferDetails[] memory transfers = new IPermit.AllowanceTransferDetails[](2);
        transfers[0] =
            IPermit.AllowanceTransferDetails({ from: owner, token: address(token), to: recipient, amount: AMOUNT });
        transfers[1] =
            IPermit.AllowanceTransferDetails({ from: owner, token: address(token), to: recipient2, amount: AMOUNT });

        // Batch transfer should still work
        vm.prank(spender);
        permit3.transferFrom(transfers);

        // Check balances
        assertEq(token.balanceOf(recipient), AMOUNT);
        assertEq(token.balanceOf(recipient2), AMOUNT);

        // Check remaining allowance
        (uint160 amount,,) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, 0);
    }
}
