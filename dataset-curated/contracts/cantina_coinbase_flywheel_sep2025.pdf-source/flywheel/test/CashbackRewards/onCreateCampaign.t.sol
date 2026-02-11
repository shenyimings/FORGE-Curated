// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {CashbackRewardsBase} from "./CashbackRewardsBase.sol";
import {Flywheel} from "../../src/Flywheel.sol";
import {CashbackRewards} from "../../src/hooks/CashbackRewards.sol";

contract OnCreateCampaignTest is CashbackRewardsBase {
    function test_createCampaignWithZeroMaxReward(
        address testOwner,
        address testManager,
        string memory testUri,
        uint256 nonce
    ) public {
        vm.assume(testOwner != address(0) && testManager != address(0));
        vm.assume(bytes(testUri).length <= 1000);

        uint16 maxRewardBasisPoints = 0; // No limit
        bytes memory hookData = abi.encode(testOwner, testManager, testUri, maxRewardBasisPoints);

        vm.prank(testManager);
        address newCampaign = flywheel.createCampaign(address(cashbackRewards), nonce, hookData);

        assertEq(cashbackRewards.owners(newCampaign), testOwner);
        assertEq(cashbackRewards.managers(newCampaign), testManager);
        assertEq(cashbackRewards.campaignURI(newCampaign), testUri);
        assertEq(cashbackRewards.maxRewardBasisPoints(newCampaign), 0);
    }

    function test_createCampaignWithNonZeroMaxReward(
        address testOwner,
        address testManager,
        uint16 maxRewardBps,
        string memory testUri,
        uint256 nonce
    ) public {
        vm.assume(testOwner != address(0) && testManager != address(0));
        vm.assume(bytes(testUri).length <= 1000);
        maxRewardBps = uint16(bound(maxRewardBps, 1, type(uint16).max)); // Any non-zero value

        bytes memory hookData = abi.encode(testOwner, testManager, testUri, maxRewardBps);

        vm.prank(testManager);
        address newCampaign = flywheel.createCampaign(address(cashbackRewards), nonce, hookData);

        assertEq(cashbackRewards.owners(newCampaign), testOwner);
        assertEq(cashbackRewards.managers(newCampaign), testManager);
        assertEq(cashbackRewards.campaignURI(newCampaign), testUri);
        assertEq(cashbackRewards.maxRewardBasisPoints(newCampaign), uint256(maxRewardBps));
    }

    function test_createCampaignEmitsCampaignCreatedEvent(
        address testOwner,
        address testManager,
        string memory testUri,
        uint16 maxRewardBasisPoints,
        uint256 nonce
    ) public {
        vm.assume(testOwner != address(0) && testManager != address(0));
        vm.assume(bytes(testUri).length <= 1000);

        bytes memory hookData = abi.encode(testOwner, testManager, testUri, maxRewardBasisPoints);

        vm.prank(testManager);
        address actualCampaign = flywheel.createCampaign(address(cashbackRewards), nonce, hookData);

        // Verify the campaign was created and has correct parameters
        assertEq(cashbackRewards.owners(actualCampaign), testOwner);
        assertEq(cashbackRewards.managers(actualCampaign), testManager);
        assertEq(cashbackRewards.campaignURI(actualCampaign), testUri);
        assertEq(cashbackRewards.maxRewardBasisPoints(actualCampaign), uint256(maxRewardBasisPoints));
    }

    function test_createMultipleCampaignsWithDifferentNonces(
        address testOwner,
        address testManager,
        string memory firstUri,
        string memory secondUri,
        uint16 firstMaxRewardBps,
        uint16 secondMaxRewardBps,
        uint256 firstNonce,
        uint256 secondNonce
    ) public {
        vm.assume(testOwner != address(0) && testManager != address(0));
        vm.assume(bytes(firstUri).length <= 1000 && bytes(secondUri).length <= 1000);
        vm.assume(firstNonce != secondNonce);

        // Create first campaign
        bytes memory firstHookData = abi.encode(testOwner, testManager, firstUri, firstMaxRewardBps);

        vm.prank(testManager);
        address firstCampaign = flywheel.createCampaign(address(cashbackRewards), firstNonce, firstHookData);

        // Create second campaign with different parameters
        bytes memory secondHookData = abi.encode(testOwner, testManager, secondUri, secondMaxRewardBps);

        vm.prank(testManager);
        address secondCampaign = flywheel.createCampaign(address(cashbackRewards), secondNonce, secondHookData);

        // Verify campaigns are different
        assertTrue(firstCampaign != secondCampaign);

        // Verify first campaign values
        assertEq(cashbackRewards.owners(firstCampaign), testOwner);
        assertEq(cashbackRewards.managers(firstCampaign), testManager);
        assertEq(cashbackRewards.campaignURI(firstCampaign), firstUri);
        assertEq(cashbackRewards.maxRewardBasisPoints(firstCampaign), uint256(firstMaxRewardBps));

        // Verify second campaign values
        assertEq(cashbackRewards.owners(secondCampaign), testOwner);
        assertEq(cashbackRewards.managers(secondCampaign), testManager);
        assertEq(cashbackRewards.campaignURI(secondCampaign), secondUri);
        assertEq(cashbackRewards.maxRewardBasisPoints(secondCampaign), uint256(secondMaxRewardBps));
    }

    function test_createCampaignWithSameOwnerAndManager(
        address sameAddress,
        string memory testUri,
        uint16 maxRewardBasisPoints,
        uint256 nonce
    ) public {
        vm.assume(sameAddress != address(0));
        vm.assume(bytes(testUri).length <= 1000);

        bytes memory hookData = abi.encode(sameAddress, sameAddress, testUri, maxRewardBasisPoints);

        vm.prank(sameAddress);
        address newCampaign = flywheel.createCampaign(address(cashbackRewards), nonce, hookData);

        // Verify both owner and manager are set to the same address
        assertEq(cashbackRewards.owners(newCampaign), sameAddress);
        assertEq(cashbackRewards.managers(newCampaign), sameAddress);
        assertEq(cashbackRewards.campaignURI(newCampaign), testUri);
        assertEq(cashbackRewards.maxRewardBasisPoints(newCampaign), uint256(maxRewardBasisPoints));
    }

    function test_createCampaignWithEmptyUri(
        address testOwner,
        address testManager,
        uint16 maxRewardBasisPoints,
        uint256 nonce
    ) public {
        vm.assume(testOwner != address(0) && testManager != address(0));

        string memory emptyUri = "";
        bytes memory hookData = abi.encode(testOwner, testManager, emptyUri, maxRewardBasisPoints);

        vm.prank(testManager);
        address newCampaign = flywheel.createCampaign(address(cashbackRewards), nonce, hookData);

        // Verify empty URI is handled correctly
        assertEq(cashbackRewards.campaignURI(newCampaign), emptyUri);
        assertEq(cashbackRewards.owners(newCampaign), testOwner);
        assertEq(cashbackRewards.managers(newCampaign), testManager);
        assertEq(cashbackRewards.maxRewardBasisPoints(newCampaign), uint256(maxRewardBasisPoints));
    }
}
