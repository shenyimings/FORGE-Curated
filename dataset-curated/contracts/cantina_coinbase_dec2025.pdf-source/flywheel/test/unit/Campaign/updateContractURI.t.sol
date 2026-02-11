// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Campaign} from "../../../src/Campaign.sol";
import {Flywheel} from "../../../src/Flywheel.sol";
import {FlywheelTest} from "../../lib/FlywheelTestBase.sol";

/// @title UpdateContractURITest
/// @notice Tests for `Campaign.updateContractURI`
contract UpdateContractURITest is FlywheelTest {
    function setUp() public {
        setUpFlywheelBase();
    }
    /// @dev Expects OnlyFlywheel error when msg.sender != flywheel
    /// @dev Reverts when caller is not Flywheel
    /// @param caller Caller address

    function test_updateContractURI_reverts_whenCallerNotFlywheel(address caller) public {
        // Ensure caller is not Flywheel
        vm.assume(caller != address(flywheel));

        // Expect OnlyFlywheel revert
        vm.expectRevert(Campaign.OnlyFlywheel.selector);
        vm.prank(caller);
        Campaign(payable(campaign)).updateContractURI();
    }

    /// @dev Verifies updateContractURI emits ContractURIUpdated
    /// @param nonce Deterministic salt for campaign creation
    /// @param owner Owner address to encode into hook data
    /// @param manager Manager address to encode into hook data
    function test_updateContractURI_emitsContractURIUpdated(uint256 nonce, address owner, address manager) public {
        // Bound inputs
        owner = boundToValidPayableAddress(owner);
        manager = boundToValidPayableAddress(manager);

        // Create campaign
        bytes memory hookData = abi.encode(owner, manager, "Test URI");
        address testCampaign = flywheel.createCampaign(address(mockCampaignHooksWithFees), nonce, hookData);

        // Expect ContractURIUpdated event
        vm.expectEmit(false, false, false, false, testCampaign);
        emit Campaign.ContractURIUpdated();

        // Call updateContractURI from Flywheel
        vm.prank(address(flywheel));
        Campaign(payable(testCampaign)).updateContractURI();
    }
}
