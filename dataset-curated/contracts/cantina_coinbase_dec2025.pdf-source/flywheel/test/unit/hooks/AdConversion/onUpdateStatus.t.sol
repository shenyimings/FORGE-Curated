// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../../../../src/Flywheel.sol";
import {AdConversion} from "../../../../src/hooks/AdConversion.sol";
import {AdConversionTestBase} from "../../../lib/AdConversionTestBase.sol";

contract OnUpdateStatusTest is AdConversionTestBase {
    // ========================================
    // REVERT CASES - UNAUTHORIZED TRANSITIONS
    // ========================================

    /// @dev Reverts when unauthorized caller attempts any status transition
    /// @param unauthorizedCaller Unauthorized caller address
    /// @param campaign Campaign address
    /// @param fromStatus Current campaign status
    /// @param toStatus Target campaign status
    /// @param metadata Status update metadata
    function test_revert_unauthorizedCaller(
        address unauthorizedCaller,
        address campaign,
        uint8 fromStatus,
        uint8 toStatus,
        string memory metadata
    ) public {
        vm.assume(unauthorizedCaller != advertiser1);
        vm.assume(unauthorizedCaller != attributionProvider1);
        vm.assume(unauthorizedCaller != address(flywheel));
        vm.assume(unauthorizedCaller != address(0));

        // Constrain to valid status values
        fromStatus = uint8(bound(fromStatus, 0, 3));
        toStatus = uint8(bound(toStatus, 0, 3));

        // Create campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Should revert when called by unauthorized caller
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnUpdateStatus(
            unauthorizedCaller,
            testCampaign,
            Flywheel.CampaignStatus(fromStatus),
            Flywheel.CampaignStatus(toStatus),
            bytes(metadata)
        );
    }

    /// @dev Reverts when attribution provider tries unauthorized INACTIVE → FINALIZING transition
    function test_revert_providerInactiveToFinalizing() public {
        // Create campaign in INACTIVE state
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Should revert when attribution provider tries INACTIVE → FINALIZING
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnUpdateStatus(
            attributionProvider1,
            testCampaign,
            Flywheel.CampaignStatus.INACTIVE,
            Flywheel.CampaignStatus.FINALIZING,
            bytes("")
        );
    }

    /// @dev Reverts when attribution provider tries unauthorized INACTIVE → FINALIZED transition
    function test_revert_providerInactiveToFinalized() public {
        // Create campaign in INACTIVE state
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Should revert when attribution provider tries INACTIVE → FINALIZED
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnUpdateStatus(
            attributionProvider1,
            testCampaign,
            Flywheel.CampaignStatus.INACTIVE,
            Flywheel.CampaignStatus.FINALIZED,
            bytes("")
        );
    }

    /// @dev Reverts when attribution provider tries unauthorized ACTIVE → INACTIVE transition
    function test_revert_providerActiveToInactive() public {
        // Create campaign and activate it
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Should revert when attribution provider tries ACTIVE → INACTIVE
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnUpdateStatus(
            attributionProvider1,
            testCampaign,
            Flywheel.CampaignStatus.ACTIVE,
            Flywheel.CampaignStatus.INACTIVE,
            bytes("")
        );
    }

    /// @dev Reverts when advertiser tries unauthorized INACTIVE → ACTIVE transition
    function test_revert_advertiserInactiveToActive() public {
        // Create campaign in INACTIVE state
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Should revert when advertiser tries INACTIVE → ACTIVE
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnUpdateStatus(
            advertiser1, testCampaign, Flywheel.CampaignStatus.INACTIVE, Flywheel.CampaignStatus.ACTIVE, bytes("")
        );
    }

    /// @dev Reverts when advertiser tries unauthorized INACTIVE → FINALIZING transition
    function test_revert_advertiserInactiveToFinalizing() public {
        // Create campaign in INACTIVE state
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Should revert when advertiser tries INACTIVE → FINALIZING
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnUpdateStatus(
            advertiser1, testCampaign, Flywheel.CampaignStatus.INACTIVE, Flywheel.CampaignStatus.FINALIZING, bytes("")
        );
    }

    /// @dev Reverts when advertiser tries unauthorized ACTIVE → INACTIVE transition
    function test_revert_advertiserActiveToInactive() public {
        // Create campaign and activate it
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Should revert when advertiser tries ACTIVE → INACTIVE
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnUpdateStatus(
            advertiser1, testCampaign, Flywheel.CampaignStatus.ACTIVE, Flywheel.CampaignStatus.INACTIVE, bytes("")
        );
    }

    /// @dev Reverts when advertiser tries unauthorized ACTIVE → FINALIZED transition
    function test_revert_advertiserActiveToFinalized() public {
        // Create campaign and activate it
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Should revert when advertiser tries ACTIVE → FINALIZED (must go through FINALIZING)
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnUpdateStatus(
            advertiser1, testCampaign, Flywheel.CampaignStatus.ACTIVE, Flywheel.CampaignStatus.FINALIZED, bytes("")
        );
    }

    /// @dev Reverts when advertiser tries FINALIZING → FINALIZED before attribution deadline
    function test_revert_advertiserFinalizingToFinalizedBeforeDeadline() public {
        // Create campaign with attribution window
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            86400 * 7, // 7 day attribution window
            DEFAULT_FEE_BPS
        );
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Set to FINALIZING status
        vm.prank(advertiser1);
        flywheel.updateStatus(testCampaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Set time to before deadline (3 days after finalizing, but 7 day window)
        vm.warp(block.timestamp + (86400 * 3));

        // Should revert when advertiser tries to finalize before deadline
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnUpdateStatus(
            advertiser1, testCampaign, Flywheel.CampaignStatus.FINALIZING, Flywheel.CampaignStatus.FINALIZED, bytes("")
        );
    }

    // ========================================
    // SUCCESS CASES - ATTRIBUTION PROVIDER TRANSITIONS
    // ========================================

    /// @dev Successfully allows attribution provider INACTIVE → ACTIVE transition
    function test_success_providerInactiveToActive() public {
        // Create campaign in INACTIVE state
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Should succeed when attribution provider activates campaign
        callHookOnUpdateStatus(
            attributionProvider1,
            testCampaign,
            Flywheel.CampaignStatus.INACTIVE,
            Flywheel.CampaignStatus.ACTIVE,
            bytes("")
        );
    }

    /// @dev Successfully allows attribution provider ACTIVE → FINALIZING transition
    function test_success_providerActiveToFinalizing() public {
        // Create campaign and activate it
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Should succeed when attribution provider moves to finalizing
        callHookOnUpdateStatus(
            attributionProvider1,
            testCampaign,
            Flywheel.CampaignStatus.ACTIVE,
            Flywheel.CampaignStatus.FINALIZING,
            bytes("")
        );
    }

    /// @dev Successfully allows attribution provider ACTIVE → FINALIZED transition
    function test_success_providerActiveToFinalized() public {
        // Create campaign and activate it
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Should succeed when attribution provider directly finalizes
        callHookOnUpdateStatus(
            attributionProvider1,
            testCampaign,
            Flywheel.CampaignStatus.ACTIVE,
            Flywheel.CampaignStatus.FINALIZED,
            bytes("")
        );
    }

    /// @dev Successfully allows attribution provider FINALIZING → FINALIZED transition
    function test_success_providerFinalizingToFinalized() public {
        // Create campaign and set to FINALIZING
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Set to FINALIZING status
        vm.prank(advertiser1);
        flywheel.updateStatus(testCampaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Should succeed when attribution provider finalizes (can bypass deadline)
        callHookOnUpdateStatus(
            attributionProvider1,
            testCampaign,
            Flywheel.CampaignStatus.FINALIZING,
            Flywheel.CampaignStatus.FINALIZED,
            bytes("")
        );
    }

    // ========================================
    // SUCCESS CASES - ADVERTISER TRANSITIONS
    // ========================================

    /// @dev Successfully allows advertiser INACTIVE → FINALIZED transition
    function test_success_advertiserInactiveToFinalized() public {
        // Create campaign in INACTIVE state
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Should succeed when advertiser directly finalizes inactive campaign
        callHookOnUpdateStatus(
            advertiser1, testCampaign, Flywheel.CampaignStatus.INACTIVE, Flywheel.CampaignStatus.FINALIZED, bytes("")
        );
    }

    /// @dev Successfully allows advertiser ACTIVE → FINALIZING transition
    function test_success_advertiserActiveToFinalizing() public {
        // Create campaign and activate it
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Should succeed when advertiser moves to finalizing
        callHookOnUpdateStatus(
            advertiser1, testCampaign, Flywheel.CampaignStatus.ACTIVE, Flywheel.CampaignStatus.FINALIZING, bytes("")
        );
    }

    /// @dev Successfully allows advertiser FINALIZING → FINALIZED after attribution deadline
    function test_success_advertiserFinalizingToFinalizedAfterDeadline() public {
        // Create campaign with attribution window
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            86400 * 7, // 7 day attribution window
            DEFAULT_FEE_BPS
        );
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Set to FINALIZING status
        vm.prank(advertiser1);
        flywheel.updateStatus(testCampaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Set time to after deadline (8 days after finalizing, with 7 day window)
        vm.warp(block.timestamp + (86400 * 8));

        // Should succeed when advertiser finalizes after deadline
        callHookOnUpdateStatus(
            advertiser1, testCampaign, Flywheel.CampaignStatus.FINALIZING, Flywheel.CampaignStatus.FINALIZED, bytes("")
        );
    }

    // ========================================
    // ATTRIBUTION DEADLINE TESTING
    // ========================================

    /// @dev Sets attribution deadline when transitioning to FINALIZING with attribution window
    /// @param attributionWindowDays Campaign attribution window in days
    function test_setsAttributionDeadline(uint256 attributionWindowDays) public {
        // Constrain attribution window to valid range (multiples of 1 day, max 180 days)
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        attributionWindowDays = uint256(bound(attributionWindowDays, 1, maxDays));
        uint48 attributionWindow = uint48(attributionWindowDays * 86400);

        // Create campaign with attribution window
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            attributionWindow,
            DEFAULT_FEE_BPS
        );
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Store timestamp before transition
        uint256 beforeTime = block.timestamp;

        // Expect AttributionDeadlineUpdated event
        vm.expectEmit(true, false, false, true);
        emit AdConversion.AttributionDeadlineUpdated(testCampaign, uint48(beforeTime + attributionWindow));

        // Transition to FINALIZING
        callHookOnUpdateStatus(
            advertiser1, testCampaign, Flywheel.CampaignStatus.ACTIVE, Flywheel.CampaignStatus.FINALIZING, bytes("")
        );
    }

    /// @dev Does not set attribution deadline when transitioning to FINALIZING with zero window
    function test_noDeadlineWithZeroWindow() public {
        // Create campaign with zero attribution window
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            0, // Zero attribution window
            DEFAULT_FEE_BPS
        );
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Should NOT emit AttributionDeadlineUpdated event for zero window
        // No expectEmit call means we expect no event

        // Transition to FINALIZING
        callHookOnUpdateStatus(
            advertiser1, testCampaign, Flywheel.CampaignStatus.ACTIVE, Flywheel.CampaignStatus.FINALIZING, bytes("")
        );
    }

    /// @dev Calculates correct attribution deadline timestamp
    function test_calculatesCorrectDeadline() public {
        // Create campaign with attribution window
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        uint48 attributionWindow = 86400 * 7; // 7 day attribution window
        uint256 currentTime = block.timestamp + (86400 * 365); // Within a year

        // Set specific time
        vm.warp(currentTime);

        // Should succeed when advertiser finalizes after deadline
        callHookOnUpdateStatus(
            advertiser1, testCampaign, Flywheel.CampaignStatus.FINALIZING, Flywheel.CampaignStatus.FINALIZED, bytes("")
        );
    }

    // ========================================
    // EDGE CASES
    // ========================================

    /// @dev Handles status transition with empty metadata
    /// @param caller Authorized caller address
    /// @param campaign Campaign address
    /// @param fromStatus Current valid status
    /// @param toStatus Target valid status
    function test_edge_emptyMetadata(address caller, address campaign, uint8 fromStatus, uint8 toStatus) public {
        // Create campaign and set up valid transition
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Test valid INACTIVE → ACTIVE transition with empty metadata
        callHookOnUpdateStatus(
            attributionProvider1,
            testCampaign,
            Flywheel.CampaignStatus.INACTIVE,
            Flywheel.CampaignStatus.ACTIVE,
            "" // Empty metadata
        );
    }

    /// @dev Handles attribution deadline exactly at current timestamp
    /// @param advertiser Advertiser address
    /// @param campaign Campaign address in FINALIZING status
    /// @param metadata Status update metadata
    /// @param exactDeadlineTime Timestamp exactly at attribution deadline
    function test_edge_exactDeadlineTime(
        address advertiser,
        address campaign,
        string memory metadata,
        uint256 exactDeadlineTime
    ) public {
        // Create campaign with attribution window
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            86400 * 7, // 7 day attribution window
            DEFAULT_FEE_BPS
        );
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Set to FINALIZING status
        uint256 finalizingTime = block.timestamp;
        vm.prank(advertiser1);
        flywheel.updateStatus(testCampaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Set time to exactly the deadline
        vm.warp(finalizingTime + (86400 * 7));

        // Should succeed when exactly at deadline
        callHookOnUpdateStatus(
            advertiser1,
            testCampaign,
            Flywheel.CampaignStatus.FINALIZING,
            Flywheel.CampaignStatus.FINALIZED,
            bytes(metadata)
        );
    }

    /// @dev Handles maximum attribution window value
    /// @param caller Authorized caller address
    /// @param campaign Campaign address with maximum attribution window
    /// @param metadata Status update metadata
    function test_edge_maximumAttributionWindow(address caller, address campaign, string memory metadata) public {
        // Create campaign with maximum attribution window
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            MAX_ATTRIBUTION_WINDOW, // 180 days
            DEFAULT_FEE_BPS
        );
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Should succeed with maximum attribution window
        uint256 beforeTime = block.timestamp;

        // Expect event with correct maximum deadline
        vm.expectEmit(true, false, false, true);
        emit AdConversion.AttributionDeadlineUpdated(testCampaign, uint48(beforeTime + MAX_ATTRIBUTION_WINDOW));

        // Transition to FINALIZING
        callHookOnUpdateStatus(
            advertiser1,
            testCampaign,
            Flywheel.CampaignStatus.ACTIVE,
            Flywheel.CampaignStatus.FINALIZING,
            bytes(metadata)
        );
    }

    // ========================================
    // EVENT TESTING
    // ========================================

    /// @dev Emits AttributionDeadlineUpdated event when entering FINALIZING with attribution window
    /// @param caller Authorized caller address
    /// @param campaign Campaign address
    /// @param metadata Status update metadata
    /// @param attributionWindow Campaign attribution window
    function test_emitsAttributionDeadlineUpdated(
        address caller,
        address campaign,
        string memory metadata,
        uint48 attributionWindow
    ) public {
        // Constrain attribution window to valid range (multiples of 1 day, max 180 days)
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        uint48 numDays = uint48(bound(attributionWindow, 1, maxDays));
        attributionWindow = numDays * 86400; // Convert to seconds

        // Create campaign with attribution window
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            attributionWindow,
            DEFAULT_FEE_BPS
        );
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Store timestamp and calculate expected deadline
        uint256 currentTime = block.timestamp;
        uint256 expectedDeadline = currentTime + attributionWindow;

        // Expect AttributionDeadlineUpdated event
        vm.expectEmit(true, false, false, true);
        emit AdConversion.AttributionDeadlineUpdated(testCampaign, uint48(expectedDeadline));

        // Transition to FINALIZING (should emit event)
        callHookOnUpdateStatus(
            advertiser1,
            testCampaign,
            Flywheel.CampaignStatus.ACTIVE,
            Flywheel.CampaignStatus.FINALIZING,
            bytes(metadata)
        );
    }

    /// @dev Does not emit AttributionDeadlineUpdated when attribution window is zero
    /// @param caller Authorized caller address
    /// @param campaign Campaign address with zero attribution window
    /// @param metadata Status update metadata
    function test_noEventWithZeroWindow(address caller, address campaign, string memory metadata) public {
        // Create campaign with zero attribution window
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            0, // Zero attribution window
            DEFAULT_FEE_BPS
        );
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Should NOT emit AttributionDeadlineUpdated event for zero window
        // No expectEmit call means we expect no event

        // Transition to FINALIZING (should not emit event)
        callHookOnUpdateStatus(
            advertiser1,
            testCampaign,
            Flywheel.CampaignStatus.ACTIVE,
            Flywheel.CampaignStatus.FINALIZING,
            bytes(metadata)
        );
    }

    // ========================================
    // COMPLEX TRANSITION SCENARIOS
    // ========================================

    /// @dev Tests complete campaign lifecycle transitions
    /// @param attributionWindowDays Campaign attribution window in days
    function test_completeCampaignLifecycle(uint256 attributionWindowDays) public {
        // Constrain attribution window to valid range (multiples of 1 day, max 180 days)
        uint48 maxDays = MAX_ATTRIBUTION_WINDOW / 86400; // 180 days
        attributionWindowDays = uint256(bound(attributionWindowDays, 1, maxDays));
        uint48 attributionWindow = uint48(attributionWindowDays * 86400);

        // Create campaign with attribution window
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            attributionWindow,
            DEFAULT_FEE_BPS
        );
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Step 1: INACTIVE → ACTIVE (attribution provider)
        callHookOnUpdateStatus(
            attributionProvider1,
            testCampaign,
            Flywheel.CampaignStatus.INACTIVE,
            Flywheel.CampaignStatus.ACTIVE,
            bytes("Activating campaign")
        );

        // Step 2: ACTIVE → FINALIZING (advertiser)
        callHookOnUpdateStatus(
            advertiser1,
            testCampaign,
            Flywheel.CampaignStatus.ACTIVE,
            Flywheel.CampaignStatus.FINALIZING,
            bytes("Moving to finalizing")
        );

        // Step 3: Wait for attribution deadline to pass
        vm.warp(block.timestamp + attributionWindow + 1);

        // Step 4: FINALIZING → FINALIZED (advertiser, after deadline)
        callHookOnUpdateStatus(
            advertiser1,
            testCampaign,
            Flywheel.CampaignStatus.FINALIZING,
            Flywheel.CampaignStatus.FINALIZED,
            bytes("Finalizing campaign")
        );
    }

    /// @dev Tests attribution provider can bypass advertiser deadline wait
    /// @param attributionProvider Attribution provider address
    /// @param advertiser Advertiser address
    /// @param campaign Campaign address in FINALIZING status
    /// @param metadata Status update metadata
    /// @param currentTime Time before attribution deadline
    function test_providerBypassesDeadline(
        address attributionProvider,
        address advertiser,
        address campaign,
        string memory metadata,
        uint256 currentTime
    ) public {
        // Create campaign with attribution window
        address testCampaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            86400 * 7, // 7 day attribution window
            DEFAULT_FEE_BPS
        );
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
        activateCampaign(testCampaign, attributionProvider1);

        // Set to FINALIZING status
        vm.prank(advertiser1);
        flywheel.updateStatus(testCampaign, Flywheel.CampaignStatus.FINALIZING, "");

        // Set time to before deadline (3 days after finalizing, but 7 day window)
        vm.warp(block.timestamp + (86400 * 3));

        // Attribution provider should be able to finalize even before deadline
        callHookOnUpdateStatus(
            attributionProvider1,
            testCampaign,
            Flywheel.CampaignStatus.FINALIZING,
            Flywheel.CampaignStatus.FINALIZED,
            bytes(metadata)
        );
    }

    // ========================================
    // TRANSITION AUTHORIZATION MATRIX TESTING
    // ========================================

    /// @dev Tests attribution provider authorization for valid transitions (authorization only)
    function test_providerValidTransitions() public {
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Test authorization for INACTIVE → ACTIVE (should succeed)
        vm.prank(address(flywheel));
        adConversion.onUpdateStatus(
            attributionProvider1,
            testCampaign,
            Flywheel.CampaignStatus.INACTIVE,
            Flywheel.CampaignStatus.ACTIVE,
            "provider activates"
        );

        // Test authorization for ACTIVE → FINALIZING (should succeed)
        vm.prank(address(flywheel));
        adConversion.onUpdateStatus(
            attributionProvider1,
            testCampaign,
            Flywheel.CampaignStatus.ACTIVE,
            Flywheel.CampaignStatus.FINALIZING,
            "provider finalizing"
        );

        // Test authorization for ACTIVE → FINALIZED (should succeed)
        vm.prank(address(flywheel));
        adConversion.onUpdateStatus(
            attributionProvider1,
            testCampaign,
            Flywheel.CampaignStatus.ACTIVE,
            Flywheel.CampaignStatus.FINALIZED,
            "provider direct finalize"
        );
    }

    /// @dev Tests advertiser authorization for valid transitions (authorization only)
    function test_advertiserValidTransitions() public {
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Test authorization for INACTIVE → FINALIZED (should succeed)
        vm.prank(address(flywheel));
        adConversion.onUpdateStatus(
            advertiser1,
            testCampaign,
            Flywheel.CampaignStatus.INACTIVE,
            Flywheel.CampaignStatus.FINALIZED,
            "advertiser direct finalize"
        );

        // Test authorization for ACTIVE → FINALIZING (should succeed)
        vm.prank(address(flywheel));
        adConversion.onUpdateStatus(
            advertiser1,
            testCampaign,
            Flywheel.CampaignStatus.ACTIVE,
            Flywheel.CampaignStatus.FINALIZING,
            "advertiser finalizing"
        );

        // Note: FINALIZING → FINALIZED for advertiser requires attribution deadline to pass
        // This is tested separately in other test functions
    }
}
