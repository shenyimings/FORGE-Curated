// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Campaign} from "../../../src/Campaign.sol";

import {Constants} from "../../../src/Constants.sol";
import {Flywheel} from "../../../src/Flywheel.sol";
import {FlywheelTest} from "../../lib/FlywheelTestBase.sol";
import {RevertingReceiver} from "../../lib/mocks/RevertingReceiver.sol";

/// @title SendTokensTest
/// @notice Tests for `Campaign.sendTokens`
contract SendTokensTest is FlywheelTest {
    function setUp() public {
        setUpFlywheelBase();
    }
    /// @notice sendTokens reverts for non-Flywheel callers
    /// @dev Expects OnlyFlywheel error when msg.sender != flywheel
    /// @param caller Caller address

    function test_sendTokens_reverts_whenCallerNotFlywheel(address caller) public {
        // Ensure caller is not the flywheel
        vm.assume(caller != address(flywheel));

        // Expect OnlyFlywheel revert
        vm.expectRevert(Campaign.OnlyFlywheel.selector);
        vm.prank(caller);
        Campaign(payable(campaign)).sendTokens(address(mockToken), caller, 100);
    }

    /// @dev Verifies sendTokens succeeds for native token
    /// @param recipient Recipient address
    /// @param amount Amount to send
    function test_sendTokens_succeeds_forNativeToken(address recipient, uint256 amount) public {
        // Bound inputs
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);
        vm.assume(recipient != campaign);

        // Fund the campaign with native tokens
        vm.deal(campaign, amount);

        // Record initial balance
        uint256 initialBalance = recipient.balance;

        // Call sendTokens from Flywheel
        vm.prank(address(flywheel));
        bool success = Campaign(payable(campaign)).sendTokens(Constants.NATIVE_TOKEN, recipient, amount);

        // Verify success and balance change
        assertTrue(success, "sendTokens should succeed for native token");
        assertEq(recipient.balance, initialBalance + amount, "Recipient should receive the native tokens");
    }

    /// @dev Verifies sendTokens succeeds for ERC20 token
    /// @param recipient Recipient address
    /// @param amount Amount to send
    function test_sendTokens_succeeds_forERC20Token(address recipient, uint256 amount) public {
        // Bound inputs
        // Bound inputs
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);
        vm.assume(recipient != campaign);

        vm.prank(owner);
        mockToken.transfer(campaign, amount);

        // Record initial balance (should be 0 for fresh address)
        uint256 initialBalance = mockToken.balanceOf(recipient);

        // Call sendTokens from Flywheel
        vm.prank(address(flywheel));
        bool success = Campaign(payable(campaign)).sendTokens(address(mockToken), recipient, amount);

        // Verify success and balance change
        assertTrue(success, "sendTokens should succeed for ERC20 token");
        assertEq(mockToken.balanceOf(recipient), initialBalance + amount, "Recipient should receive the ERC20 tokens");
    }

    /// @dev Verifies sendTokens returns false when send fails (ERC20)
    /// @param recipient Recipient address
    /// @param amount Amount to send
    function test_sendTokens_returnsFalseWhenSendFails_ERC20(address recipient, uint256 amount) public {
        // Bound inputs
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);

        // Do NOT fund the campaign, so transfer will fail
        // Campaign has 0 balance, trying to send will fail

        // Call sendTokens from Flywheel with insufficient balance
        vm.prank(address(flywheel));
        bool success = Campaign(payable(campaign)).sendTokens(address(mockToken), recipient, amount);

        // Verify it returns false when transfer fails
        assertFalse(success, "sendTokens should return false when ERC20 transfer fails due to insufficient balance");
    }

    /// @dev Verifies sendTokens returns false when send fails (native token)
    /// @param recipient Recipient address
    /// @param amount Amount to send
    function test_sendTokens_returnsFalseWhenSendFails_native(address recipient, uint256 amount) public {
        // Bound inputs
        recipient = boundToValidPayableAddress(recipient);
        amount = boundToValidAmount(amount);

        // Fund the campaign with native tokens
        vm.deal(campaign, amount);

        // Call sendTokens from Flywheel to the reverting contract
        vm.prank(address(flywheel));
        bool success =
            Campaign(payable(campaign)).sendTokens(Constants.NATIVE_TOKEN, address(revertingRecipient), amount);

        // Verify it returns false when native transfer fails
        assertFalse(success, "sendTokens should return false when native transfer fails");
    }
}
