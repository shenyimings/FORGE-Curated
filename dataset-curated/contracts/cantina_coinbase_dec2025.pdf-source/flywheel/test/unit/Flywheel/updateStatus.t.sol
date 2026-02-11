// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../../../src/Flywheel.sol";
import {FlywheelTest} from "../../lib/FlywheelTestBase.sol";
import {MockCampaignHooksWithFees} from "../../lib/mocks/MockCampaignHooksWithFees.sol";

/// @title UpdateStatusTest
/// @notice Tests for Flywheel.updateStatus
contract UpdateStatusTest is FlywheelTest {
    function setUp() public {
        setUpFlywheelBase();
    }

    /// @dev Expects CampaignDoesNotExist
    /// @dev Reverts when campaign does not exist
    /// @param nonExistentCampaign Non-existent campaign address
    function test_reverts_ifNonexistentCampaign(address nonExistentCampaign) public {
        vm.assume(nonExistentCampaign != campaign); // Ensure it's not the existing campaign

        vm.expectRevert(Flywheel.CampaignDoesNotExist.selector);
        flywheel.updateStatus(nonExistentCampaign, Flywheel.CampaignStatus.ACTIVE, "");
    }

    /// @dev Expects InvalidCampaignStatus when setting same status
    /// @param hookData Arbitrary hook data forwarded to hooks.onUpdateStatus
    function test_reverts_whenNoStatusChange(bytes memory hookData) public {
        // Campaign starts as INACTIVE, so trying to set it to INACTIVE should fail
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.INACTIVE));

        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.INACTIVE, hookData);
    }

    /// @dev Expects InvalidCampaignStatus when updating from FINALIZED
    /// @param hookData Arbitrary hook data forwarded to hooks.onUpdateStatus
    function test_reverts_whenFromFinalized(bytes memory hookData) public {
        // Move campaign to FINALIZED state
        activateCampaign(campaign, manager);
        finalizeCampaign(campaign, manager);
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZED));

        // Try to update from FINALIZED to any other status - should fail
        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, hookData);
    }

    /// @dev Expects InvalidCampaignStatus when FINALIZING -> not FINALIZED
    /// @param newStatus New status of the campaign as Flywheel.CampaignStatus
    function test_reverts_whenFinalizingToNotFinalized(uint256 newStatus) public {
        // Bound newStatus to valid enum range but exclude FINALIZED (3)
        newStatus = bound(newStatus, 0, 2); // INACTIVE (0), ACTIVE (1), FINALIZING (2)
        Flywheel.CampaignStatus status = Flywheel.CampaignStatus(newStatus);

        // Move campaign to FINALIZING state
        activateCampaign(campaign, manager);
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        // Try to update from FINALIZING to any status other than FINALIZED - should fail
        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(manager);
        flywheel.updateStatus(campaign, status, "");
    }

    /// @notice Transitions INACTIVE -> Any other status
    /// @dev Verifies CampaignStatusUpdated event and status change
    /// @param newStatus New status of the campaign as Flywheel.CampaignStatus
    function test_succeeds_inactiveToAnyOtherStatus(uint256 newStatus) public {
        // Bound newStatus to valid enum range and exclude INACTIVE (0)
        newStatus = bound(newStatus, 1, 3); // ACTIVE (1), FINALIZING (2), FINALIZED (3)
        Flywheel.CampaignStatus status = Flywheel.CampaignStatus(newStatus);

        // Verify campaign starts as INACTIVE
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.INACTIVE));

        // Expect CampaignStatusUpdated event
        vm.expectEmit(true, true, true, true);
        emit Flywheel.CampaignStatusUpdated(campaign, manager, Flywheel.CampaignStatus.INACTIVE, status);

        // Update status from INACTIVE to new status
        vm.prank(manager);
        flywheel.updateStatus(campaign, status, "");

        // Verify status was updated
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(status));
    }

    /// @notice Transitions ACTIVE -> Any other status
    /// @dev Verifies CampaignStatusUpdated event and status change
    /// @param newStatus New status of the campaign as Flywheel.CampaignStatus
    function test_succeeds_activeToAnyOtherStatus(uint256 newStatus) public {
        // Bound newStatus to valid enum range and exclude ACTIVE (1)
        vm.assume(newStatus != 1); // Exclude ACTIVE
        newStatus = bound(newStatus, 0, 3); // INACTIVE (0), FINALIZING (2), FINALIZED (3)
        if (newStatus >= 1) newStatus++; // Skip ACTIVE
        if (newStatus > 3) newStatus = 3; // Cap at FINALIZED
        Flywheel.CampaignStatus status = Flywheel.CampaignStatus(newStatus);

        // Move campaign to ACTIVE first
        activateCampaign(campaign, manager);
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));

        // Expect CampaignStatusUpdated event
        vm.expectEmit(true, true, true, true);
        emit Flywheel.CampaignStatusUpdated(campaign, manager, Flywheel.CampaignStatus.ACTIVE, status);

        // Update status from ACTIVE to new status
        vm.prank(manager);
        flywheel.updateStatus(campaign, status, "");

        // Verify status was updated
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(status));
    }

    /// @notice Transitions FINALIZING -> FINALIZED
    /// @dev Verifies CampaignStatusUpdated event and status change
    function test_succeeds_finalizingToFinalized() public {
        // Move campaign to FINALIZING state
        activateCampaign(campaign, manager);
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZING));

        // Expect CampaignStatusUpdated event
        vm.expectEmit(true, true, true, true);
        emit Flywheel.CampaignStatusUpdated(
            campaign, manager, Flywheel.CampaignStatus.FINALIZING, Flywheel.CampaignStatus.FINALIZED
        );

        // Update status from FINALIZING to FINALIZED
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");

        // Verify status was updated
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.FINALIZED));
    }
}
