// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../../../../src/Flywheel.sol";
import {AdConversion} from "../../../../src/hooks/AdConversion.sol";
import {AdConversionTestBase} from "../../../lib/AdConversionTestBase.sol";

contract OnUpdateMetadataTest is AdConversionTestBase {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when caller is not attribution provider or advertiser
    /// @param unauthorizedCaller Unauthorized caller address
    /// @param campaign Campaign address
    /// @param newMetadata New metadata string
    function test_revert_unauthorizedCaller(address unauthorizedCaller, address campaign, string memory newMetadata)
        public
    {
        vm.assume(unauthorizedCaller != advertiser1);
        vm.assume(unauthorizedCaller != attributionProvider1);
        vm.assume(unauthorizedCaller != address(0));

        // Create campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Should revert when called by unauthorized caller
        vm.expectRevert(AdConversion.Unauthorized.selector);
        callHookOnUpdateMetadata(unauthorizedCaller, testCampaign, bytes(newMetadata));
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Successfully allows metadata update when called by attribution provider
    /// @param newMetadata New metadata string
    function test_success_attributionProvider(string memory newMetadata) public {
        // Create campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Store original metadata for comparison
        string memory originalMetadata = adConversion.campaignURI(testCampaign);

        // Should succeed when called by attribution provider (hook only provides authorization)
        callHookOnUpdateMetadata(attributionProvider1, testCampaign, bytes(newMetadata));

        // Verify metadata remains unchanged (hook only authorizes, doesn't update)
        assertEq(
            adConversion.campaignURI(testCampaign), originalMetadata, "Hook should not modify metadata - only authorize"
        );
    }

    /// @dev Successfully allows metadata update when called by advertiser
    /// @param newMetadata New metadata string
    function test_success_advertiser(string memory newMetadata) public {
        // Create campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Store original metadata for comparison
        string memory originalMetadata = adConversion.campaignURI(testCampaign);

        // Should succeed when called by advertiser (hook only provides authorization)
        callHookOnUpdateMetadata(advertiser1, testCampaign, bytes(newMetadata));

        // Verify metadata remains unchanged (hook only authorizes, doesn't update)
        assertEq(
            adConversion.campaignURI(testCampaign), originalMetadata, "Hook should not modify metadata - only authorize"
        );
    }

    /// @dev Successfully updates metadata with empty string
    function test_success_emptyMetadata() public {
        // Create campaign
        address testCampaign = createBasicCampaign();
        fundCampaign(testCampaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);

        // Store original metadata
        string memory originalMetadata = adConversion.campaignURI(testCampaign);

        // Should succeed when updating to empty metadata
        callHookOnUpdateMetadata(advertiser1, testCampaign, "");

        // Verify metadata remains unchanged (hook only authorizes, doesn't update)
        assertEq(
            adConversion.campaignURI(testCampaign), originalMetadata, "Hook should not modify metadata - only authorize"
        );
    }
}
