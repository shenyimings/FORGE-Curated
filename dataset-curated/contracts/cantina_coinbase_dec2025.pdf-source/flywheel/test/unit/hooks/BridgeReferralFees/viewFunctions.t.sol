// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {LibString} from "solady/utils/LibString.sol";

import {BridgeReferralFees} from "../../../../src/hooks/BridgeReferralFees.sol";
import {BridgeReferralFeesTest} from "../../../lib/BridgeReferralFeesTest.sol";

contract ViewFunctionsTest is BridgeReferralFeesTest {
    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Returns the metadataURI set in constructor for any campaign address
    function test_campaignURI_success_returnsMetadataURI() public {
        // Test with the existing campaign
        string memory uri = bridgeReferralFees.campaignURI(bridgeReferralFeesCampaign);

        // The URI should be uriPrefix + checksummed campaign address
        string memory expectedURI =
            string.concat(CAMPAIGN_URI, LibString.toHexStringChecksummed(bridgeReferralFeesCampaign));
        assertEq(uri, expectedURI, "Campaign URI should match expected format");
    }

    /// @dev Returns consistent URI regardless of campaign address parameter
    function test_campaignURI_success_consistentAcrossCampaigns() public {
        // Create another BridgeReferralFees contract to get a different campaign address
        (address hooks2, address campaign2) = _createBridgeReferralFeesCampaign();

        string memory uri1 = bridgeReferralFees.campaignURI(bridgeReferralFeesCampaign);
        string memory uri2 = bridgeReferralFees.campaignURI(campaign2);

        // URIs should be different (different campaign addresses)
        assertTrue(keccak256(bytes(uri1)) != keccak256(bytes(uri2)), "Different campaigns should have different URIs");

        // But both should follow the same format
        string memory expectedURI1 =
            string.concat(CAMPAIGN_URI, LibString.toHexStringChecksummed(bridgeReferralFeesCampaign));
        string memory expectedURI2 = string.concat(CAMPAIGN_URI, LibString.toHexStringChecksummed(campaign2));

        assertEq(uri1, expectedURI1, "First campaign URI should match expected");
        assertEq(uri2, expectedURI2, "Second campaign URI should match expected");
    }

    // ========================================
    // STATE VERIFICATION
    // ========================================

    /// @dev Verifies campaignURI matches the metadataURI immutable variable
    function test_campaignURI_matchesMetadataURI() public {
        string memory uri = bridgeReferralFees.campaignURI(bridgeReferralFeesCampaign);
        string memory uriPrefix = bridgeReferralFees.uriPrefix();

        // The returned URI should start with the stored uriPrefix
        assertTrue(bytes(uri).length >= bytes(uriPrefix).length, "URI should be at least as long as prefix");

        // Check that URI starts with the prefix
        for (uint256 i = 0; i < bytes(uriPrefix).length; i++) {
            assertEq(bytes(uri)[i], bytes(uriPrefix)[i], "URI should start with uriPrefix");
        }
    }
}
