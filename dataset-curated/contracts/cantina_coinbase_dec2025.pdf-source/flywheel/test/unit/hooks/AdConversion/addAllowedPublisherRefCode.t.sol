// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {AdConversion} from "../../../../src/hooks/AdConversion.sol";
import {AdConversionTestBase} from "../../../lib/AdConversionTestBase.sol";
import {Vm} from "forge-std/Vm.sol";

contract AddAllowedPublisherRefCodeTest is AdConversionTestBase {
    // ========================================
    // REVERT CASES
    // ========================================

    /// @dev Reverts when caller is not the advertiser
    /// @param unauthorizedCaller Unauthorized caller address (not advertiser)
    function test_revert_unauthorizedCaller(address unauthorizedCaller) public {
        vm.assume(unauthorizedCaller != advertiser1);

        // Create campaign
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = REF_CODE_3; // Pre-populate with existing ref code
        address testCampaign = createCampaignWithAllowlist(advertiser1, attributionProvider1, allowedRefCodes);

        // Should revert when called by unauthorized caller
        vm.prank(unauthorizedCaller);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        adConversion.addAllowedPublisherRefCode(testCampaign, REF_CODE_1);
    }

    /// @dev Reverts when publisher ref code is not registered in BuilderCodes registry
    /// @param refCodeSeed Seed for generating the unregistered ref code
    function test_revert_invalidPublisherRefCode(uint256 refCodeSeed) public {
        vm.assume(refCodeSeed != 0);

        // Generate an unregistered ref code (which is invalid according to AdConversion)
        string memory unregisteredRefCode = generateValidRefCodeFromSeed(refCodeSeed);
        vm.assume(!builderCodes.isRegistered(unregisteredRefCode));

        // Create campaign with allowlist (need at least one ref code to enable allowlist)
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = REF_CODE_3; // Pre-populate with existing ref code
        address testCampaign = createCampaignWithAllowlist(advertiser1, attributionProvider1, allowedRefCodes);

        // Should revert when trying to add unregistered ref code
        vm.prank(advertiser1);
        vm.expectRevert(AdConversion.InvalidPublisherRefCode.selector);
        adConversion.addAllowedPublisherRefCode(testCampaign, unregisteredRefCode);
    }

    /// @dev Reverts when campaign does not have an allowlist (hasAllowlist = false)
    function test_revert_noAllowlist() public {
        // Create campaign WITHOUT allowlist (basic campaign)
        address testCampaign = createBasicCampaign();

        // Should revert when trying to add to campaign without allowlist
        vm.prank(advertiser1);
        vm.expectRevert(AdConversion.Unauthorized.selector);
        adConversion.addAllowedPublisherRefCode(testCampaign, REF_CODE_1);
    }

    /// @dev Reverts when trying to add empty ref code
    function test_revert_emptyRefCode() public {
        // Create campaign with allowlist (need at least one ref code to enable allowlist)
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = REF_CODE_3; // Pre-populate with existing ref code
        address testCampaign = createCampaignWithAllowlist(advertiser1, attributionProvider1, allowedRefCodes);

        // Should revert when trying to add empty ref code (BuilderCodes validation)
        vm.prank(advertiser1);
        vm.expectRevert(abi.encodeWithSignature("InvalidCode(string)", ""));
        adConversion.addAllowedPublisherRefCode(testCampaign, EMPTY_REF_CODE);
    }

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Successfully adds registered publisher ref code to campaign allowlist
    /// @param refCodeSeed Seed for generating the registered ref code
    function test_success_addToAllowlist(uint256 refCodeSeed) public {
        vm.assume(refCodeSeed != 0);

        // Generate a registered ref code
        string memory registeredRefCode = generateValidRefCodeFromSeed(refCodeSeed);
        // Register the ref code
        vm.prank(registrarSigner);
        builderCodes.register(registeredRefCode, publisher1, publisherPayout1);

        // Create campaign with allowlist (need at least one ref code to enable allowlist)
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = REF_CODE_3; // Pre-populate with existing ref code
        address testCampaign = createCampaignWithAllowlist(advertiser1, attributionProvider1, allowedRefCodes);

        // Should succeed when adding registered ref code
        vm.prank(advertiser1);
        adConversion.addAllowedPublisherRefCode(testCampaign, registeredRefCode);

        // Verify the ref code was added to allowlist
        assertTrue(
            adConversion.allowedPublishers(testCampaign, registeredRefCode),
            "new registered ref code should be added to allowlist"
        );
    }

    /// @dev Successfully adds multiple publisher ref codes to campaign allowlist
    function test_success_addMultiple(uint256 refCodeSeed1, uint256 refCodeSeed2) public {
        vm.assume(refCodeSeed1 != 0);
        vm.assume(refCodeSeed2 != 0);

        // Generate two registered ref codes
        string memory registeredRefCode1 = generateValidRefCodeFromSeed(refCodeSeed1);
        string memory registeredRefCode2 = generateValidRefCodeFromSeed(refCodeSeed2);

        // Ensure the generated ref codes are different to avoid registration conflicts
        vm.assume(keccak256(bytes(registeredRefCode1)) != keccak256(bytes(registeredRefCode2)));

        // Register the ref codes
        vm.prank(registrarSigner);
        builderCodes.register(registeredRefCode1, publisher1, publisherPayout1);
        vm.prank(registrarSigner);
        builderCodes.register(registeredRefCode2, publisher1, publisherPayout1);

        // Create campaign with allowlist (need at least one ref code to enable allowlist)
        string[] memory allowedRefCodes = new string[](2);
        allowedRefCodes[0] = REF_CODE_3; // Pre-populate with existing ref code
        address testCampaign = createCampaignWithAllowlist(advertiser1, attributionProvider1, allowedRefCodes);

        // Add multiple ref codes
        vm.startPrank(advertiser1);
        adConversion.addAllowedPublisherRefCode(testCampaign, registeredRefCode1);
        adConversion.addAllowedPublisherRefCode(testCampaign, registeredRefCode2);
        vm.stopPrank();

        // Verify both ref codes were added to allowlist
        assertTrue(
            adConversion.allowedPublishers(testCampaign, registeredRefCode1),
            "new registeredRefCode1 should be added to allowlist"
        );
        assertTrue(
            adConversion.allowedPublishers(testCampaign, registeredRefCode2),
            "new registeredRefCode2 should be added to allowlist"
        );
    }

    /// @dev Successfully handles adding same ref code multiple times (idempotent)
    function test_success_idempotent(uint256 refCodeSeed) public {
        vm.assume(refCodeSeed != 0);

        // Generate a registered ref code
        string memory registeredRefCode = generateValidRefCodeFromSeed(refCodeSeed);
        // Register the ref code
        vm.prank(registrarSigner);
        builderCodes.register(registeredRefCode, publisher1, publisherPayout1);

        // Create campaign with allowlist (need at least one ref code to enable allowlist)
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = REF_CODE_3; // Pre-populate with existing ref code
        address testCampaign = createCampaignWithAllowlist(advertiser1, attributionProvider1, allowedRefCodes);

        // Add same ref code multiple times (should be idempotent)
        vm.startPrank(advertiser1);
        adConversion.addAllowedPublisherRefCode(testCampaign, registeredRefCode);
        adConversion.addAllowedPublisherRefCode(testCampaign, registeredRefCode); // Should be no-op
        adConversion.addAllowedPublisherRefCode(testCampaign, registeredRefCode); // Should be no-op
        vm.stopPrank();

        // Verify ref code is still properly allowed (no errors occurred)
        assertTrue(
            adConversion.allowedPublishers(testCampaign, registeredRefCode),
            "registeredRefCode should remain in allowlist after adding it multiple times"
        );
    }

    // ========================================
    // EDGE CASES
    // ========================================

    /// @dev Handles adding ref code with maximum length (32 characters)
    function test_edge_maxLength() public {
        // Register a max length ref code (32 characters)
        string memory maxLengthRefCode = "12345678901234567890123456789012"; // 32 chars
        vm.prank(registrarSigner);
        builderCodes.register(maxLengthRefCode, publisher1, publisherPayout1);

        // Create campaign with allowlist (need at least one ref code to enable allowlist)
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = REF_CODE_3; // Pre-populate with existing ref code
        address testCampaign = createCampaignWithAllowlist(advertiser1, attributionProvider1, allowedRefCodes);

        // Should succeed when adding max length ref code
        vm.prank(advertiser1);
        adConversion.addAllowedPublisherRefCode(testCampaign, maxLengthRefCode);

        // Verify the ref code was added to allowlist
        assertTrue(
            adConversion.allowedPublishers(testCampaign, maxLengthRefCode),
            "Max length ref code should be added to allowlist after adding it"
        );
    }

    /// @dev Handles adding ref code with single character
    function test_edge_singleCharacter() public {
        // Single character ref codes are not allowed by BuilderCodes (minimum 2 chars)
        // This test verifies the validation behavior
        string memory singleCharRefCode = "A";

        // Create campaign with allowlist (need at least one ref code to enable allowlist)
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = REF_CODE_3; // Pre-populate with existing ref code
        address testCampaign = createCampaignWithAllowlist(advertiser1, attributionProvider1, allowedRefCodes);

        // Should revert when trying to add single character ref code (BuilderCodes validation)
        vm.prank(advertiser1);
        vm.expectRevert(abi.encodeWithSignature("InvalidCode(string)", "A"));
        adConversion.addAllowedPublisherRefCode(testCampaign, singleCharRefCode);
    }

    /// @dev Handles adding ref code with special allowed characters
    function test_edge_specialCharacters() public {
        // Register a ref code with special characters (underscores, numbers)
        string memory specialCharRefCode = "test_code_123";
        vm.prank(registrarSigner);
        builderCodes.register(specialCharRefCode, publisher1, publisherPayout1);

        // Create campaign with allowlist (need at least one ref code to enable allowlist)
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = REF_CODE_3; // Pre-populate with existing ref code
        address testCampaign = createCampaignWithAllowlist(advertiser1, attributionProvider1, allowedRefCodes);

        // Should succeed when adding special character ref code
        vm.prank(advertiser1);
        adConversion.addAllowedPublisherRefCode(testCampaign, specialCharRefCode);

        // Verify the ref code was added to allowlist
        assertTrue(
            adConversion.allowedPublishers(testCampaign, specialCharRefCode),
            "Special character ref code should be added to allowlist after adding it"
        );
    }

    // ========================================
    // EVENT TESTING
    // ========================================

    /// @dev Emits PublisherAddedToAllowlist event with correct parameters
    function test_emitsPublisherAddedToAllowlist(uint256 refCodeSeed) public {
        vm.assume(refCodeSeed != 0);

        // Generate a registered ref code
        string memory registeredRefCode = generateValidRefCodeFromSeed(refCodeSeed);
        // Register the ref code
        vm.prank(registrarSigner);
        builderCodes.register(registeredRefCode, publisher1, publisherPayout1);

        // Create campaign with allowlist (need at least one ref code to enable allowlist)
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = REF_CODE_3; // Pre-populate with existing ref code
        address testCampaign = createCampaignWithAllowlist(advertiser1, attributionProvider1, allowedRefCodes);

        // Expect the PublisherAddedToAllowlist event
        vm.expectEmit(true, false, false, true);
        emit AdConversion.PublisherAddedToAllowlist(testCampaign, registeredRefCode);

        // Add ref code (should emit event)
        vm.prank(advertiser1);
        adConversion.addAllowedPublisherRefCode(testCampaign, registeredRefCode);
    }

    /// @dev Emits multiple events when adding multiple ref codes
    function test_emitsMultipleEvents(uint256 refCodeSeed1, uint256 refCodeSeed2) public {
        vm.assume(refCodeSeed1 != 0);
        vm.assume(refCodeSeed2 != 0);

        // Generate two registered ref codes
        string memory registeredRefCode1 = generateValidRefCodeFromSeed(refCodeSeed1);
        string memory registeredRefCode2 = generateValidRefCodeFromSeed(refCodeSeed2);

        // Ensure the generated ref codes are different to avoid registration conflicts
        vm.assume(keccak256(bytes(registeredRefCode1)) != keccak256(bytes(registeredRefCode2)));

        // Register the ref codes
        vm.prank(registrarSigner);
        builderCodes.register(registeredRefCode1, publisher1, publisherPayout1);
        vm.prank(registrarSigner);
        builderCodes.register(registeredRefCode2, publisher1, publisherPayout1);
        // Create campaign with allowlist (need at least one ref code to enable allowlist)
        string[] memory allowedRefCodes = new string[](2);
        allowedRefCodes[0] = REF_CODE_3; // Pre-populate with existing ref code
        address testCampaign = createCampaignWithAllowlist(advertiser1, attributionProvider1, allowedRefCodes);

        vm.startPrank(advertiser1);

        // Expect first event
        vm.expectEmit(true, false, false, true);
        emit AdConversion.PublisherAddedToAllowlist(testCampaign, registeredRefCode1);
        adConversion.addAllowedPublisherRefCode(testCampaign, registeredRefCode1);

        // Expect second event
        vm.expectEmit(true, false, false, true);
        emit AdConversion.PublisherAddedToAllowlist(testCampaign, registeredRefCode2);
        adConversion.addAllowedPublisherRefCode(testCampaign, registeredRefCode2);

        vm.stopPrank();
    }

    /// @dev Does not emit event when adding already allowed ref code
    function test_noEventForDuplicate(uint256 refCodeSeed) public {
        vm.assume(refCodeSeed != 0);

        // Generate a registered ref code
        string memory registeredRefCode = generateValidRefCodeFromSeed(refCodeSeed);
        // Register the ref code
        vm.prank(registrarSigner);
        builderCodes.register(registeredRefCode, publisher1, publisherPayout1);

        // Create campaign with allowlist (need at least one ref code to enable allowlist)
        string[] memory allowedRefCodes = new string[](1);
        allowedRefCodes[0] = REF_CODE_3; // Pre-populate with existing ref code
        address testCampaign = createCampaignWithAllowlist(advertiser1, attributionProvider1, allowedRefCodes);

        vm.startPrank(advertiser1);
        vm.recordLogs();

        // First addition should emit event
        vm.expectEmit(true, false, false, true);
        emit AdConversion.PublisherAddedToAllowlist(testCampaign, registeredRefCode);
        adConversion.addAllowedPublisherRefCode(testCampaign, registeredRefCode);

        // Second addition should NOT emit event (no-op)
        // Don't expect any events for the duplicate addition
        adConversion.addAllowedPublisherRefCode(testCampaign, registeredRefCode);

        vm.stopPrank();

        // Verify ref code is still properly allowed
        assertTrue(
            adConversion.allowedPublishers(testCampaign, registeredRefCode),
            "registeredRefCode should remain in allowlist after adding it multiple times"
        );

        // Verify only one PublisherAddedToAllowlist event was emitted by the AdConversion hook for this campaign
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 sig = keccak256("PublisherAddedToAllowlist(address,string)");
        bytes32 campaignTopic = bytes32(uint256(uint160(testCampaign)));
        uint256 found;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 1 && entries[i].topics[0] == sig && entries[i].topics[1] == campaignTopic) {
                if (entries[i].emitter == address(adConversion)) {
                    found++;
                }
            }
        }
        assertEq(found, 1, "should emit PublisherAddedToAllowlist exactly once by hook");
    }
}
