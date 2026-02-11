pragma solidity ^0.8.29;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {BuilderCodes} from "../src/BuilderCodes.sol";
import {PublisherTestSetup, PublisherSetupHelper} from "./helpers/PublisherSetupHelper.sol";

contract BuilderCodesTest is PublisherTestSetup {
    using PublisherSetupHelper for *;

    BuilderCodes public implementation;
    BuilderCodes public pubRegistry;
    ERC1967Proxy public proxy;

    address private owner = address(this);
    address private signer = address(0x123);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy implementation
        implementation = new BuilderCodes();

        // Deploy proxy with signer address
        bytes memory initData = abi.encodeWithSelector(BuilderCodes.initialize.selector, owner, signer, "");
        proxy = new ERC1967Proxy(address(implementation), initData);

        // Create interface to proxy
        pubRegistry = BuilderCodes(address(proxy));

        vm.stopPrank();
    }

    function test_isValidCode_reverts_zeroCode() public {
        assertFalse(pubRegistry.isValidCode(""));
    }

    function test_isValidCode_success_nonZeroCode(uint256 value) public {
        assertTrue(pubRegistry.isValidCode(generateCode(value)));
    }

    //     function test_constructor() public {
    //         assertEq(pubRegistry.owner(), owner);
    //         assertTrue(pubRegistry.hasRole(implementation.REGISTER_ROLE(), signer));
    //     }

    //     function test_initializeWithZeroOwner() public {
    //         // Deploy fresh implementation
    //         BuilderCodes freshImpl = new BuilderCodes();

    //         // Try to initialize with zero owner
    //         bytes memory initData = abi.encodeWithSelector(BuilderCodes.initialize.selector, address(0), address(0));

    //         vm.expectRevert(BuilderCodes.ZeroAddress.selector);
    //         new ERC1967Proxy(address(freshImpl), initData);
    //     }

    //     function test_initializeWithZeroSigner() public {
    //         // Deploy fresh implementation
    //         BuilderCodes freshImpl = new BuilderCodes();

    //         // Initialize with zero signer (should be allowed)
    //         bytes memory initData = abi.encodeWithSelector(BuilderCodes.initialize.selector, owner, address(0));
    //         ERC1967Proxy freshProxy = new ERC1967Proxy(address(freshImpl), initData);
    //         BuilderCodes freshRegistry = BuilderCodes(address(freshProxy));

    //         assertEq(freshRegistry.owner(), owner);
    //         assertFalse(freshRegistry.hasRole(implementation.REGISTER_ROLE(), address(0x123))); // No signers
    //     }

    //     function test_grantSignerRole() public {
    //         address newSigner = address(0x456);

    //         vm.startPrank(owner);

    //         // Expect the event before calling the function
    //         vm.expectEmit(true, true, false, false);
    //         emit IAccessControl.RoleGranted(implementation.REGISTER_ROLE(), newSigner, owner);

    //         pubRegistry.grantRole(implementation.REGISTER_ROLE(), newSigner);

    //         vm.stopPrank();

    //         assertTrue(pubRegistry.hasRole(implementation.REGISTER_ROLE(), newSigner));
    //         assertTrue(pubRegistry.hasRole(implementation.REGISTER_ROLE(), signer)); // original signer still there
    //     }

    //     // todo: something is not working here for some reason
    //     // function test_grantSignerRole_Unauthorized(address account, address newSigner) public {
    //     //     vm.assume(account != pubRegistry.owner());
    //     //     vm.assume(!pubRegistry.hasRole(pubRegistry.getRoleAdmin(pubRegistry.REGISTER_ROLE()), account));
    //     //     vm.assume(newSigner != owner);
    //     //     vm.assume(newSigner != signer);

    //     //     vm.startPrank(account);
    //     //     vm.expectRevert(); //)abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", account, pubRegistry.REGISTER_ROLE()));
    //     //     pubRegistry.grantRole(pubRegistry.REGISTER_ROLE(), newSigner);
    //     //     vm.stopPrank();
    //     // }

    //     function test_revokeSignerRole() public {
    //         vm.startPrank(owner);

    //         // First verify signer has role
    //         assertTrue(pubRegistry.hasRole(implementation.REGISTER_ROLE(), signer));

    //         vm.expectEmit(true, true, false, false);
    //         emit IAccessControl.RoleRevoked(implementation.REGISTER_ROLE(), signer, owner);

    //         pubRegistry.revokeRole(pubRegistry.REGISTER_ROLE(), signer);

    //         vm.stopPrank();

    //         assertFalse(pubRegistry.hasRole(implementation.REGISTER_ROLE(), signer));
    //     }

    //     function test_register_BySigner() public {
    //         bytes32 customRefCode = generateCode(1);
    //         address pubOwner = address(0x789);
    //         address payoutAddr = address(0x101);

    //         // Use helper to create config
    //         PublisherSetupHelper.PublisherConfig memory config =
    //             PublisherSetupHelper.createPublisherConfig(customRefCode, pubOwner, payoutAddr, "https://example.com");

    //         // Expect the event before registration
    //         vm.expectEmit(true, true, true, true);
    //         emit BuilderCodes.BuilderCodeRegistered(
    //             config.refCode, config.owner, config.payoutRecipient, config.metadataUrl, true
    //         );

    //         // Setup publisher using helper
    //         setupPublisher(pubRegistry, config, signer);

    //         // Verify the publisher was registered
    //         assertTrue(pubRegistry.isBuilderCodeRegistered(config.refCode));
    //         assertEq(pubRegistry.getOwner(config.refCode), config.owner);
    //         assertEq(pubRegistry.getMetadataUrl(config.refCode), config.metadataUrl);
    //         assertEq(pubRegistry.getPayoutRecipient(config.refCode), config.payoutRecipient);
    //     }

    //     function test_register_ByOwner() public {
    //         // Use simplified helper - creates config and registers in one call
    //         PublisherSetupHelper.PublisherConfig memory config =
    //             setupPublisher(pubRegistry, generateCode(1), address(0x789), address(0x101), owner);

    //         // Verify the publisher was registered
    //         assertTrue(pubRegistry.isBuilderCodeRegistered(config.refCode));
    //         assertEq(pubRegistry.getOwner(config.refCode), config.owner);
    //         assertEq(pubRegistry.getPayoutRecipient(config.refCode), config.payoutRecipient);
    //         // Default metadata URL is auto-generated
    //         assertEq(pubRegistry.getMetadataUrl(config.refCode), "https://publisher.com/1");
    //     }

    //     function test_register_Unauthorized() public {
    //         bytes32 customRefCode = generateCode(1);
    //         address unauthorized = address(0x999);

    //         vm.startPrank(unauthorized);

    //         vm.expectRevert(
    //             abi.encodeWithSelector(
    //                 IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorized, pubRegistry.REGISTER_ROLE()
    //             )
    //         );
    //         pubRegistry.register(customRefCode, address(0x789), address(0x101), "https://example.com");

    //         vm.stopPrank();
    //     }

    //     function test_register_WithZeroSigner() public {
    //         // Deploy registry with zero signer
    //         BuilderCodes freshImpl = new BuilderCodes();
    //         bytes memory initData = abi.encodeWithSelector(BuilderCodes.initialize.selector, owner, address(0));
    //         ERC1967Proxy freshProxy = new ERC1967Proxy(address(freshImpl), initData);
    //         BuilderCodes freshRegistry = BuilderCodes(address(freshProxy));

    //         bytes32 customRefCode = generateCode(1);

    //         // Only owner should be able to call when signer is zero
    //         vm.startPrank(owner);
    //         freshRegistry.register(customRefCode, address(0x789), address(0x101), "https://example.com");
    //         vm.stopPrank();

    //         // Verify it worked
    //         assertEq(freshRegistry.getOwner(customRefCode), address(0x789));
    //         assertEq(freshRegistry.getPayoutRecipient(customRefCode), address(0x101));
    //         assertEq(freshRegistry.getMetadataUrl(customRefCode), "https://example.com");
    //         assertEq(freshRegistry.isBuilderCodeRegistered(customRefCode), true);

    //         // Unauthorized address should fail
    //         vm.startPrank(address(0x999));
    //         vm.expectRevert(
    //             abi.encodeWithSelector(
    //                 IAccessControl.AccessControlUnauthorizedAccount.selector, address(0x999), freshRegistry.REGISTER_ROLE()
    //             )
    //         );
    //         freshRegistry.register(generateCode(2), address(0x789), address(0x101), "https://example.com");
    //         vm.stopPrank();
    //     }

    //     string private publisherMetadataUrl = "https://example.com";
    //     address private publisherOwner = address(1e6);
    //     address private defaultPayout = address(1e7);
    //     uint256 private optimismChainId = 10;
    //     address private optimismPayout = address(1e8);

    //     function registerDefaultPublisher() internal returns (string memory) {
    //         // Register using the non-custom method (simulates user registration)
    //         vm.startPrank(publisherOwner);
    //         string memory refCode = pubRegistry.register(defaultPayout, publisherMetadataUrl);
    //         vm.stopPrank();
    //         return refCode;
    //     }

    //     function setupDefaultPublisher() internal returns (PublisherSetupHelper.PublisherConfig memory) {
    //         // Alternative using the helper for custom registration
    //         return setupPublisher(
    //             pubRegistry,
    //             generateCode(1),
    //             publisherOwner,
    //             defaultPayout,
    //             owner // owner has REGISTER_ROLE
    //         );
    //     }

    //     function test_registerPublisher() public {
    //         // Then execute the registration
    //         vm.startPrank(publisherOwner);

    //         vm.stopPrank();

    //         // Verify state changes
    //         assertEq(pubRegistry.getOwner(refCode), publisherOwner);
    //         assertEq(pubRegistry.getMetadataUrl(refCode), publisherMetadataUrl);
    //         assertEq(pubRegistry.getPayoutRecipient(refCode), defaultPayout);
    //         assertEq(pubRegistry.isBuilderCodeRegistered(refCode), true);
    //         assertEq(pubRegistry.computeBuilderCode(pubRegistry.nonce()), refCode);
    //     }

    //     function test_updateMetadataUrl() public {
    //         string memory refCode = registerDefaultPublisher();
    //         string memory newDimsUrl = "https://new.com";

    //         vm.startPrank(publisherOwner);

    //         // Expect the event before calling the function
    //         vm.expectEmit(true, true, true, true);
    //         emit BuilderCodes.BuilderCodeMetadataUrlUpdated(refCode, newDimsUrl);

    //         pubRegistry.updateMetadataUrl(refCode, newDimsUrl);

    //         vm.stopPrank();

    //         assertEq(pubRegistry.getMetadataUrl(refCode), newDimsUrl);
    //     }

    //     function test_updatePublisherDefaultPayout() public {
    //         string memory refCode = registerDefaultPublisher();
    //         address newDefaultPayout = address(0x999);

    //         vm.startPrank(publisherOwner);

    //         // Expect the event before calling the function
    //         vm.expectEmit(true, true, true, true);
    //         emit BuilderCodes.BuilderCodePayoutRecipientUpdated(refCode, newDefaultPayout);

    //         pubRegistry.updatePayoutRecipient(refCode, newDefaultPayout);

    //         vm.stopPrank();

    //         assertEq(pubRegistry.getPayoutRecipient(refCode), newDefaultPayout);

    //         // non-publisher cannot update default payout
    //         vm.startPrank(address(0x123));
    //         vm.expectRevert(BuilderCodes.Unauthorized.selector);
    //         pubRegistry.updatePayoutRecipient(refCode, newDefaultPayout);
    //         vm.stopPrank();
    //     }

    //     function test_changePublisherOwner() public {
    //         string memory refCode = registerDefaultPublisher();
    //         address newOwner = address(0x999);
    //         vm.startPrank(publisherOwner);
    //         pubRegistry.updateOwner(refCode, newOwner);

    //         vm.stopPrank();

    //         assertEq(pubRegistry.getOwner(refCode), newOwner);

    //         // non-publisher cannot update owner
    //         vm.startPrank(address(0x123));
    //         vm.expectRevert(BuilderCodes.Unauthorized.selector);
    //         pubRegistry.updateOwner(refCode, newOwner);
    //         vm.stopPrank();
    //     }

    //     function test_computeBuilderCode() public {
    //         registerDefaultPublisher();
    //         string memory refCode1 = pubRegistry.computeBuilderCode(1);
    //         console.log("xxx ref code 1", refCode1);

    //         string memory refCode2 = pubRegistry.computeBuilderCode(2);
    //         console.log("xxx ref code 2", refCode2);

    //         string memory refCode3 = pubRegistry.computeBuilderCode(3);
    //         console.log("xxx ref code 3", refCode3);

    //         string memory refCode4333 = pubRegistry.computeBuilderCode(4333);
    //         console.log("xxx ref code 4333", refCode4333);
    //     }

    //     function test_refCodeCollision() public {
    //         // These nonces are known to generate the first collision
    //         uint256 nonce1 = 2_397_017;
    //         uint256 nonce2 = 3_210_288;

    //         // Verify they actually generate the same ref code
    //         string memory refCode1 = pubRegistry.computeBuilderCode(nonce1);
    //         string memory refCode2 = pubRegistry.computeBuilderCode(nonce2);
    //         assertEq(refCode1, refCode2, "Test setup error: nonces should generate same ref code");
    //         console.log("xxx ref code 1", refCode1);
    //         console.log("xxx ref code 2", refCode2);

    //         // Force the nextPublisherNonce to be just before the first collision
    //         vm.store(
    //             address(pubRegistry),
    //             bytes32(uint256(1)), // slot 1 contains nextPublisherNonce
    //             bytes32(nonce1)
    //         );

    //         // Register first publisher - should get the ref code from nonce1
    //         vm.startPrank(publisherOwner);
    //         string memory firstRefCode = pubRegistry.register(defaultPayout, "first.com");
    //         uint256 firstNonce = pubRegistry.nonce();

    //         // Register second publisher - should skip the collision and generate a new unique code
    //         string memory secondRefCode = pubRegistry.register(defaultPayout, "second.com");
    //         uint256 secondNonce = pubRegistry.nonce();
    //         vm.stopPrank();

    //         console.log("xxx first registered ref code", firstRefCode);
    //         console.log("xxx second registered ref code", secondRefCode);

    //         // Verify we got different ref codes
    //         assertTrue(
    //             keccak256(abi.encode(firstRefCode)) != keccak256(abi.encode(secondRefCode)),
    //             "Should generate different ref codes"
    //         );

    //         assertEq(firstRefCode, pubRegistry.computeBuilderCode(firstNonce), "First ref code mismatch");
    //         assertEq(secondRefCode, pubRegistry.computeBuilderCode(secondNonce), "Second ref code mismatch");

    //         // Verify both publishers were registered with their respective ref codes
    //         assertEq(pubRegistry.getOwner(firstRefCode), publisherOwner, "First publisher not registered correctly");
    //         assertEq(pubRegistry.getOwner(secondRefCode), publisherOwner, "Second publisher not registered correctly");
    //     }

    //     function test_register() public {
    //         // Use helper to create and setup publisher
    //         PublisherSetupHelper.PublisherConfig memory config = PublisherSetupHelper.createPublisherConfig(
    //             "custom123", address(0x123), address(0x456), "https://custom.com"
    //         );

    //         // Expect events before registration
    //         vm.expectEmit(true, true, true, true);
    //         emit BuilderCodes.BuilderCodeRegistered(
    //             config.refCode, config.owner, config.payoutRecipient, config.metadataUrl, true
    //         );

    //         setupPublisher(pubRegistry, config, owner);

    //         // Verify registration
    //         assertTrue(pubRegistry.isBuilderCodeRegistered(config.refCode));
    //         assertEq(pubRegistry.getOwner(config.refCode), config.owner);
    //         assertEq(pubRegistry.getMetadataUrl(config.refCode), config.metadataUrl);
    //         assertEq(pubRegistry.getPayoutRecipient(config.refCode), config.payoutRecipient);
    //     }

    //     function test_batchRegisterPublishers() public {
    //         // Create multiple publishers using helper
    //         PublisherSetupHelper.PublisherConfig[] memory configs = createTestPublishers(3);

    //         // Register all at once
    //         setupPublishers(pubRegistry, configs, owner);

    //         // Verify all were registered
    //         for (uint256 i = 0; i < configs.length; i++) {
    //             assertTrue(pubRegistry.isBuilderCodeRegistered(configs[i].refCode));
    //             assertEq(pubRegistry.getOwner(configs[i].refCode), configs[i].owner);
    //             assertEq(pubRegistry.getPayoutRecipient(configs[i].refCode), configs[i].payoutRecipient);
    //         }
    //     }

    //     function test_register_RefCodeTaken() public {
    //         string memory customRefCode = "custom123";

    //         // Register first publisher
    //         vm.startPrank(owner);
    //         pubRegistry.register(customRefCode, address(0x123), address(0x456), "https://first.com");

    //         // Try to register second publisher with same ref code
    //         vm.expectRevert(BuilderCodes.AlreadyRegistered.selector);
    //         pubRegistry.register(customRefCode, address(0x789), address(0x101), "https://second.com");
    //         vm.stopPrank();
    //     }

    //     function test_updatePublisherOwner_Unauthorized() public {
    //         string memory refCode = registerDefaultPublisher();
    //         address newOwner = address(0x999);

    //         // Try to update owner from unauthorized address
    //         vm.startPrank(address(0x123));
    //         vm.expectRevert(BuilderCodes.Unauthorized.selector);
    //         pubRegistry.updateOwner(refCode, newOwner);
    //         vm.stopPrank();
    //     }

    //     function test_updatePublisherOwner_NewOwnerCanUpdate() public {
    //         string memory refCode = registerDefaultPublisher();
    //         address newOwner = address(0x999);

    //         // Current owner updates to new owner
    //         vm.startPrank(publisherOwner);
    //         pubRegistry.updateOwner(refCode, newOwner);
    //         vm.stopPrank();

    //         // Verify new owner can make updates
    //         vm.startPrank(newOwner);
    //         string memory newMetadataUrl = "https://newowner.com";
    //         pubRegistry.updateMetadataUrl(refCode, newMetadataUrl);
    //         vm.stopPrank();

    //         // Verify old owner cannot make updates
    //         vm.startPrank(publisherOwner);
    //         vm.expectRevert(BuilderCodes.Unauthorized.selector);
    //         pubRegistry.updateMetadataUrl(refCode, "https://oldowner.com");
    //         vm.stopPrank();

    //         // Verify metadata was updated by new owner
    //         assertEq(pubRegistry.getMetadataUrl(refCode), newMetadataUrl);
    //     }

    //     function test_updatePublisherOwner_RevertOnZeroAddress() public {
    //         string memory refCode = registerDefaultPublisher();

    //         // Try to update owner to address(0)
    //         vm.startPrank(publisherOwner);
    //         vm.expectRevert(BuilderCodes.ZeroAddress.selector);
    //         pubRegistry.updateOwner(refCode, address(0));
    //         vm.stopPrank();
    //     }

    //     function test_getPayoutRecipient() public {
    //         string memory refCode = registerDefaultPublisher();

    //         address payoutAddress = pubRegistry.getPayoutRecipient(refCode);
    //         assertEq(payoutAddress, defaultPayout, "Should return default payout address");
    //     }

    //     // Tests for missing coverage lines

    //     /// @notice Test renounceOwnership function should revert
    //     function test_renounceOwnership_shouldRevert() public {
    //         vm.prank(owner);
    //         vm.expectRevert(BuilderCodes.OwnershipRenunciationDisabled.selector);
    //         pubRegistry.renounceOwnership();
    //     }

    //     /// @notice Test return statement in _generateUniqueRefCode with no collision
    //     function test_generateUniqueRefCode_firstTrySuccess() public {
    //         // This tests the return statement on line 250 when no collision occurs
    //         // Register a publisher, which calls _generateUniqueRefCode internally
    //         vm.startPrank(publisherOwner);
    //         string memory refCode = pubRegistry.register(defaultPayout, publisherMetadataUrl);
    //         vm.stopPrank();

    //         // Verify the ref code was generated correctly
    //         assertEq(refCode, pubRegistry.computeBuilderCode(pubRegistry.nonce()), "Ref code should match generated nonce");

    //         // Verify publisher was registered with the generated ref code
    //         assertEq(
    //             pubRegistry.getOwner(refCode), publisherOwner, "Publisher should be registered with generated ref code"
    //         );
    //     }

    //     // Ownable2Step transfer ownership tests

    //     /// @notice Test complete ownership transfer flow
    //     function test_ownable2Step_transferOwnership_complete() public {
    //         address newOwner = address(0x123);

    //         // Step 1: Current owner transfers ownership
    //         vm.prank(owner);
    //         pubRegistry.transferOwnership(newOwner);

    //         // Verify pending owner is set but owner hasn't changed yet
    //         assertEq(pubRegistry.pendingOwner(), newOwner, "Pending owner should be set");
    //         assertEq(pubRegistry.owner(), owner, "Original owner should still be owner");

    //         // Step 2: New owner accepts ownership
    //         vm.prank(newOwner);
    //         pubRegistry.acceptOwnership();

    //         // Verify ownership has been transferred
    //         assertEq(pubRegistry.owner(), newOwner, "New owner should be owner");
    //         assertEq(pubRegistry.pendingOwner(), address(0), "Pending owner should be cleared");
    //     }

    //     /// @notice Test only pending owner can accept ownership
    //     function test_ownable2Step_acceptOwnership_onlyPendingOwner() public {
    //         address newOwner = address(0x123);
    //         address unauthorized = address(0x456);

    //         // Transfer ownership
    //         vm.prank(owner);
    //         pubRegistry.transferOwnership(newOwner);

    //         // Try to accept from unauthorized address
    //         vm.prank(unauthorized);
    //         vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", unauthorized));
    //         pubRegistry.acceptOwnership();

    //         // Verify ownership hasn't changed
    //         assertEq(pubRegistry.owner(), owner, "Owner should not have changed");
    //         assertEq(pubRegistry.pendingOwner(), newOwner, "Pending owner should still be set");
    //     }

    //     /// @notice Test transfer ownership to zero address (renunciation via 2-step)
    //     function test_ownable2Step_transferOwnership_zeroAddress() public {
    //         vm.prank(owner);
    //         // OpenZeppelin 5.x allows transferring to zero address (effectively renouncing ownership)
    //         // This sets pendingOwner to zero address, and acceptOwnership would complete the renunciation
    //         pubRegistry.transferOwnership(address(0));

    //         // Verify pending owner is set to zero address
    //         assertEq(pubRegistry.pendingOwner(), address(0), "Pending owner should be zero address");
    //         assertEq(pubRegistry.owner(), owner, "Original owner should still be owner until accepted");

    //         // Accept ownership (renunciation)
    //         vm.prank(address(0));
    //         pubRegistry.acceptOwnership();

    //         // Verify ownership has been renounced
    //         assertEq(pubRegistry.owner(), address(0), "Owner should be zero address after renunciation");
    //         assertEq(pubRegistry.pendingOwner(), address(0), "Pending owner should be cleared");
    //     }

    //     /// @notice Test overwriting pending owner before acceptance
    //     function test_ownable2Step_transferOwnership_overwrite() public {
    //         address firstNewOwner = address(0x123);
    //         address secondNewOwner = address(0x456);

    //         // Transfer to first new owner
    //         vm.prank(owner);
    //         pubRegistry.transferOwnership(firstNewOwner);

    //         assertEq(pubRegistry.pendingOwner(), firstNewOwner, "First pending owner should be set");

    //         // Transfer to second new owner (overwrites first)
    //         vm.prank(owner);
    //         pubRegistry.transferOwnership(secondNewOwner);

    //         assertEq(pubRegistry.pendingOwner(), secondNewOwner, "Second pending owner should overwrite first");

    //         // First owner cannot accept anymore
    //         vm.prank(firstNewOwner);
    //         vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", firstNewOwner));
    //         pubRegistry.acceptOwnership();

    //         // Second owner can accept
    //         vm.prank(secondNewOwner);
    //         pubRegistry.acceptOwnership();

    //         assertEq(pubRegistry.owner(), secondNewOwner, "Second owner should become owner");
    //     }

    //     /// @notice Test that only current owner can transfer ownership
    //     function test_ownable2Step_transferOwnership_onlyOwner() public {
    //         address unauthorized = address(0x123);
    //         address newOwner = address(0x456);

    //         vm.prank(unauthorized);
    //         vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", unauthorized));
    //         pubRegistry.transferOwnership(newOwner);
    //     }

    //     /// @notice Test new owner can perform owner functions after acceptance
    //     function test_ownable2Step_newOwnerCanPerformOwnerFunctions() public {
    //         address newOwner = address(0x123);

    //         // Transfer and accept ownership
    //         vm.prank(owner);
    //         pubRegistry.transferOwnership(newOwner);

    //         vm.prank(newOwner);
    //         pubRegistry.acceptOwnership();

    //         // New owner should be able to register custom publishers
    //         vm.prank(newOwner);
    //         pubRegistry.register("newowner123", address(0x789), address(0x101), "https://newowner.com");

    //         // Verify custom publisher was registered
    //         assertEq(pubRegistry.getOwner("newowner123"), address(0x789));
    //         assertEq(pubRegistry.getPayoutRecipient("newowner123"), address(0x101));
    //         assertEq(pubRegistry.getMetadataUrl("newowner123"), "https://newowner.com");
    //         assertEq(pubRegistry.isBuilderCodeRegistered("newowner123"), true);
    //     }

    //     /// @notice Test old owner cannot perform owner functions after transfer
    //     function test_ownable2Step_oldOwnerCannotPerformOwnerFunctions() public {
    //         address newOwner = address(0x123);

    //         // Transfer and accept ownership
    //         vm.prank(owner);
    //         pubRegistry.transferOwnership(newOwner);

    //         vm.prank(newOwner);
    //         pubRegistry.acceptOwnership();

    //         // Old owner should not be able to register custom publishers
    //         vm.prank(owner);
    //         vm.expectRevert(
    //             abi.encodeWithSelector(
    //                 IAccessControl.AccessControlUnauthorizedAccount.selector, owner, pubRegistry.REGISTER_ROLE()
    //             )
    //         );
    //         pubRegistry.register("oldowner123", address(0x789), address(0x101), "https://oldowner.com");
    //     }
}
