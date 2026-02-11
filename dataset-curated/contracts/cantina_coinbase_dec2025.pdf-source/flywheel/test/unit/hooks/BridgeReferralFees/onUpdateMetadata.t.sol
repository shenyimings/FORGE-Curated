// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {LibString} from "solady/utils/LibString.sol";

import {BridgeReferralFees, BridgeReferralFeesTest} from "../../../lib/BridgeReferralFeesTest.sol";

contract OnUpdateMetadataTest is BridgeReferralFeesTest {
    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Accepts metadata update from any sender (no access restrictions)
    /// @param randomCaller Random caller address
    function test_revert_unauthorized(address randomCaller) public {
        vm.assume(randomCaller != address(0));
        vm.assume(randomCaller != bridgeReferralFees.METADATA_MANAGER());

        vm.prank(randomCaller);
        vm.expectRevert(BridgeReferralFees.Unauthorized.selector);
        flywheel.updateMetadata(bridgeReferralFeesCampaign, "some metadata");
    }

    function test_success_updatesUriPrefix(string memory newUriPrefix) public {
        vm.assume(bytes(newUriPrefix).length > 0);
        vm.prank(bridgeReferralFees.METADATA_MANAGER());
        flywheel.updateMetadata(bridgeReferralFeesCampaign, bytes(newUriPrefix));
        assertEq(bridgeReferralFees.uriPrefix(), newUriPrefix, "Uri prefix should be updated");
        assertEq(
            flywheel.campaignURI(bridgeReferralFeesCampaign),
            string.concat(newUriPrefix, LibString.toHexStringChecksummed(bridgeReferralFeesCampaign)),
            "Campaign URI should be updated"
        );
    }

    function test_success_noUriPrefixChange() public {
        string memory oldUriPrefix = bridgeReferralFees.uriPrefix();
        vm.prank(bridgeReferralFees.METADATA_MANAGER());
        flywheel.updateMetadata(bridgeReferralFeesCampaign, "");
        assertEq(bridgeReferralFees.uriPrefix(), oldUriPrefix, "Uri prefix should not change");
        assertEq(
            flywheel.campaignURI(bridgeReferralFeesCampaign),
            string.concat(oldUriPrefix, LibString.toHexStringChecksummed(bridgeReferralFeesCampaign)),
            "Campaign URI should not change"
        );
    }
}
