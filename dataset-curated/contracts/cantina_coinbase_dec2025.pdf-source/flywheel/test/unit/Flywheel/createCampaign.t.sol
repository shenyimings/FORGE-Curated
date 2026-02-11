// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../../../src/Flywheel.sol";
import {FlywheelTest} from "../../lib/FlywheelTestBase.sol";
import {MockCampaignHooksWithFees} from "../../lib/mocks/MockCampaignHooksWithFees.sol";

/// @title CreateCampaignTest
/// @notice Tests for Flywheel.createCampaign
contract CreateCampaignTest is FlywheelTest {
    function setUp() public {
        setUpFlywheelBase();
    }

    /// @dev Expects ZeroAddress error
    /// @dev Reverts when hooks address is zero
    /// @param nonce Deterministic salt used by createCampaign
    /// @param hookData Stub encoded SimpleRewards hook data (owner, manager, uri)
    function test_reverts_whenHooksZeroAddress(uint256 nonce, bytes memory hookData) public {
        vm.expectRevert(Flywheel.ZeroAddress.selector);
        flywheel.createCampaign(address(0), nonce, hookData);
    }

    /// @dev Deploys a campaign clone deterministically and verifies new code exists at returned address
    /// @param nonce Deterministic salt used by createCampaign
    /// @param owner Campaign owner
    /// @param manager Campaign manager
    /// @param uri Campaign URI
    function test_deploysClone_deterministicAddress(uint256 nonce, address owner, address manager, string memory uri)
        public
    {
        // Predict the campaign address
        bytes memory hookData = abi.encode(owner, manager, uri);
        address predictedAddress = flywheel.predictCampaignAddress(address(mockCampaignHooksWithFees), nonce, hookData);

        // Verify no code exists at the predicted address initially
        assertEq(predictedAddress.code.length, 0, "Address should have no code initially");

        // Create the campaign
        address actualAddress = flywheel.createCampaign(address(mockCampaignHooksWithFees), nonce, hookData);

        // Verify the addresses match
        assertEq(actualAddress, predictedAddress, "Actual address should match predicted address");

        // Verify code exists at the address after deployment
        assertTrue(actualAddress.code.length > 0, "Campaign should have code after deployment");
    }

    /// @dev Reuses existing campaign if already deployed with same salt
    /// @dev Verifies idempotency: returns existing campaign without reverting
    /// @param nonce Deterministic salt used by createCampaign
    /// @param owner Campaign owner
    /// @param manager Campaign manager
    /// @param uri Campaign URI
    function test_returnsExisting_whenAlreadyDeployed(uint256 nonce, address owner, address manager, string memory uri)
        public
    {
        owner = boundToValidPayableAddress(owner);
        manager = boundToValidPayableAddress(manager);

        bytes memory hookData = abi.encode(owner, manager, uri);

        // Create campaign first time
        address firstAddress = flywheel.createCampaign(address(mockCampaignHooksWithFees), nonce, hookData);

        // Create campaign second time with same parameters
        address secondAddress = flywheel.createCampaign(address(mockCampaignHooksWithFees), nonce, hookData);

        // Verify same address is returned
        assertEq(firstAddress, secondAddress, "Should return same address for same parameters");

        // Verify campaign still has code
        assertTrue(firstAddress.code.length > 0, "Campaign should still have code");
    }

    /// @dev Verifies initial status is INACTIVE
    /// @param nonce Deterministic salt used by createCampaign
    /// @param owner Campaign owner
    /// @param manager Campaign manager
    /// @param uri Campaign URI
    function test_setsStatusToInactive(uint256 nonce, address owner, address manager, string memory uri) public {
        owner = boundToValidPayableAddress(owner);
        manager = boundToValidPayableAddress(manager);

        bytes memory hookData = abi.encode(owner, manager, uri);

        // Create campaign
        address campaign = flywheel.createCampaign(address(mockCampaignHooksWithFees), nonce, hookData);

        // Verify initial status is INACTIVE
        assertEq(
            uint256(flywheel.campaignStatus(campaign)),
            uint256(Flywheel.CampaignStatus.INACTIVE),
            "Initial status should be INACTIVE"
        );
    }

    /// @dev Verifies hooks are set correctly
    /// @param nonce Deterministic salt used by createCampaign
    /// @param owner Campaign owner
    /// @param manager Campaign manager
    /// @param uri Campaign URI
    function test_setsHooks(uint256 nonce, address owner, address manager, string memory uri) public {
        owner = boundToValidPayableAddress(owner);
        manager = boundToValidPayableAddress(manager);

        bytes memory hookData = abi.encode(owner, manager, uri);

        // Create campaign
        address campaign = flywheel.createCampaign(address(mockCampaignHooksWithFees), nonce, hookData);

        // Verify hooks are set correctly
        address campaignHooks = address(flywheel.campaignHooks(campaign));
        assertEq(campaignHooks, address(mockCampaignHooksWithFees), "Campaign hooks should be set correctly");
    }

    /// @dev Emits CampaignCreated on successful creation
    /// @dev Will expect and match event fields (campaign address and hooks)
    /// @param nonce Deterministic salt used by createCampaign
    /// @param owner Campaign owner
    /// @param manager Campaign manager
    /// @param uri Campaign URI
    function test_emitsCampaignCreated(uint256 nonce, address owner, address manager, string memory uri) public {
        owner = boundToValidPayableAddress(owner);
        manager = boundToValidPayableAddress(manager);

        bytes memory hookData = abi.encode(owner, manager, uri);

        // Predict campaign address for event expectation
        address predictedCampaign = flywheel.predictCampaignAddress(address(mockCampaignHooksWithFees), nonce, hookData);

        // Expect CampaignCreated event
        vm.expectEmit(true, true, false, true);
        emit Flywheel.CampaignCreated(predictedCampaign, address(mockCampaignHooksWithFees));

        // Create campaign
        address actualCampaign = flywheel.createCampaign(address(mockCampaignHooksWithFees), nonce, hookData);

        // Verify addresses match
        assertEq(actualCampaign, predictedCampaign, "Actual campaign should match predicted");
    }
}
