// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import { BaseTest } from "test/utils/BaseTest.t.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { Errors } from "src/libraries/Errors.sol";

contract AssetRegistry_Test is BaseTest {
    AssetRegistry public assetRegistry;
    bytes32 public adminRole;
    bytes32 public managerRole;

    uint256 public constant MAX_ASSETS = 255;

    function setUp() public override {
        super.setUp();
        createUser("admin");
        createUser("alice");
        assetRegistry = new AssetRegistry(users["admin"]);
        adminRole = assetRegistry.DEFAULT_ADMIN_ROLE();
        managerRole = keccak256("MANAGER_ROLE");
    }

    function test_constructor() public {
        assert(assetRegistry.hasRole(adminRole, users["admin"]));
        assert(assetRegistry.hasRole(managerRole, users["admin"]));
    }

    function test_constructor_revertWhen_zeroAddressAdmin() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        assetRegistry = new AssetRegistry(address(0));
    }

    // Try granting manager role from an account without admin role
    function testFuzz_grantRole_revertWhen_CalledByNonAdmin(address nonAdmin, address recipient) public {
        vm.assume(nonAdmin != users["admin"] && nonAdmin != address(0));
        vm.assume(recipient != address(0) && recipient != users["admin"]);

        vm.expectRevert(_formatAccessControlError(nonAdmin, adminRole));
        vm.prank(nonAdmin);
        assetRegistry.grantRole(managerRole, recipient);

        assertFalse(assetRegistry.hasRole(managerRole, recipient));
    }

    // Try granting manager role from an account with admin role
    function testFuzz_grantRole_managerRole(address recipient) public {
        vm.assume(recipient != address(0));
        vm.assume(!assetRegistry.hasRole(managerRole, recipient));

        // Grant the manager role to the recipient from the admin
        vm.prank(users["admin"]);
        assetRegistry.grantRole(managerRole, recipient);

        // Check the recipient now has the manager role
        assertTrue(assetRegistry.hasRole(managerRole, recipient));
    }

    function testFuzz_grantRole_adminRole(address newAdmin, address newManager) public {
        vm.assume(newAdmin != address(0) && newAdmin != users["admin"]);
        vm.assume(newManager != address(0) && newManager != newAdmin);

        // Check the new admin does not have the admin role
        assertFalse(assetRegistry.hasRole(adminRole, newAdmin));

        // Grant the admin role to the new admin from the owner
        vm.prank(users["admin"]);
        assetRegistry.grantRole(adminRole, newAdmin);

        // Check the new admin now has the admin role
        assertTrue(assetRegistry.hasRole(adminRole, newAdmin));

        // Verify the new admin can grant the manager role
        vm.prank(newAdmin);
        assetRegistry.grantRole(managerRole, newManager);

        // Check that the new manager has the manager role
        assertTrue(assetRegistry.hasRole(managerRole, newManager));
    }

    function testFuzz_revokeRole_managerRole_revertWhen_RevokeRoleWithoutAdmin(
        address nonAdmin,
        address targetUser
    )
        public
    {
        vm.assume(nonAdmin != users["admin"] && nonAdmin != address(0));
        vm.assume(targetUser != address(0));

        vm.prank(nonAdmin);
        vm.expectRevert(_formatAccessControlError(nonAdmin, adminRole));
        assetRegistry.revokeRole(managerRole, targetUser);

        // Verify that the role was not revoked
        assertTrue(assetRegistry.hasRole(managerRole, users["admin"]));
    }

    function testFuzz_revokeRole_adminRole(address user) public {
        vm.assume(user != address(0) && user != users["admin"]);

        // Check the user does not have the admin role initially
        assertFalse(assetRegistry.hasRole(adminRole, user));

        // Grant the admin role to the user from the owner
        vm.prank(users["admin"]);
        assetRegistry.grantRole(adminRole, user);

        // Check the user now has the admin role
        assertTrue(assetRegistry.hasRole(adminRole, user));

        // Revoke the admin role from the user from the owner
        vm.prank(users["admin"]);
        assetRegistry.revokeRole(adminRole, user);

        // Check the user no longer has the admin role
        assertFalse(assetRegistry.hasRole(adminRole, user));
    }

    function testFuzz_revokeRoleF_adminRole(address user) public {
        vm.assume(user != address(0) && user != users["admin"]);

        // Check the user does not have the admin role initially
        assertFalse(assetRegistry.hasRole(adminRole, user));

        // Grant the admin role to the user from the owner
        vm.prank(users["admin"]);
        assetRegistry.grantRole(adminRole, user);

        // Check the user now has the admin role
        assertTrue(assetRegistry.hasRole(adminRole, user));

        // Revoke the admin role from the user
        vm.prank(user);
        assetRegistry.revokeRole(adminRole, user);

        // Check the user no longer has the admin role
        assertFalse(assetRegistry.hasRole(adminRole, user));
    }

    function test_renounceRole_managerRole() public {
        // Check the admin has the manager role
        assert(assetRegistry.hasRole(managerRole, users["admin"]));

        // Renounce the manager role from the admin
        vm.prank(users["admin"]);
        assetRegistry.renounceRole(managerRole, users["admin"]);

        // Check the user no longer has the manager role
        assert(!assetRegistry.hasRole(managerRole, users["admin"]));
    }

    function test_renounceRole_adminRole() public {
        // Check the user has the admin role
        assert(assetRegistry.hasRole(adminRole, users["admin"]));

        // Renounce the admin role from the admin
        vm.prank(users["admin"]);
        assetRegistry.renounceRole(adminRole, users["admin"]);

        // Check the user no longer has the admin role
        assert(!assetRegistry.hasRole(adminRole, users["admin"]));
    }

    function test_addAsset_revertWhen_zeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(users["admin"]);
        assetRegistry.addAsset(address(0));
    }

    function test_addAsset_revertWhen_maxAssetsReached() public {
        for (uint256 i = 0; i < MAX_ASSETS; i++) {
            testFuzz_addAsset(address(uint160(i + 1)));
        }

        vm.expectRevert(AssetRegistry.MaxAssetsReached.selector);
        vm.prank(users["admin"]);
        assetRegistry.addAsset(address(uint160(MAX_ASSETS + 1)));
    }

    function testFuzz_addAsset_revertWhen_alreadyEnabled(address asset) public {
        vm.assume(asset != address(0));
        testFuzz_addAsset(asset);

        vm.expectRevert(AssetRegistry.AssetAlreadyEnabled.selector);
        vm.prank(users["admin"]);
        assetRegistry.addAsset(asset);
    }

    function testFuzz_addAsset(address asset) public {
        vm.assume(asset != address(0));

        vm.expectEmit();
        emit AssetRegistry.AddAsset(asset);
        vm.prank(users["admin"]);
        assetRegistry.addAsset(asset);

        _assertAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);
    }

    function testFuzz_setAssetStatus_revertWhen_zeroAddress(uint8 status) public {
        vm.assume(status <= uint8(type(AssetRegistry.AssetStatus).max));
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(users["admin"]);
        assetRegistry.setAssetStatus(address(0), AssetRegistry.AssetStatus(status));
    }

    function testFuzz_setAssetStatus_revertWhen_notEnabled(address asset) public {
        vm.assume(asset != address(0));

        vm.expectRevert(AssetRegistry.AssetNotEnabled.selector);
        vm.prank(users["admin"]);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);
    }

    function testFuzz_setAssetStatus_pause(address asset) public {
        vm.assume(asset != address(0));

        testFuzz_addAsset(asset);

        vm.expectEmit();
        emit AssetRegistry.SetAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);
        vm.prank(users["admin"]);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);

        _assertAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);
    }

    function testFuzz_setAssetStatus_unpause(address asset) public {
        vm.assume(asset != address(0));
        vm.startPrank(users["admin"]);

        assetRegistry.addAsset(asset);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);

        vm.expectEmit();
        emit AssetRegistry.SetAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);

        _assertAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);
    }

    function testFuzz_setAssetStatus_revertWhen_noStatusChange(address asset) public {
        vm.assume(asset != address(0));
        vm.startPrank(users["admin"]);

        assetRegistry.addAsset(asset);

        // Attempt to set status to ENABLED when it's already ENABLED
        vm.expectRevert(AssetRegistry.AssetInvalidStatusUpdate.selector);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);

        _assertAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);

        // Pause the asset
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);

        // Attempt to set status to PAUSED when it's already PAUSED
        vm.expectRevert(AssetRegistry.AssetInvalidStatusUpdate.selector);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);

        _assertAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);
    }

    function testFuzz_setAssetStatus_revertWhen_settingToDisabled(address asset) public {
        vm.assume(asset != address(0));
        testFuzz_addAsset(asset);

        vm.expectRevert(AssetRegistry.AssetInvalidStatusUpdate.selector);
        vm.prank(users["admin"]);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.DISABLED);

        _assertAssetStatus(asset, AssetRegistry.AssetStatus.ENABLED);
    }

    function testFuzz_getAssetStatus(address asset) public {
        vm.assume(asset != address(0));

        // Test for non-existent asset
        assertEq(uint256(assetRegistry.getAssetStatus(asset)), uint256(AssetRegistry.AssetStatus.DISABLED));

        // Add asset and check status
        vm.prank(users["admin"]);
        assetRegistry.addAsset(asset);
        assertEq(uint256(assetRegistry.getAssetStatus(asset)), uint256(AssetRegistry.AssetStatus.ENABLED));

        // Pause asset and check status
        vm.prank(users["admin"]);
        assetRegistry.setAssetStatus(asset, AssetRegistry.AssetStatus.PAUSED);
        assertEq(uint256(assetRegistry.getAssetStatus(asset)), uint256(AssetRegistry.AssetStatus.PAUSED));
    }

    function _assertAssetStatus(address asset, AssetRegistry.AssetStatus expectedStatus) internal view {
        assertEq(uint256(assetRegistry.getAssetStatus(asset)), uint256(expectedStatus));
    }

    function _setupAssets(uint256 assetCount) internal returns (address[] memory) {
        address[] memory testAssets = new address[](assetCount);
        for (uint256 i = 0; i < assetCount; i++) {
            testAssets[i] = address(uint160(i + 1));
            vm.prank(users["admin"]);
            assetRegistry.addAsset(testAssets[i]);
        }
        return testAssets;
    }

    function testFuzz_getAllAssets(uint256 assetCount) public {
        vm.assume(assetCount <= MAX_ASSETS);
        address[] memory testAssets = _setupAssets(assetCount);

        // Get all assets
        address[] memory returnedAssets = assetRegistry.getAllAssets();

        // Verify all assets are returned
        assertEq(returnedAssets, testAssets);
    }

    function testFuzz_getAssets(uint256 assetCount, uint256 bitFlag) public {
        vm.assume(assetCount <= MAX_ASSETS);
        vm.assume(bitFlag > 0 && bitFlag < (1 << assetCount));
        address[] memory testAssets = _setupAssets(assetCount);

        // Get assets based on the fuzzed bitFlag
        address[] memory returnedAssets = assetRegistry.getAssets(bitFlag);

        // Verify the returned assets
        uint256 expectedCount = 0;
        for (uint256 i = 0; i < assetCount; i++) {
            if ((bitFlag & (1 << i)) != 0) {
                expectedCount++;
                assertEq(returnedAssets[expectedCount - 1], testAssets[i]);
            }
        }

        // Verify the length of the returned array
        assertEq(returnedAssets.length, expectedCount);
    }

    function testFuzz_getAssets_passesWhen_EmptyBitFlag(uint256 assetCount) public {
        vm.assume(assetCount <= MAX_ASSETS);
        _setupAssets(assetCount);

        // Get assets with empty bitFlag
        address[] memory assets = assetRegistry.getAssets(0);
        assertEq(assets.length, 0, "Returned assets should be empty");
    }

    function testFuzz_getAssets_revertsWhen_AssetExceedsMaximum(uint256 numAssets, uint256 bitFlag) public {
        vm.assume(numAssets > 0 && numAssets <= MAX_ASSETS);
        vm.assume(bitFlag > 0 && bitFlag >= (1 << numAssets));
        _setupAssets(numAssets);

        // Get all assets
        vm.expectRevert(AssetRegistry.AssetExceedsMaximum.selector);
        assetRegistry.getAssets(bitFlag);
    }

    function testFuzz_getAssets_revertWhen_AssetExceedsMaximum_nonExistentAssets(uint256 bitFlag) public {
        vm.assume(bitFlag != 0);

        // Get assets with no assets added
        vm.expectRevert(AssetRegistry.AssetExceedsMaximum.selector);
        assetRegistry.getAssets(bitFlag);
    }

    function testFuzz_getAssetsBitFlag(uint256 assetCount, uint256[] memory assetIndices) public {
        vm.assume(assetCount > 0 && assetCount <= MAX_ASSETS);
        vm.assume(assetIndices.length > 0 && assetIndices.length <= assetCount);

        address[] memory testAssets = _setupAssets(assetCount);
        address[] memory selectedAssets = new address[](assetIndices.length);
        uint256 expectedBitFlag;

        for (uint256 i = 0; i < assetIndices.length; i++) {
            uint256 index = assetIndices[i] % assetCount;
            selectedAssets[i] = testAssets[index];
            expectedBitFlag |= 1 << index;
        }

        uint256 returnedBitFlag = assetRegistry.getAssetsBitFlag(selectedAssets);

        assertEq(returnedBitFlag, expectedBitFlag, "Returned bit flag does not match expected");
    }

    function testFuzz_getAssetsBitFlag_revertWhenAssetNotEnabled(uint256 assetCount, address invalidAsset) public {
        vm.assume(assetCount > 0 && assetCount < MAX_ASSETS);
        vm.assume(invalidAsset != address(0));

        address[] memory testAssets = _setupAssets(assetCount);

        // Ensure invalidAsset is not in testAssets
        bool isAssetAdded = false;
        for (uint256 i = 0; i < assetCount; i++) {
            if (testAssets[i] == invalidAsset) {
                isAssetAdded = true;
                break;
            }
        }
        vm.assume(!isAssetAdded);

        address[] memory assetsWithInvalid = new address[](assetCount);
        for (uint256 i = 0; i < assetCount - 1; i++) {
            assetsWithInvalid[i] = testAssets[i];
        }
        assetsWithInvalid[assetCount - 1] = invalidAsset;

        vm.expectRevert(AssetRegistry.AssetNotEnabled.selector);
        assetRegistry.getAssetsBitFlag(assetsWithInvalid);
    }

    function testFuzz_getAssetsBitFlag_revertWhenExceedsMaximum(uint256 excessCount) public {
        // test up to 255 * 2 addresses in parameters exceeding the maximum limit (255)
        vm.assume(excessCount > 0 && excessCount <= MAX_ASSETS);

        _setupAssets(MAX_ASSETS);
        address[] memory excessAssets = new address[](MAX_ASSETS + excessCount);
        for (uint256 i = MAX_ASSETS; i < excessAssets.length; i++) {
            excessAssets[i] = address(uint160(i + 1));
        }
        vm.expectRevert(AssetRegistry.AssetExceedsMaximum.selector);
        assetRegistry.getAssetsBitFlag(excessAssets);
    }

    function testFuzz_hasPausedAssets(uint256 pause, uint256 bitFlag) public {
        // Find the highest bit of pause and add assets up to that index
        // then pause the assets based on the pause bit
        // then determine if the hasPausedAssets(bitFlag) should return true or false
        // compare the result with a call to the function
        vm.assume(pause < (1 << MAX_ASSETS));

        // Setup assets based on the highest bit in the pause flag
        uint256 highestBit = 0;
        for (uint256 i = 0; i < MAX_ASSETS; i++) {
            if ((pause >> i) & 1 == 1) {
                highestBit = i;
            }
        }
        vm.assume(bitFlag > 0 && bitFlag < (1 << (highestBit + 1)));

        // Add assets up to the highest bit
        address[] memory assets = _setupAssets(highestBit + 1);

        // Pause assets based on the pause bit
        vm.startPrank(users["admin"]);
        for (uint256 i = 0; i <= highestBit; i++) {
            if ((pause >> i) & 1 == 1) {
                assetRegistry.setAssetStatus(assets[i], AssetRegistry.AssetStatus.PAUSED);
            }
        }

        address[] memory bitFlagAssets = assetRegistry.getAssets(bitFlag);
        bool expectedPaused = false;
        for (uint256 i = 0; i < bitFlagAssets.length; i++) {
            if (assetRegistry.getAssetStatus(bitFlagAssets[i]) == AssetRegistry.AssetStatus.PAUSED) {
                expectedPaused = true;
                break;
            }
        }

        // Call the function and compare the result
        bool result = assetRegistry.hasPausedAssets(bitFlag);
        assertEq(result, expectedPaused, "hasPausedAssets result does not match expected");
    }
}
