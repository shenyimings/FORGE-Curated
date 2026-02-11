// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../../../src/Flywheel.sol";
import {FlywheelTest} from "../../lib/FlywheelTestBase.sol";
import {MockCampaignHooksWithFees} from "../../lib/mocks/MockCampaignHooksWithFees.sol";

/// @title PredictCampaignAddressTest
/// @notice Tests for Flywheel.predictCampaignAddress
contract PredictCampaignAddressTest is FlywheelTest {
    function setUp() public {
        setUpFlywheelBase();
    }

    /// @dev Predicts address deterministically given hooks, nonce, and hookData
    /// @param hooks Hooks address
    /// @param hookData Encoded SimpleRewards hook data (owner, manager, uri)
    /// @param nonce Deterministic salt used by predict/create
    function test_matchesActual(address hooks, bytes memory hookData, uint256 nonce) public {
        // Use the real hooks contract deployed in setUp to satisfy isContract checks
        hooks = address(mockCampaignHooksWithFees);

        // Predict the campaign address
        address predictedAddress = flywheel.predictCampaignAddress(hooks, nonce, hookData);
        vm.assertEq(predictedAddress.code.length, 0);
        // Mock the hooks contract to avoid revert in onCreateCampaign
        // Optional: ensure onCreateCampaign call succeeds regardless of hook logic
        vm.mockCall(
            hooks,
            0,
            abi.encodeWithSelector(
                mockCampaignHooksWithFees.onCreateCampaign.selector, predictedAddress, nonce, hookData
            ),
            hex""
        );

        // Create the campaign and verify it matches the prediction
        address actualAddress = flywheel.createCampaign(hooks, nonce, hookData);
        vm.assertTrue(predictedAddress.code.length > 0);
        assertEq(actualAddress, predictedAddress, "Actual address should match predicted address");
    }

    /// @dev Address changes when nonce changes (same hooks and hookData)
    /// @param hooks Hooks address
    /// @param hookData Encoded SimpleRewards hook data (owner, manager, uri)
    /// @param nonce1 First nonce
    /// @param nonce2 Second nonce
    function test_changesWithNonce(address hooks, bytes memory hookData, uint256 nonce1, uint256 nonce2) public view {
        vm.assume(hooks != address(0)); // Avoid zero address
        vm.assume(nonce1 != nonce2); // Ensure nonces are different

        // Predict addresses with different nonces
        address address1 = flywheel.predictCampaignAddress(hooks, nonce1, hookData);
        address address2 = flywheel.predictCampaignAddress(hooks, nonce2, hookData);

        // Addresses should be different when nonces differ
        assertTrue(address1 != address2, "Addresses should be different for different nonces");
    }

    /// @dev Address changes when hookData changes (same hooks and nonce)
    /// @param hooks Hooks address
    /// @param hookData1 First hook data blob
    /// @param hookData2 Second hook data blob
    /// @param nonce Deterministic salt used by predict/create
    function test_changesWithHookData(address hooks, bytes memory hookData1, bytes memory hookData2, uint256 nonce)
        public
        view
    {
        vm.assume(hooks != address(0)); // Avoid zero address
        vm.assume(keccak256(hookData1) != keccak256(hookData2)); // Ensure hookData is different

        // Predict addresses with different hookData
        address address1 = flywheel.predictCampaignAddress(hooks, nonce, hookData1);
        address address2 = flywheel.predictCampaignAddress(hooks, nonce, hookData2);

        // Addresses should be different when hookData differs
        assertTrue(address1 != address2, "Addresses should be different for different hookData");
    }

    /// @dev Address changes when hooks change (different hook instances)
    /// @param hooks1 First hooks address
    /// @param hooks2 Second hooks address
    /// @param hookData Encoded SimpleRewards hook data (owner, manager, uri)
    /// @param nonce Deterministic salt used by predict/create
    function test_changesWithHooks(address hooks1, address hooks2, bytes memory hookData, uint256 nonce) public view {
        vm.assume(hooks1 != address(0)); // Avoid zero address
        vm.assume(hooks2 != address(0)); // Avoid zero address
        vm.assume(hooks1 != hooks2); // Ensure hooks are different

        // Predict addresses with different hooks
        address address1 = flywheel.predictCampaignAddress(hooks1, nonce, hookData);
        address address2 = flywheel.predictCampaignAddress(hooks2, nonce, hookData);

        // Addresses should be different when hooks differ
        assertTrue(address1 != address2, "Addresses should be different for different hooks");
    }
}
