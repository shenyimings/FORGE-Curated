// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Campaign} from "../../../src/Campaign.sol";
import {Flywheel} from "../../../src/Flywheel.sol";
import {FlywheelTest} from "../../lib/FlywheelTestBase.sol";

/// @title ContractURITest
/// @notice Tests for `Campaign.contractURI`
contract ContractURITest is FlywheelTest {
    function setUp() public {
        setUpFlywheelBase();
    }

    /// @dev Expects contractURI returns value from Flywheel.campaignURI
    /// @param nonce Deterministic salt for campaign creation
    /// @param owner Owner address to encode into hook data
    /// @param manager Manager address to encode into hook data
    /// @param uri Campaign URI to encode into hook data
    function test_returnsFlywheelCampaignURI(uint256 nonce, address owner, address manager, string memory uri) public {
        // Bound inputs
        owner = boundToValidPayableAddress(owner);
        manager = boundToValidPayableAddress(manager);

        // Create campaign with the specified URI
        bytes memory hookData = abi.encode(owner, manager, uri);
        address campaign = flywheel.createCampaign(address(mockCampaignHooksWithFees), nonce, hookData);

        // Call contractURI and verify it returns the expected URI
        string memory actualURI = Campaign(payable(campaign)).contractURI();
        assertEq(actualURI, uri, "contractURI should return the URI from flywheel");
    }
}
