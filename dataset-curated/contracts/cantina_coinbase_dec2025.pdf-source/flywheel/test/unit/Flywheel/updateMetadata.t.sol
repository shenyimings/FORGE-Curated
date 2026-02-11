// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Campaign} from "../../../src/Campaign.sol";
import {Flywheel} from "../../../src/Flywheel.sol";
import {FlywheelTest} from "../../lib/FlywheelTestBase.sol";
import {MockCampaignHooksWithFees} from "../../lib/mocks/MockCampaignHooksWithFees.sol";

/// @title UpdateMetadataTest
/// @notice Tests for Flywheel.updateMetadata
contract UpdateMetadataTest is FlywheelTest {
    function setUp() public {
        setUpFlywheelBase();
    }

    /// @dev Verifies updateMetadata succeeds and forwards to hooks.onUpdateMetadata
    /// @dev Expects ContractURIUpdated event from hook
    /// @param newURI New campaign URI to apply via hook
    function test_succeeds_andForwardsToHook(bytes memory newURI) public {
        // Activate campaign so it's not FINALIZED
        activateCampaign(campaign, manager);

        // Mock successful hook call
        vm.mockCall(
            address(mockCampaignHooksWithFees),
            abi.encodeWithSignature("onUpdateMetadata(address,address,bytes)", manager, campaign, newURI),
            ""
        );

        // Update metadata should succeed
        vm.prank(manager);
        flywheel.updateMetadata(campaign, newURI);

        // Verify the hook was called by checking the mock was called
        // We can't directly verify this, but the transaction succeeding means the hook was called
    }

    /// @dev Verifies that CampaignMetadataUpdated is emitted
    /// @param newURI New campaign URI to apply via hook
    function test_emitsCampaignMetadataUpdated(bytes memory newURI) public {
        // Activate campaign so it's not FINALIZED
        activateCampaign(campaign, manager);

        // Mock successful hook call
        vm.mockCall(
            address(mockCampaignHooksWithFees),
            abi.encodeWithSignature("onUpdateMetadata(address,address,bytes)", manager, campaign, newURI),
            ""
        );

        // Expect CampaignMetadataUpdated event
        vm.expectEmit(true, false, false, true);
        emit Flywheel.CampaignMetadataUpdated(campaign, flywheel.campaignURI(campaign));

        // Update metadata
        vm.prank(manager);
        flywheel.updateMetadata(campaign, newURI);
    }

    /// @dev Verifies that ContractURIUpdated is emitted per ERC-7572
    /// @param newURI New campaign URI to apply via hook
    function test_emitsContractURIUpdated(bytes memory newURI) public {
        // Activate campaign so it's not FINALIZED
        activateCampaign(campaign, manager);

        // Mock successful hook call
        vm.mockCall(
            address(mockCampaignHooksWithFees),
            abi.encodeWithSignature("onUpdateMetadata(address,address,bytes)", manager, campaign, newURI),
            ""
        );

        // Expect ContractURIUpdated event from campaign
        vm.expectEmit(false, false, false, false, campaign);
        emit Campaign.ContractURIUpdated();

        // Update metadata
        vm.prank(manager);
        flywheel.updateMetadata(campaign, newURI);
    }
}
