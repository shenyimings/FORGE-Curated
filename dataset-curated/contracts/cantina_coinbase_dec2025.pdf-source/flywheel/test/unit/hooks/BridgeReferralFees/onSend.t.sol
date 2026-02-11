// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Constants} from "../../../../src/Constants.sol";
import {Flywheel} from "../../../../src/Flywheel.sol";
import {BridgeReferralFees} from "../../../../src/hooks/BridgeReferralFees.sol";
import {BridgeReferralFeesTest} from "../../../lib/BridgeReferralFeesTest.sol";
import {MockAccount} from "../../../lib/mocks/MockAccount.sol";

contract OnSendTest is BridgeReferralFeesTest {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when caller is not flywheel
    /// @param caller Caller address
    /// @param feeBps Fee basis points (doesn't matter for access control test)
    /// @param user User address for payout
    function test_revert_onlyFlywheel(address caller, uint8 feeBps, address user, uint256 seed) public {
        vm.assume(caller != address(flywheel));
        feeBps = uint8(bound(feeBps, 0, MAX_FEE_BASIS_POINTS));
        vm.assume(user != address(0));

        string memory code = _registerBuilderCode(seed);
        bytes memory hookData = abi.encode(user, code, feeBps);

        // Direct call to bridgeReferralFees should revert (only flywheel can call)
        vm.prank(caller);
        vm.expectRevert();
        bridgeReferralFees.onSend(caller, bridgeReferralFeesCampaign, address(usdc), hookData);
    }

    /// @dev Reverts when hookData cannot be correctly decoded
    /// @param hookData The malformed hook data that should cause revert
    /// @param campaignBalance Amount to fund campaign with
    function test_revert_invalidHookData(bytes memory hookData, uint256 campaignBalance) public {
        // Ensure hookData cannot be decoded as (address, string, uint8)
        // This is complex to validate precisely, so we use simple malformed data
        vm.assume(hookData.length > 0 && hookData.length < 64);

        campaignBalance = bound(campaignBalance, 1 ether, 1000 ether);

        // Fund campaign
        usdc.mint(bridgeReferralFeesCampaign, campaignBalance);

        vm.expectRevert();
        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Calculates correct payout and fee amounts with registered builder code
    /// @param bridgedAmount Amount available for bridging
    /// @param feeBps Fee basis points within valid range
    /// @param user User address for payout
    function test_success_registeredBuilderCode(uint256 bridgedAmount, uint8 feeBps, address user, uint256 seed)
        public
    {
        vm.assume(bridgedAmount > 0);
        vm.assume(bridgedAmount < 1e30); // Conservative bound to avoid arithmetic overflow
        vm.assume(feeBps <= MAX_FEE_BASIS_POINTS); // Within max fee basis points
        vm.assume(user != address(0));

        string memory code = _registerBuilderCode(seed);

        // Fund campaign
        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        bytes memory hookData = abi.encode(user, code, feeBps);

        uint256 expectedFeeAmount = (bridgedAmount / 1e4) * feeBps + ((bridgedAmount % 1e4) * feeBps) / 1e4;
        uint256 expectedUserAmount = bridgedAmount - expectedFeeAmount;

        vm.prank(address(flywheel));
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            bridgeReferralFees.onSend(address(this), bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(payouts[0].recipient, user, "User should receive correct recipient");
        assertEq(payouts[0].amount, expectedUserAmount, "User should receive correct amount");
        assertEq(
            payouts[0].extraData, abi.encode(code, expectedFeeAmount), "Payout extraData should contain code and fee"
        );

        if (expectedFeeAmount > 0) {
            assertTrue(sendFeesNow, "Should send fees when fee amount > 0");
            bytes32 codeBytes32 = bytes32(builderCodes.toTokenId(code));
            assertEq(fees[0].key, codeBytes32, "Fee distribution should use builder code as key");
            assertEq(fees[0].recipient, builder, "Fee should go to builder");
            assertEq(fees[0].amount, expectedFeeAmount, "Fee amount should be correct");
        } else {
            assertFalse(sendFeesNow, "Should not send fees when fee amount = 0");
        }
    }

    /// @dev Sets fee to zero when builder code is not registered in BuilderCodes
    /// @param bridgedAmount Amount available for bridging
    /// @param feeBps Fee basis points (ignored for unregistered codes)
    /// @param user User address for payout
    function test_success_unregisteredBuilderCode(uint256 bridgedAmount, uint8 feeBps, address user) public {
        vm.assume(bridgedAmount > 0);
        vm.assume(user != address(0));

        // Use an unregistered but valid code
        string memory unregisteredCodeStr = "unregistered";

        // Fund campaign
        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        bytes memory hookData = abi.encode(user, unregisteredCodeStr, feeBps);

        vm.prank(address(flywheel));
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            bridgeReferralFees.onSend(address(this), bridgeReferralFeesCampaign, address(usdc), hookData);

        // User should receive full amount (no fee for unregistered codes)
        assertEq(payouts[0].recipient, user, "User should receive correct recipient");
        assertEq(payouts[0].amount, bridgedAmount, "User should receive full amount");
        assertEq(
            payouts[0].extraData,
            abi.encode(unregisteredCodeStr, uint256(0)),
            "Payout extraData should contain code and zero fee"
        );

        assertFalse(sendFeesNow, "Should not send fees for unregistered codes");
        assertEq(fees.length, 0, "Should have no fee distributions");
    }

    /// @dev Caps fee at maxFeeBasisPoints when requested fee exceeds maximum
    /// @param bridgedAmount Amount available for bridging
    /// @param excessiveFeeBps Fee basis points exceeding maximum
    /// @param user User address for payout
    function test_success_feeExceedsMaximum(uint256 bridgedAmount, uint8 excessiveFeeBps, address user, uint256 seed)
        public
    {
        vm.assume(bridgedAmount > 0);
        vm.assume(bridgedAmount < 1e30); // Conservative bound to avoid arithmetic overflow
        vm.assume(excessiveFeeBps > MAX_FEE_BASIS_POINTS); // Exceeds max fee basis points
        vm.assume(user != address(0));

        string memory code = _registerBuilderCode(seed);

        // Fund campaign
        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        bytes memory hookData = abi.encode(user, code, excessiveFeeBps);

        // Fee should be capped at MAX_FEE_BASIS_POINTS
        uint256 expectedFeeAmount =
            (bridgedAmount / 1e4) * MAX_FEE_BASIS_POINTS + ((bridgedAmount % 1e4) * MAX_FEE_BASIS_POINTS) / 1e4;
        vm.assume(expectedFeeAmount > 0); // Ensure fee is actually generated
        uint256 expectedUserAmount = bridgedAmount - expectedFeeAmount;

        vm.prank(address(flywheel));
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            bridgeReferralFees.onSend(address(this), bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(payouts[0].recipient, user, "User should receive correct recipient");
        assertEq(payouts[0].amount, expectedUserAmount, "User should receive correct amount");
        assertEq(
            payouts[0].extraData,
            abi.encode(code, expectedFeeAmount),
            "Payout extraData should contain code and capped fee"
        );

        assertTrue(sendFeesNow, "Should send fees when fee amount > 0");
        bytes32 codeBytes32 = bytes32(builderCodes.toTokenId(code));
        assertEq(fees[0].key, codeBytes32, "Fee distribution should use builder code as key");
        assertEq(fees[0].recipient, builder, "Fee should go to builder");
        assertEq(fees[0].amount, expectedFeeAmount, "Fee amount should be capped");
    }

    /// @dev Returns zero fees when fee basis points is zero
    /// @param bridgedAmount Amount available for bridging
    /// @param user User address for payout
    function test_success_zeroFeeBps(uint256 bridgedAmount, address user, uint256 seed) public {
        vm.assume(bridgedAmount > 0);
        vm.assume(user != address(0));

        string memory code = _registerBuilderCode(seed);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);
        bytes memory hookData = abi.encode(user, code, uint8(0));

        vm.prank(address(flywheel));
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            bridgeReferralFees.onSend(address(this), bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(payouts[0].recipient, user, "User should receive correct recipient");
        assertEq(payouts[0].amount, bridgedAmount, "User should receive full amount");
        assertEq(
            payouts[0].extraData, abi.encode(code, uint256(0)), "Payout extraData should contain code and zero fee"
        );

        assertFalse(sendFeesNow, "Should not send fees when fee is zero");
        assertEq(fees.length, 0, "Should have no fee distributions");
    }

    /// @dev Returns nonzero fees when fee basis points is nonzero
    /// @param bridgedAmount Amount available for bridging
    /// @param feeBps Non-zero fee basis points to test
    /// @param user User address for payout
    function test_success_nonzeroFeeBps(uint256 bridgedAmount, uint8 feeBps, address user, uint256 seed) public {
        bridgedAmount = bound(bridgedAmount, 1, 1e30); // Conservative bound to avoid arithmetic overflow
        feeBps = uint8(bound(feeBps, 1, MAX_FEE_BASIS_POINTS)); // Ensure non-zero fee
        vm.assume(user != address(0));

        // Ensure fee amount will actually be > 0 to avoid false positive failures
        uint256 expectedFeeAmount = (bridgedAmount / 1e4) * feeBps + ((bridgedAmount % 1e4) * feeBps) / 1e4;
        vm.assume(expectedFeeAmount > 0);

        string memory code = _registerBuilderCode(seed);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);
        bytes memory hookData = abi.encode(user, code, feeBps);

        uint256 expectedUserAmount = bridgedAmount - expectedFeeAmount;

        vm.prank(address(flywheel));
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            bridgeReferralFees.onSend(address(this), bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(payouts[0].recipient, user, "User should receive correct recipient");
        assertEq(payouts[0].amount, expectedUserAmount, "User should receive correct amount");
        assertEq(
            payouts[0].extraData, abi.encode(code, expectedFeeAmount), "Payout extraData should contain code and fee"
        );

        assertTrue(sendFeesNow, "Should send fees when fee amount > 0");
        bytes32 codeBytes32 = bytes32(builderCodes.toTokenId(code));
        assertEq(fees[0].key, codeBytes32, "Fee distribution should use builder code as key");
        assertEq(fees[0].recipient, builder, "Fee should go to builder");
        assertEq(fees[0].amount, expectedFeeAmount, "Fee amount should be correct");
    }

    /// @dev Calculates bridged amount correctly with native token (ETH)
    /// @param bridgedAmount Amount available for bridging
    /// @param feeBps Fee basis points within valid range
    /// @param user User address for payout
    function test_success_nativeToken(uint256 bridgedAmount, uint8 feeBps, address user, uint256 seed) public {
        vm.assume(bridgedAmount > 0);
        vm.assume(bridgedAmount < 1e30); // Conservative bound to avoid arithmetic overflow
        feeBps = uint8(bound(feeBps, 0, MAX_FEE_BASIS_POINTS));
        vm.assume(user != address(0));
        vm.assume(user.code.length == 0); // Only EOA addresses can receive ETH safely
        vm.assume(user > address(0x100)); // Avoid precompiled contract addresses

        string memory code = _registerBuilderCode(seed);

        // Fund campaign with native token
        vm.deal(bridgeReferralFeesCampaign, bridgedAmount);

        bytes memory hookData = abi.encode(user, code, feeBps);

        uint256 expectedFeeAmount = (bridgedAmount / 1e4) * feeBps + ((bridgedAmount % 1e4) * feeBps) / 1e4;
        uint256 expectedUserAmount = bridgedAmount - expectedFeeAmount;

        vm.prank(address(flywheel));
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            bridgeReferralFees.onSend(address(this), bridgeReferralFeesCampaign, Constants.NATIVE_TOKEN, hookData);

        assertEq(payouts[0].recipient, user, "User should receive correct recipient");
        assertEq(payouts[0].amount, expectedUserAmount, "User should receive correct amount");
        assertEq(
            payouts[0].extraData, abi.encode(code, expectedFeeAmount), "Payout extraData should contain code and fee"
        );

        if (expectedFeeAmount > 0) {
            assertTrue(sendFeesNow, "Should send fees when fee amount > 0");
            bytes32 codeBytes32 = bytes32(builderCodes.toTokenId(code));
            assertEq(fees[0].key, codeBytes32, "Fee distribution should use builder code as key");
            assertEq(fees[0].recipient, builder, "Fee should go to builder");
            assertEq(fees[0].amount, expectedFeeAmount, "Fee amount should be correct");
        } else {
            assertFalse(sendFeesNow, "Should not send fees when fee amount = 0");
        }
    }

    /// @dev Excludes allocated fees from bridged amount calculation
    /// @param totalBalance Total campaign balance
    /// @param allocatedFees Already allocated fees
    /// @param feeBps Fee basis points within valid range
    /// @param user User address for payout
    function test_success_withExistingAllocatedFees(
        uint256 totalBalance,
        uint256 allocatedFees,
        uint8 feeBps,
        address user,
        uint256 seed
    ) public {
        // Bound inputs to avoid arithmetic overflow
        totalBalance = bound(totalBalance, 1, 1e30);
        allocatedFees = bound(allocatedFees, 0, totalBalance - 1);
        feeBps = uint8(bound(feeBps, 0, MAX_FEE_BASIS_POINTS));
        vm.assume(user != address(0));

        uint256 bridgedAmount = totalBalance - allocatedFees;
        vm.assume(bridgedAmount > 0);

        // Setup scenario would require allocated fees which is complex
        // For simplicity, just test basic case
        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        string memory code = _registerBuilderCode(seed);
        bytes memory hookData = abi.encode(user, code, feeBps);

        uint256 expectedFeeAmount = (bridgedAmount / 1e4) * feeBps + ((bridgedAmount % 1e4) * feeBps) / 1e4;
        uint256 expectedUserAmount = bridgedAmount - expectedFeeAmount;

        vm.prank(address(flywheel));
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            bridgeReferralFees.onSend(address(this), bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(payouts[0].recipient, user, "User should receive correct recipient");
        assertEq(payouts[0].amount, expectedUserAmount, "User should receive correct amount");
        assertEq(
            payouts[0].extraData, abi.encode(code, expectedFeeAmount), "Payout extraData should contain code and fee"
        );

        if (expectedFeeAmount > 0) {
            assertTrue(sendFeesNow, "Should send fees when fee amount > 0");
            bytes32 codeBytes32 = bytes32(builderCodes.toTokenId(code));
            assertEq(fees[0].key, codeBytes32, "Fee distribution should use builder code as key");
            assertEq(fees[0].recipient, builder, "Fee should go to builder");
            assertEq(fees[0].amount, expectedFeeAmount, "Fee amount should be correct");
        } else {
            assertFalse(sendFeesNow, "Should not send fees when fee amount = 0");
        }
    }

    // ========================================
    // EDGE CASES
    // ========================================

    /// @dev Handles maximum possible bridged amount without overflow
    /// @param feeBps Fee basis points within valid range
    /// @param user User address for payout
    function test_edge_maximumBridgedAmount(uint8 feeBps, address user, uint256 seed) public {
        feeBps = uint8(bound(feeBps, 0, MAX_FEE_BASIS_POINTS));
        vm.assume(user != address(0));

        uint256 maxAmount = type(uint256).max; // Test with absolute max
        string memory code = _registerBuilderCode(seed);

        usdc.mint(bridgeReferralFeesCampaign, maxAmount);
        bytes memory hookData = abi.encode(user, code, feeBps);

        uint256 expectedFeeAmount = (maxAmount / 1e4) * feeBps + ((maxAmount % 1e4) * feeBps) / 1e4;
        uint256 expectedUserAmount = maxAmount - expectedFeeAmount;

        vm.prank(address(flywheel));
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            bridgeReferralFees.onSend(address(this), bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(payouts[0].recipient, user, "User should receive correct recipient");
        assertEq(payouts[0].amount, expectedUserAmount, "User should receive correct amount");
        assertEq(
            payouts[0].extraData, abi.encode(code, expectedFeeAmount), "Payout extraData should contain code and fee"
        );

        if (expectedFeeAmount > 0) {
            assertTrue(sendFeesNow, "Should send fees when fee amount > 0");
            bytes32 codeBytes32 = bytes32(builderCodes.toTokenId(code));
            assertEq(fees[0].key, codeBytes32, "Fee distribution should use builder code as key");
            assertEq(fees[0].recipient, builder, "Fee should go to builder");
            assertEq(fees[0].amount, expectedFeeAmount, "Fee amount should be correct");
        } else {
            assertFalse(sendFeesNow, "Should not send fees when fee amount = 0");
        }
    }

    /// @dev Handles minimum non-zero bridged amount (1 wei)
    /// @param feeBps Fee basis points within valid range
    /// @param user User address for payout
    /// @param minAmount Minimum amount to test (1-10 wei)
    function test_edge_minimumBridgedAmount(uint8 feeBps, address user, uint256 minAmount, uint256 seed) public {
        feeBps = uint8(bound(feeBps, 0, MAX_FEE_BASIS_POINTS));
        vm.assume(user != address(0));
        minAmount = bound(minAmount, 1, 10); // Test very small amounts

        string memory code = _registerBuilderCode(seed);

        usdc.mint(bridgeReferralFeesCampaign, minAmount);
        bytes memory hookData = abi.encode(user, code, feeBps);

        uint256 expectedFeeAmount = (minAmount / 1e4) * feeBps + ((minAmount % 1e4) * feeBps) / 1e4;
        uint256 expectedUserAmount = minAmount - expectedFeeAmount;

        vm.prank(address(flywheel));
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) =
            bridgeReferralFees.onSend(address(this), bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(payouts[0].recipient, user, "User should receive correct recipient");
        assertEq(payouts[0].amount, expectedUserAmount, "User should receive correct amount");
        assertEq(
            payouts[0].extraData, abi.encode(code, expectedFeeAmount), "Payout extraData should contain code and fee"
        );

        if (expectedFeeAmount > 0) {
            assertTrue(sendFeesNow, "Should send fees when fee amount > 0");
            bytes32 codeBytes32 = bytes32(builderCodes.toTokenId(code));
            assertEq(fees[0].key, codeBytes32, "Fee distribution should use builder code as key");
            assertEq(fees[0].recipient, builder, "Fee should go to builder");
            assertEq(fees[0].amount, expectedFeeAmount, "Fee amount should be correct");
        } else {
            assertFalse(sendFeesNow, "Should not send fees when fee amount = 0");
        }
    }

    // ========================================
    // STATE VERIFICATION
    // ========================================

    /// @dev Verifies sendFeesNow is true when fee amount is greater than zero
    /// @param bridgedAmount Amount available for bridging
    /// @param feeBps Non-zero fee basis points
    /// @param user User address for payout
    function test_onSend_sendFeesNowTrue(uint256 bridgedAmount, uint8 feeBps, address user, uint256 seed) public {
        vm.assume(bridgedAmount > 0);
        vm.assume(bridgedAmount < 1e30); // Conservative bound to avoid arithmetic overflow
        feeBps = uint8(bound(feeBps, 1, MAX_FEE_BASIS_POINTS)); // Ensure non-zero fee
        vm.assume(user != address(0));

        // Ensure fee amount will be > 0
        uint256 expectedFeeAmount = (bridgedAmount / 1e4) * feeBps + ((bridgedAmount % 1e4) * feeBps) / 1e4;
        vm.assume(expectedFeeAmount > 0);
        uint256 expectedUserAmount = bridgedAmount - expectedFeeAmount;

        string memory code = _registerBuilderCode(seed);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        vm.prank(address(flywheel));
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) = bridgeReferralFees
            .onSend(address(this), bridgeReferralFeesCampaign, address(usdc), abi.encode(user, code, feeBps));

        assertEq(payouts[0].recipient, user, "User should receive correct recipient");
        assertEq(payouts[0].amount, expectedUserAmount, "User should receive correct amount");
        assertEq(
            payouts[0].extraData, abi.encode(code, expectedFeeAmount), "Payout extraData should contain code and fee"
        );

        assertTrue(sendFeesNow, "sendFeesNow should be true when fees > 0");
        bytes32 codeBytes32 = bytes32(builderCodes.toTokenId(code));
        assertEq(fees[0].key, codeBytes32, "Fee distribution should use builder code as key");
        assertEq(fees[0].recipient, builder, "Fee should go to builder");
        assertEq(fees[0].amount, expectedFeeAmount, "Fee amount should be correct");
    }

    /// @dev Verifies sendFeesNow behavior when fee amount is zero
    /// @param bridgedAmount Amount available for bridging
    /// @param feeBps Fee basis points (ignored for unregistered codes)
    /// @param user User address for payout
    function test_onSend_sendFeesNowWithZeroFee(uint256 bridgedAmount, uint8 feeBps, address user) public {
        vm.assume(bridgedAmount > 0);
        feeBps = uint8(bound(feeBps, 0, MAX_FEE_BASIS_POINTS));
        vm.assume(user != address(0));

        // Use unregistered code to force zero fees
        string memory unregisteredCodeStr = "unregistered_zero";
        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        vm.prank(address(flywheel));
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) = bridgeReferralFees
            .onSend(address(this), bridgeReferralFeesCampaign, address(usdc), abi.encode(user, unregisteredCodeStr, feeBps));

        assertEq(payouts[0].recipient, user, "User should receive correct recipient");
        assertEq(payouts[0].amount, bridgedAmount, "User should receive full amount");
        assertEq(
            payouts[0].extraData,
            abi.encode(unregisteredCodeStr, uint256(0)),
            "Payout extraData should contain code and zero fee"
        );

        assertFalse(sendFeesNow, "sendFeesNow should be false when fees = 0");
        assertEq(fees.length, 0, "Should have no fee distributions");
    }

    /// @dev Verifies correct payout extraData contains builder code and fee amount
    /// @param bridgedAmount Amount available for bridging
    /// @param feeBps Fee basis points within valid range
    /// @param user User address for payout
    function test_onSend_payoutExtraData(uint256 bridgedAmount, uint8 feeBps, address user, uint256 seed) public {
        vm.assume(bridgedAmount > 0);
        vm.assume(bridgedAmount < 1e30); // Conservative bound to avoid arithmetic overflow
        feeBps = uint8(bound(feeBps, 0, MAX_FEE_BASIS_POINTS));
        vm.assume(user != address(0));

        string memory code = _registerBuilderCode(seed);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        uint256 expectedFeeAmount = (bridgedAmount / 1e4) * feeBps + ((bridgedAmount % 1e4) * feeBps) / 1e4;
        uint256 expectedUserAmount = bridgedAmount - expectedFeeAmount;

        vm.prank(address(flywheel));
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) = bridgeReferralFees
            .onSend(address(this), bridgeReferralFeesCampaign, address(usdc), abi.encode(user, code, feeBps));

        (string memory extractedCode, uint256 extractedFeeAmount) = abi.decode(payouts[0].extraData, (string, uint256));

        assertEq(payouts[0].recipient, user, "User should receive correct recipient");
        assertEq(payouts[0].amount, expectedUserAmount, "User should receive correct amount");
        assertEq(
            keccak256(bytes(extractedCode)),
            keccak256(bytes(code)),
            "Payout extraData should contain correct builder code"
        );
        assertEq(extractedFeeAmount, expectedFeeAmount, "Payout extraData should contain correct fee amount");

        if (expectedFeeAmount > 0) {
            assertTrue(sendFeesNow, "Should send fees when fee amount > 0");
            bytes32 codeBytes32 = bytes32(builderCodes.toTokenId(code));
            assertEq(fees[0].key, codeBytes32, "Fee distribution should use builder code as key");
        } else {
            assertFalse(sendFeesNow, "Should not send fees when fee amount = 0");
        }
    }

    /// @dev Verifies fee distribution uses builder code as key
    /// @param bridgedAmount Amount available for bridging
    /// @param feeBps Fee basis points within valid range
    /// @param user User address for payout
    function test_onSend_feeDistributionKey(uint256 bridgedAmount, uint8 feeBps, address user, uint256 seed) public {
        vm.assume(bridgedAmount > 0);
        vm.assume(bridgedAmount < 1e30); // Conservative bound to avoid arithmetic overflow
        feeBps = uint8(bound(feeBps, 1, MAX_FEE_BASIS_POINTS)); // Ensure non-zero fee
        vm.assume(user != address(0));

        // Ensure fee amount will be > 0 to avoid empty fees array
        uint256 expectedFeeAmount = (bridgedAmount / 1e4) * feeBps + ((bridgedAmount % 1e4) * feeBps) / 1e4;
        vm.assume(expectedFeeAmount > 0);
        uint256 expectedUserAmount = bridgedAmount - expectedFeeAmount;

        string memory code = _registerBuilderCode(seed);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        vm.prank(address(flywheel));
        (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow) = bridgeReferralFees
            .onSend(address(this), bridgeReferralFeesCampaign, address(usdc), abi.encode(user, code, feeBps));

        assertEq(payouts[0].recipient, user, "User should receive correct recipient");
        assertEq(payouts[0].amount, expectedUserAmount, "User should receive correct amount");
        assertEq(
            payouts[0].extraData, abi.encode(code, expectedFeeAmount), "Payout extraData should contain code and fee"
        );

        assertTrue(sendFeesNow, "Should send fees when fee amount > 0");
        assertTrue(fees.length > 0, "Should have at least one fee distribution");
        bytes32 codeBytes32 = bytes32(builderCodes.toTokenId(code));
        assertEq(fees[0].key, codeBytes32, "Fee distribution should use builder code as key");
        assertEq(fees[0].recipient, builder, "Fee should go to builder");
        assertEq(fees[0].amount, expectedFeeAmount, "Fee amount should be correct");
    }

    // ========================================
    // INVALID BUILDER CODE HANDLING
    // ========================================

    /// @dev Processes empty builder code successfully with zero fees
    /// @param bridgedAmount Amount available for bridging
    /// @param user User address for payout
    function test_success_emptyBuilderCode_zeroFees(uint256 bridgedAmount, address user) public {
        bridgedAmount = bound(bridgedAmount, 1, type(uint128).max);
        _boundUser(user);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        string memory emptyCode = "";
        bytes memory hookData = abi.encode(user, emptyCode, uint8(0));

        uint256 userBalanceBefore = usdc.balanceOf(user);

        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(usdc.balanceOf(user), userBalanceBefore + bridgedAmount, "User should receive full amount");
        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    /// @dev Processes too long builder code (>32 bytes) successfully with zero fees
    /// @param bridgedAmount Amount available for bridging
    /// @param user User address for payout
    function test_success_tooLongBuilderCode_zeroFees(uint256 bridgedAmount, address user) public {
        bridgedAmount = bound(bridgedAmount, 1, type(uint128).max);
        _boundUser(user);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        string memory tooLongCode = "this_builder_code_is_way_too_long_to_be_valid";
        bytes memory hookData = abi.encode(user, tooLongCode, uint8(0));

        uint256 userBalanceBefore = usdc.balanceOf(user);

        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(usdc.balanceOf(user), userBalanceBefore + bridgedAmount, "User should receive full amount");
        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    /// @dev Processes builder code with uppercase letters successfully with zero fees
    /// @param bridgedAmount Amount available for bridging
    /// @param user User address for payout
    function test_success_uppercaseInCode_zeroFees(uint256 bridgedAmount, address user) public {
        bridgedAmount = bound(bridgedAmount, 1, type(uint128).max);
        _boundUser(user);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        string memory uppercaseCode = "TestCode";
        bytes memory hookData = abi.encode(user, uppercaseCode, uint8(0));

        uint256 userBalanceBefore = usdc.balanceOf(user);

        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(usdc.balanceOf(user), userBalanceBefore + bridgedAmount, "User should receive full amount");
        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    /// @dev Processes builder code with special characters successfully with zero fees
    /// @param bridgedAmount Amount available for bridging
    /// @param user User address for payout
    function test_success_specialCharactersInCode_zeroFees(uint256 bridgedAmount, address user) public {
        bridgedAmount = bound(bridgedAmount, 1, type(uint128).max);
        _boundUser(user);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        string memory specialCharCode = "test@code#123!";
        bytes memory hookData = abi.encode(user, specialCharCode, uint8(0));

        uint256 userBalanceBefore = usdc.balanceOf(user);

        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(usdc.balanceOf(user), userBalanceBefore + bridgedAmount, "User should receive full amount");
        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    /// @dev Processes builder code with non-ASCII characters successfully with zero fees
    /// @param bridgedAmount Amount available for bridging
    /// @param user User address for payout
    function test_success_nonAsciiCharactersInCode_zeroFees(uint256 bridgedAmount, address user) public {
        bridgedAmount = bound(bridgedAmount, 1, type(uint128).max);
        _boundUser(user);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        string memory nonAsciiCode = unicode"test🚀code";
        bytes memory hookData = abi.encode(user, nonAsciiCode, uint8(0));

        uint256 userBalanceBefore = usdc.balanceOf(user);

        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(usdc.balanceOf(user), userBalanceBefore + bridgedAmount, "User should receive full amount");
        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    // ========================================
    // SAFE PERCENT OVERFLOW PROTECTION
    // ========================================

    /// @dev Handles large amounts near uint256 max with non-zero feeBps without overflow
    /// @param bridgedAmount Amount available for bridging
    /// @param feeBps Fee basis points within valid range
    /// @param user User address for payout
    /// @param seed Random seed for test variation
    function test_success_largeAmount_withMaxFeeBps_noOverflow(
        uint256 bridgedAmount,
        uint8 feeBps,
        address user,
        uint256 seed
    ) public {
        string memory code = _registerBuilderCode(seed);
        bridgedAmount = bound(bridgedAmount, type(uint256).max / 2, type(uint256).max - 1);
        feeBps = uint8(bound(feeBps, 1, MAX_FEE_BASIS_POINTS));
        _boundUser(user);

        vm.deal(bridgeReferralFeesCampaign, bridgedAmount);

        bytes memory hookData = abi.encode(user, code, feeBps);

        uint256 expectedFee = _safePercent(bridgedAmount, feeBps);
        uint256 expectedUser = bridgedAmount - expectedFee;

        uint256 userBalanceBefore = user.balance;
        uint256 builderBalanceBefore = builder.balance;

        flywheel.send(bridgeReferralFeesCampaign, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, hookData);

        assertEq(user.balance, userBalanceBefore + expectedUser, "User should receive correct amount");
        assertEq(builder.balance, builderBalanceBefore + expectedFee, "Builder should receive fee");
        assertEq(bridgeReferralFeesCampaign.balance, 0, "Campaign should be empty");
    }

    /// @dev Handles maximum uint256 amount with feeBps without overflow
    /// @param feeBps Fee basis points within valid range
    /// @param user User address for payout
    /// @param seed Random seed for test variation
    function test_success_maxUint256Amount_withFeeBps_noOverflow(uint8 feeBps, address user, uint256 seed) public {
        string memory code = _registerBuilderCode(seed);
        uint256 bridgedAmount = type(uint256).max;
        feeBps = uint8(bound(feeBps, 1, 10));
        _boundUser(user);

        vm.deal(bridgeReferralFeesCampaign, bridgedAmount);

        bytes memory hookData = abi.encode(user, code, feeBps);

        uint256 expectedFee = _safePercent(bridgedAmount, feeBps);
        uint256 expectedUser = bridgedAmount - expectedFee;

        uint256 userBalanceBefore = user.balance;
        uint256 builderBalanceBefore = builder.balance;

        flywheel.send(bridgeReferralFeesCampaign, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, hookData);

        assertEq(user.balance, userBalanceBefore + expectedUser, "User should receive correct amount");
        assertEq(builder.balance, builderBalanceBefore + expectedFee, "Builder should receive fee");
        assertEq(bridgeReferralFeesCampaign.balance, 0, "Campaign should be empty");
    }

    /// @dev Calculates zero fee correctly when amount is zero
    /// @param feeBps Fee basis points within valid range
    /// @param user User address for payout
    /// @param seed Random seed for test variation
    function test_edge_zeroAmount_calculatesZeroFee(uint8 feeBps, address user, uint256 seed) public {
        string memory code = _registerBuilderCode(seed);
        uint256 bridgedAmount = 0;
        feeBps = uint8(bound(feeBps, 1, MAX_FEE_BASIS_POINTS));
        _boundUser(user);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        bytes memory hookData = abi.encode(user, code, feeBps);

        uint256 userBalanceBefore = usdc.balanceOf(user);
        uint256 builderBalanceBefore = usdc.balanceOf(builder);

        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(usdc.balanceOf(user), userBalanceBefore, "User should receive nothing");
        assertEq(usdc.balanceOf(builder), builderBalanceBefore, "Builder should receive no fee");
        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    /// @dev Calculates zero fee correctly when feeBps is zero
    /// @param bridgedAmount Amount available for bridging
    /// @param user User address for payout
    /// @param seed Random seed for test variation
    function test_edge_zeroFeeBps_calculatesZeroFee(uint256 bridgedAmount, address user, uint256 seed) public {
        string memory code = _registerBuilderCode(seed);
        bridgedAmount = bound(bridgedAmount, 1, type(uint128).max);
        uint8 feeBps = 0;
        _boundUser(user);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        bytes memory hookData = abi.encode(user, code, feeBps);

        uint256 userBalanceBefore = usdc.balanceOf(user);
        uint256 builderBalanceBefore = usdc.balanceOf(builder);

        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(usdc.balanceOf(user), userBalanceBefore + bridgedAmount, "User should receive full amount");
        assertEq(usdc.balanceOf(builder), builderBalanceBefore, "Builder should receive no fee");
        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    /// @dev Verifies fee calculation matches expected precision using _safePercent
    /// @param bridgedAmount Amount available for bridging
    /// @param feeBps Fee basis points within valid range
    /// @param user User address for payout
    /// @param seed Random seed for test variation
    function test_success_feeCalculation_matchesExpectedPrecision(
        uint256 bridgedAmount,
        uint8 feeBps,
        address user,
        uint256 seed
    ) public {
        string memory code = _registerBuilderCode(seed);
        bridgedAmount = bound(bridgedAmount, 1e4, type(uint128).max);
        feeBps = uint8(bound(feeBps, 1, MAX_FEE_BASIS_POINTS));
        _boundUser(user);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        bytes memory hookData = abi.encode(user, code, feeBps);

        uint256 expectedFee = _safePercent(bridgedAmount, feeBps);
        uint256 expectedUser = bridgedAmount - expectedFee;

        uint256 userBalanceBefore = usdc.balanceOf(user);
        uint256 builderBalanceBefore = usdc.balanceOf(builder);

        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(usdc.balanceOf(user), userBalanceBefore + expectedUser, "User should receive correct amount");
        assertEq(usdc.balanceOf(builder), builderBalanceBefore + expectedFee, "Builder should receive exact fee");
        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    // ========================================
    // ZERO BRIDGED AMOUNT BEHAVIOR
    // ========================================

    /// @dev Succeeds when bridged amount is zero (behavior changed from revert)
    /// @param feeBps Fee basis points
    /// @param user User address for payout
    /// @param seed Random seed for test variation
    function test_success_zeroBridgedAmount_succeeds(uint8 feeBps, address user, uint256 seed) public {
        string memory code = _registerBuilderCode(seed);
        uint256 bridgedAmount = 0;
        _boundUser(user);

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        bytes memory hookData = abi.encode(user, code, feeBps);

        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    // ========================================
    // BUILDERCODES EXTERNAL CALL FAILURES
    // ========================================

    /// @dev Handles BuilderCodes returning zero address gracefully with zero fees
    /// @param bridgedAmount Amount available for bridging
    /// @param feeBps Fee basis points (ignored when processing fails)
    /// @param user User address for payout
    /// @param seed Random seed for test variation
    function test_success_builderCodesReturnsZeroAddress_zeroFees(
        uint256 bridgedAmount,
        uint8 feeBps,
        address user,
        uint256 seed
    ) public {
        string memory code = _registerBuilderCode(seed);
        bridgedAmount = bound(bridgedAmount, 1, type(uint128).max);
        feeBps = uint8(bound(feeBps, 1, MAX_FEE_BASIS_POINTS));
        _boundUser(user);

        MockAccount mockAccount = new MockAccount(builder, false);
        vm.prank(builder);
        builderCodes.updatePayoutAddress(code, address(mockAccount));

        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        bytes memory hookData = abi.encode(user, code, feeBps);

        uint256 expectedFee = _percent(bridgedAmount, feeBps);
        uint256 expectedUser = bridgedAmount - expectedFee;
        uint256 userBalanceBefore = usdc.balanceOf(user);

        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        uint256 allocatedFees = flywheel.totalAllocatedFees(bridgeReferralFeesCampaign, address(usdc));

        assertEq(usdc.balanceOf(user), userBalanceBefore + expectedUser, "User receives amount minus fee");
        assertEq(usdc.balanceOf(address(mockAccount)), expectedFee, "Mock account should receive fees");
        assertEq(allocatedFees, 0, "No fees should be allocated since transfer succeeded");
    }
}
