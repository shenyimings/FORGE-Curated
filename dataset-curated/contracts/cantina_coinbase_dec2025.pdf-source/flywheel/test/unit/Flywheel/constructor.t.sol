// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Campaign} from "../../../src/Campaign.sol";
import {Flywheel} from "../../../src/Flywheel.sol";
import {Test} from "forge-std/Test.sol";

/// @title ConstructorTest
/// @notice Tests for Flywheel constructor
contract ConstructorTest is Test {
    /// @dev Ensures campaignImplementation is deployed during construction
    function test_deploysCampaignImplementation() public {
        // Deploy a new Flywheel instance
        Flywheel flywheel = new Flywheel();

        // Verify that campaignImplementation is set and is not zero address
        address impl = flywheel.CAMPAIGN_IMPLEMENTATION();
        assertTrue(impl != address(0), "Campaign implementation should not be zero address");

        // Verify that the implementation has code (is actually deployed)
        assertTrue(impl.code.length > 0, "Campaign implementation should have code");

        // Verify that the implementation is actually a Campaign contract
        // We can check this by calling the FLYWHEEL() function
        (bool success, bytes memory data) = impl.staticcall(abi.encodeWithSignature("FLYWHEEL()"));
        assertTrue(success, "Implementation should have FLYWHEEL() function");
        address returnedFlywheel = abi.decode(data, (address));
        assertEq(returnedFlywheel, address(flywheel), "Campaign implementation should reference the flywheel");
    }
}
