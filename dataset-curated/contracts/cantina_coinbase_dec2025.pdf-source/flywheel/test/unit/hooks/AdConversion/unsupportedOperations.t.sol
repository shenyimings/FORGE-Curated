// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {CampaignHooks} from "../../../../src/CampaignHooks.sol";
import {Flywheel} from "../../../../src/Flywheel.sol";
import {AdConversion} from "../../../../src/hooks/AdConversion.sol";
import {AdConversionTestBase} from "../../../lib/AdConversionTestBase.sol";

contract UnsupportedOperationsTest is AdConversionTestBase {
    // ========================================
    // UNSUPPORTED OPERATIONS REVERT CASES
    // ========================================

    /// @dev Reverts when onAllocate is called (unsupported operation)
    /// @param caller Caller address
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param hookData Hook-specific data
    function test_onAllocate_revert_unsupported(address caller, address campaign, address token, bytes memory hookData)
        public
    {
        vm.assume(caller != address(0));

        // Create campaign for testing
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Should revert when onAllocate is called (unsupported operation)
        vm.expectRevert(CampaignHooks.Unsupported.selector);
        vm.prank(address(flywheel));
        adConversion.onAllocate(caller, testCampaign, address(tokenA), hookData);
    }

    /// @dev Reverts when onDeallocate is called (unsupported operation)
    /// @param caller Caller address
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param hookData Hook-specific data
    function test_onDeallocate_revert_unsupported(
        address caller,
        address campaign,
        address token,
        bytes memory hookData
    ) public {
        vm.assume(caller != address(0));

        // Create campaign for testing
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Should revert when onDeallocate is called (unsupported operation)
        vm.expectRevert(CampaignHooks.Unsupported.selector);
        vm.prank(address(flywheel));
        adConversion.onDeallocate(caller, testCampaign, address(tokenA), hookData);
    }

    /// @dev Reverts when onDistribute is called (unsupported operation)
    /// @param caller Caller address
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param hookData Hook-specific data
    function test_onDistribute_revert_unsupported(
        address caller,
        address campaign,
        address token,
        bytes memory hookData
    ) public {
        vm.assume(caller != address(0));

        // Create campaign for testing
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Should revert when onDistribute is called (unsupported operation)
        vm.expectRevert(CampaignHooks.Unsupported.selector);
        vm.prank(address(flywheel));
        adConversion.onDistribute(caller, testCampaign, address(tokenA), hookData);
    }
}
