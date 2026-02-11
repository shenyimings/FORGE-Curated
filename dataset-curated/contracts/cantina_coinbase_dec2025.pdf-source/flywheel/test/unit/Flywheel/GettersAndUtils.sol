// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../../../src/Flywheel.sol";
import {SimpleRewards} from "../../../src/hooks/SimpleRewards.sol";
import {Test} from "forge-std/Test.sol";

/// @title GettersAndUtilsTest
/// @notice Tests for Flywheel getters and utility functions
contract GettersAndUtilsTest is Test {
    /// @dev campaignHooks reverts for non-existent campaign
    /// @dev Expects CampaignDoesNotExist
    /// @param unknownCampaign Random address without a campaign
    function test_campaignHooks_reverts_whenCampaignDoesNotExist(address unknownCampaign) public {}

    /// @dev campaignStatus reverts for non-existent campaign
    /// @dev Expects CampaignDoesNotExist
    /// @param unknownCampaign Random address without a campaign
    function test_campaignStatus_reverts_whenCampaignDoesNotExist(address unknownCampaign) public {}

    /// @dev campaignURI reverts for non-existent campaign
    /// @dev Expects CampaignDoesNotExist
    /// @param unknownCampaign Random address without a campaign
    function test_campaignURI_reverts_whenCampaignDoesNotExist(address unknownCampaign) public {}

    /// @dev campaignExists returns true after createCampaign; false for unknown addresses
    /// @param nonce Deterministic salt used by createCampaign
    /// @param hookData Encoded SimpleRewards hook data (owner, manager, uri)
    function test_campaignExists_returnsCorrectly(uint256 nonce, bytes memory hookData) public {}

    /// @dev campaignHooks returns hook address for existing campaign
    /// @param nonce Deterministic salt used by createCampaign
    /// @param hookData Encoded SimpleRewards hook data (owner, manager, uri)
    function test_campaignHooks_returnsHooksAddress(uint256 nonce, bytes memory hookData) public {}

    /// @dev campaignStatus returns current status; verifies initial INACTIVE and after transitions
    /// @param nonce Deterministic salt used by createCampaign
    /// @param hookData Encoded SimpleRewards hook data (owner, manager, uri)
    function test_campaignStatus_returnsCurrentStatus(uint256 nonce, bytes memory hookData) public {}

    /// @dev campaignURI returns hook-provided URI
    /// @param uri The campaign URI to set via hook data
    function test_campaignURI_returnsHookURI(bytes memory uri) public {}
}
