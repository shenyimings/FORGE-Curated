// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { VaultManager, BaseController, IControlledVault } from "../../../src/controller/VaultManager.sol";

import { ControllerTest } from "./Controller.t.sol";

abstract contract Controller_VaultManager_Test is ControllerTest {
    address[3] vault = [makeAddr("vault1"), makeAddr("vault2"), makeAddr("vault3")];
    address[3] asset = [makeAddr("asset1"), makeAddr("asset2"), makeAddr("asset3")];
    BaseController.VaultSettings settings;

    address manager = makeAddr("manager");
    bytes32 managerRole;

    function _mockVault(address _vault, address _asset) internal {
        vm.mockCall(
            _vault, abi.encodeWithSelector(IControlledVault.controller.selector), abi.encode(address(controller))
        );
        vm.mockCall(_vault, abi.encodeWithSelector(IControlledVault.asset.selector), abi.encode(_asset));
        vm.mockCall(_vault, abi.encodeWithSelector(IControlledVault.totalNormalizedAssets.selector), abi.encode(0));
        controller.workaround_setPriceFeedExists(_asset, true);
    }

    function setUp() public virtual override {
        super.setUp();

        _mockVault(vault[0], asset[0]);
        _mockVault(vault[1], asset[1]);
        _mockVault(vault[2], asset[2]);

        managerRole = controller.VAULT_MANAGER_ROLE();
        vm.prank(admin);
        controller.grantRole(managerRole, manager);

        vm.label(vault[0], "Vault 1");
        vm.label(vault[1], "Vault 2");
        vm.label(vault[2], "Vault 3");

        vm.label(asset[0], "Asset 1");
        vm.label(asset[1], "Asset 2");
        vm.label(asset[2], "Asset 3");
    }
}

contract Controller_VaultManager_AddVault_Test is Controller_VaultManager_Test {
    bool isMainVaultForAsset = true;

    function testFuzz_shouldRevert_whenCallerNotVaultManager(address caller) public {
        vm.assume(caller != manager);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        controller.addVault(vault[0], settings, isMainVaultForAsset);
    }

    function test_shouldRevert_whenZeroVault() public {
        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_InvalidVault.selector);
        controller.addVault(address(0), settings, isMainVaultForAsset);
    }

    function test_shouldRevert_whenSentinelVault() public {
        address sentinel = controller.SENTINEL_VAULTS();

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_InvalidVault.selector);
        controller.addVault(sentinel, settings, isMainVaultForAsset);
    }

    function test_shouldRevert_whenVaultAlreadyAdded() public {
        vm.prank(manager);
        controller.addVault(vault[0], settings, isMainVaultForAsset);

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_InvalidVault.selector);
        controller.addVault(vault[0], settings, isMainVaultForAsset);
    }

    function test_shouldRevert_whenVaultsControllerMismatch() public {
        vm.mockCall(
            vault[0],
            abi.encodeWithSelector(IControlledVault.controller.selector),
            abi.encode(makeAddr("fakeController"))
        );

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_ControllerMismatch.selector);
        controller.addVault(vault[0], settings, isMainVaultForAsset);
    }

    function test_shouldRevert_whenNoPriceFeedForAsset() public {
        controller.workaround_setPriceFeedExists(asset[0], false);

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_NoPriceFeedForAsset.selector);
        controller.addVault(vault[0], settings, isMainVaultForAsset);
    }

    function testFuzz_shouldRevert_whenInvalidVaultSettingsMaxProportionality(uint256 maxProportionality) public {
        maxProportionality = bound(maxProportionality, controller.MAX_BPS() + 1, type(uint16).max);

        // forge-lint: disable-next-line(unsafe-typecast)
        settings.maxProportionality = uint16(maxProportionality);

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_InvalidMaxProportionality.selector);
        controller.addVault(vault[0], settings, isMainVaultForAsset);
    }

    function testFuzz_shouldRevert_whenInvalidVaultSettingsMinProportionality(uint256 minProportionality) public {
        minProportionality = bound(minProportionality, controller.MAX_BPS() + 1, type(uint16).max);

        // forge-lint: disable-next-line(unsafe-typecast)
        settings.minProportionality = uint16(minProportionality);

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_InvalidMinProportionality.selector);
        controller.addVault(vault[0], settings, isMainVaultForAsset);
    }

    function testFuzz_shouldRevert_whenInvalidVaultSettingsMinNotLessThanMax() public {
        settings.maxProportionality = 5000;
        settings.minProportionality = 6000;

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_MinProportionalityNotLessThanMax.selector);
        controller.addVault(vault[0], settings, isMainVaultForAsset);
    }

    function test_shouldAddVaultToLinkedList() public {
        vm.prank(manager);
        controller.addVault(vault[0], settings, isMainVaultForAsset);

        address sentinel = controller.SENTINEL_VAULTS();
        assertEq(controller.exposed_vaultsLinkedList(sentinel), vault[0]);
        assertEq(controller.exposed_vaultsLinkedList(vault[0]), sentinel);

        vm.prank(manager);
        controller.addVault(vault[1], settings, isMainVaultForAsset);

        assertEq(controller.exposed_vaultsLinkedList(sentinel), vault[1]);
        assertEq(controller.exposed_vaultsLinkedList(vault[1]), vault[0]);
        assertEq(controller.exposed_vaultsLinkedList(vault[0]), sentinel);
    }

    function testFuzz_shouldSetVaultSettings(uint224 maxCapacity, uint16 maxProp, uint16 minProp) public {
        maxProp = uint16(bound(maxProp, 0, controller.MAX_BPS()));
        minProp = uint16(bound(minProp, 0, controller.MAX_BPS()));
        vm.assume(minProp <= maxProp);

        settings.maxCapacity = maxCapacity;
        settings.minProportionality = minProp;
        settings.maxProportionality = maxProp;

        vm.prank(manager);
        controller.addVault(vault[0], settings, isMainVaultForAsset);

        (uint224 actualMaxCapacity, uint16 actualMinProp, uint16 actualMaxProp) = controller.vaultSettings(vault[0]);
        assertEq(actualMaxCapacity, settings.maxCapacity);
        assertEq(actualMinProp, settings.minProportionality);
        assertEq(actualMaxProp, settings.maxProportionality);
    }

    function test_shouldEmit_VaultAdded() public {
        vm.expectEmit();
        emit VaultManager.VaultAdded(vault[0], asset[0]);

        vm.prank(manager);
        controller.addVault(vault[0], settings, isMainVaultForAsset);
    }

    function test_shouldEmit_VaultSettingsUpdated() public {
        settings.maxCapacity = 1e24;
        settings.maxProportionality = 8000;
        settings.minProportionality = 2000;

        vm.expectEmit();
        emit VaultManager.VaultSettingsUpdated(
            vault[0], settings.maxCapacity, settings.maxProportionality, settings.minProportionality
        );

        vm.prank(manager);
        controller.addVault(vault[0], settings, isMainVaultForAsset);
    }

    function test_shouldSetVaultAsMainForAsset_whenIsMainVaultForAssetFalse_whenNoMainVault() public {
        vm.prank(manager);
        controller.addVault(vault[0], settings, false);

        assertEq(controller.vaultFor(asset[0]), vault[0]);
    }

    function test_shouldSetVaultAsMainForAsset_whenIsMainVaultForAssetTrue_whenOtherMainVault() public {
        vm.prank(manager);
        controller.addVault(vault[0], settings, true);

        address mainVault = makeAddr("mainVault");
        _mockVault(mainVault, asset[0]);

        vm.prank(manager);
        controller.addVault(mainVault, settings, true);

        assertEq(controller.vaultFor(asset[0]), mainVault);
    }

    function test_shouldNotSetVaultAsMainForAsset_whenIsMainVaultForAssetFalse_whenOtherMainVault() public {
        vm.prank(manager);
        controller.addVault(vault[0], settings, true);

        address notMainVault = makeAddr("notMainVault");
        _mockVault(notMainVault, asset[0]);

        vm.prank(manager);
        controller.addVault(notMainVault, settings, false);

        assertEq(controller.vaultFor(asset[0]), vault[0]);
    }

    function test_shouldEmit_MainVaultForAssetUpdated() public {
        vm.expectEmit();
        emit VaultManager.MainVaultForAssetUpdated(asset[0], address(0), vault[0]);

        vm.prank(manager);
        controller.addVault(vault[0], settings, true);

        address mainVault = makeAddr("mainVault");
        _mockVault(mainVault, asset[0]);

        vm.expectEmit();
        emit VaultManager.MainVaultForAssetUpdated(asset[0], vault[0], mainVault);

        vm.prank(manager);
        controller.addVault(mainVault, settings, true);
    }
}

contract Controller_VaultManager_RemoveVault_Test is Controller_VaultManager_Test {
    address prevVault;

    function setUp() public override {
        super.setUp();

        settings = BaseController.VaultSettings(1, 2, 3);

        vm.prank(manager);
        controller.addVault(vault[0], settings, true);
        vm.prank(manager);
        controller.addVault(vault[1], settings, true);

        prevVault = vault[1];
    }

    function testFuzz_shouldRevert_whenCallerNotVaultManager(address caller) public {
        vm.assume(caller != manager);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        controller.removeVault(vault[0], prevVault);
    }

    function test_shouldRevert_whenVaultNotAdded() public {
        address fakeVault = makeAddr("fakeVault");

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_InvalidVault.selector);
        controller.removeVault(fakeVault, prevVault);
    }

    function test_shouldRevert_whenVaultNotEmpty() public {
        vm.mockCall(vault[0], abi.encodeWithSelector(IControlledVault.totalNormalizedAssets.selector), abi.encode(1));

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_VaultNotEmpty.selector);
        controller.removeVault(vault[0], prevVault);
    }

    function test_shouldRevert_whenInvalidPrevVault() public {
        address fakePrevVault = makeAddr("fakePrevVault");

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_InvalidPrevVault.selector);
        controller.removeVault(vault[0], fakePrevVault);
    }

    function test_shouldRemoveVaultFromLinkedList() public {
        assertEq(controller.exposed_vaultsLinkedList(prevVault), vault[0]);
        assertEq(controller.exposed_vaultsLinkedList(vault[0]), controller.SENTINEL_VAULTS());

        vm.prank(manager);
        controller.removeVault(vault[0], prevVault);

        assertEq(controller.exposed_vaultsLinkedList(prevVault), controller.SENTINEL_VAULTS());
        assertEq(controller.exposed_vaultsLinkedList(vault[0]), address(0));
    }

    function test_shouldDeleteVaultSettings() public {
        vm.prank(manager);
        controller.removeVault(vault[0], prevVault);

        (uint224 actualMaxCapacity, uint16 actualMaxProp, uint16 actualMinProp) = controller.vaultSettings(vault[0]);
        assertEq(actualMaxCapacity, 0);
        assertEq(actualMaxProp, 0);
        assertEq(actualMinProp, 0);
    }

    function test_shouldEmit_VaultRemoved() public {
        vm.expectEmit();
        emit VaultManager.VaultRemoved(vault[0]);

        vm.prank(manager);
        controller.removeVault(vault[0], prevVault);
    }

    function test_shouldEmit_VaultSettingsUpdated() public {
        vm.expectEmit();
        emit VaultManager.VaultSettingsUpdated(vault[0], 0, 0, 0);

        vm.prank(manager);
        controller.removeVault(vault[0], prevVault);
    }

    function test_shouldDeleteMainVaultForAsset_whenRemovingMainVault() public {
        assertEq(controller.vaultFor(asset[0]), vault[0]);

        vm.prank(manager);
        controller.removeVault(vault[0], prevVault);

        assertEq(controller.vaultFor(asset[0]), address(0));
    }

    function test_shouldNotDeleteMainVaultForAsset_whenRemovingNonMainVault() public {
        address mainVault = makeAddr("mainVault");
        _mockVault(mainVault, asset[0]);

        vm.prank(manager);
        controller.addVault(mainVault, settings, true);

        assertEq(controller.vaultFor(asset[0]), mainVault);

        vm.prank(manager);
        controller.removeVault(vault[0], prevVault);

        assertEq(controller.vaultFor(asset[0]), mainVault);
    }

    function test_shouldEmit_MainVaultForAssetUpdated() public {
        vm.expectEmit();
        emit VaultManager.MainVaultForAssetUpdated(asset[0], vault[0], address(0));

        vm.prank(manager);
        controller.removeVault(vault[0], prevVault);
    }
}

contract Controller_VaultManager_UpdateVaultSettings_Test is Controller_VaultManager_Test {
    function setUp() public override {
        super.setUp();

        settings = BaseController.VaultSettings(1, 2, 3);

        vm.prank(manager);
        controller.addVault(vault[0], settings, true);
    }

    function testFuzz_shouldRevert_whenCallerNotVaultManager(address caller) public {
        vm.assume(caller != manager);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        controller.updateVaultSettings(vault[0], settings);
    }

    function test_shouldRevert_whenVaultNotAdded() public {
        address fakeVault = makeAddr("fakeVault");

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_InvalidVault.selector);
        controller.updateVaultSettings(fakeVault, settings);
    }

    function testFuzz_shouldRevert_whenInvalidVaultSettingsMaxProportionality(uint256 maxProportionality) public {
        maxProportionality = bound(maxProportionality, controller.MAX_BPS() + 1, type(uint16).max);

        // forge-lint: disable-next-line(unsafe-typecast)
        settings.maxProportionality = uint16(maxProportionality);

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_InvalidMaxProportionality.selector);
        controller.updateVaultSettings(vault[0], settings);
    }

    function testFuzz_shouldRevert_whenInvalidVaultSettingsMinProportionality(uint256 minProportionality) public {
        minProportionality = bound(minProportionality, controller.MAX_BPS() + 1, type(uint16).max);

        // forge-lint: disable-next-line(unsafe-typecast)
        settings.minProportionality = uint16(minProportionality);

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_InvalidMinProportionality.selector);
        controller.updateVaultSettings(vault[0], settings);
    }

    function testFuzz_shouldRevert_whenInvalidVaultSettingsMinNotLessThanMax() public {
        settings.maxProportionality = 5000;
        settings.minProportionality = 6000;

        vm.prank(manager);
        vm.expectRevert(VaultManager.Vault_MinProportionalityNotLessThanMax.selector);
        controller.updateVaultSettings(vault[0], settings);
    }

    function testFuzz_shouldSetVaultSettings(uint224 maxCapacity, uint16 maxProp, uint16 minProp) public {
        maxProp = uint16(bound(maxProp, 0, controller.MAX_BPS()));
        minProp = uint16(bound(minProp, 0, controller.MAX_BPS()));
        vm.assume(minProp <= maxProp);

        settings.maxCapacity = maxCapacity;
        settings.minProportionality = minProp;
        settings.maxProportionality = maxProp;

        vm.prank(manager);
        controller.updateVaultSettings(vault[0], settings);

        (uint224 actualMaxCapacity, uint16 actualMinProp, uint16 actualMaxProp) = controller.vaultSettings(vault[0]);
        assertEq(actualMaxCapacity, settings.maxCapacity);
        assertEq(actualMinProp, settings.minProportionality);
        assertEq(actualMaxProp, settings.maxProportionality);
    }

    function test_shouldEmit_VaultSettingsUpdated() public {
        settings.maxCapacity = 1e24;
        settings.maxProportionality = 8000;
        settings.minProportionality = 2000;

        vm.expectEmit();
        emit VaultManager.VaultSettingsUpdated(
            vault[0], settings.maxCapacity, settings.maxProportionality, settings.minProportionality
        );

        vm.prank(manager);
        controller.updateVaultSettings(vault[0], settings);
    }
}

contract Controller_VaultManager_SetMainVault_Test is Controller_VaultManager_Test {
    address mainVault = makeAddr("mainVault");

    function setUp() public override {
        super.setUp();

        _mockVault(mainVault, asset[0]);

        settings = BaseController.VaultSettings(1, 2, 3);

        vm.prank(manager);
        controller.addVault(mainVault, settings, true);
        vm.prank(manager);
        controller.addVault(vault[0], settings, false);
    }

    function testFuzz_shouldRevert_whenCallerNotVaultManager(address caller) public {
        vm.assume(caller != manager);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        controller.setMainVault(vault[0]);
    }

    function test_shouldRevert_whenVaultNotAdded() public {
        address fakeVault = makeAddr("fakeVault");

        vm.expectRevert(VaultManager.Vault_InvalidVault.selector);
        vm.prank(manager);
        controller.setMainVault(fakeVault);
    }

    function test_shouldRevert_whenVaultIsMainVault() public {
        vm.expectRevert(VaultManager.Vault_AlreadyMainVaultForAsset.selector);
        vm.prank(manager);
        controller.setMainVault(mainVault);
    }

    function test_shouldSetMainVaultForAsset() public {
        assertEq(controller.vaultFor(asset[0]), mainVault);

        vm.prank(manager);
        controller.setMainVault(vault[0]);

        assertEq(controller.vaultFor(asset[0]), vault[0]);
    }

    function test_shouldEmit_MainVaultForAssetUpdated() public {
        vm.expectEmit();
        emit VaultManager.MainVaultForAssetUpdated(asset[0], mainVault, vault[0]);

        vm.prank(manager);
        controller.setMainVault(vault[0]);
    }
}

contract Controller_VaultManager_IsVault_Test is Controller_VaultManager_Test {
    function setUp() public override {
        super.setUp();

        settings = BaseController.VaultSettings(1, 2, 3);

        vm.prank(manager);
        controller.addVault(vault[0], settings, true);
        vm.prank(manager);
        controller.addVault(vault[1], settings, true);
        vm.prank(manager);
        controller.addVault(vault[2], settings, true);
    }

    function test_shouldReturnFalse_whenZeroAddress() public view {
        assertFalse(controller.isVault(address(0)));
    }

    function test_shouldReturnFalse_whenSentinelAddress() public view {
        address sentinel = controller.SENTINEL_VAULTS();
        assertFalse(controller.isVault(sentinel));
    }

    function testFuzz_shouldReturnFalse_whenRandomAddress(address random) public view {
        vm.assume(
            random != address(0) && random != controller.SENTINEL_VAULTS() && random != vault[0] && random != vault[1]
                && random != vault[2]
        );
        assertFalse(controller.isVault(random));
    }

    function test_shouldReturnTrue_whenAddedVault() public view {
        assertTrue(controller.isVault(vault[0]));
        assertTrue(controller.isVault(vault[1]));
        assertTrue(controller.isVault(vault[2]));
    }
}

contract Controller_VaultManager_Vaults_Test is Controller_VaultManager_Test {
    function test_shouldReturnEmptyArray_whenNoVaultsAdded() public view {
        address[] memory currentVaults = controller.vaults();
        assertEq(currentVaults.length, 0);
    }

    function test_shouldReturnAllAddedVaultsInOrder() public {
        BaseController.VaultSettings memory settings = BaseController.VaultSettings(1, 2, 3);

        vm.prank(manager);
        controller.addVault(vault[0], settings, true);
        vm.prank(manager);
        controller.addVault(vault[1], settings, true);
        vm.prank(manager);
        controller.addVault(vault[2], settings, true);

        address[] memory currentVaults = controller.vaults();
        assertEq(currentVaults.length, 3);
        assertEq(currentVaults[0], vault[2]);
        assertEq(currentVaults[1], vault[1]);
        assertEq(currentVaults[2], vault[0]);
    }
}

contract Controller_VaultManager_VaultsOverview_Test is Controller_VaultManager_Test {
    function test_shouldReturnEmpty_whenNoVaults() public view {
        VaultManager.VaultsOverview memory overview = controller.exposed_vaultsOverview(false);

        assertEq(overview.vaults.length, 0);
        assertEq(overview.assets.length, 0);
        assertEq(overview.settings.length, 0);
        assertEq(overview.totalAssets, 0);
        assertEq(overview.totalValue, 0);
    }

    function test_shouldReturnOverview_whenOneVault() public {
        _mockVault(makeAddr("vault1"), makeAddr("asset1"), 100e18, makeAddr("feed1"), 1.1e8, 8, 1, 2, 3);

        VaultManager.VaultsOverview memory overview = controller.exposed_vaultsOverview(true);

        assertEq(overview.vaults.length, 1);
        assertEq(overview.vaults[0], makeAddr("vault1"));
        assertEq(overview.assets.length, 1);
        assertEq(overview.assets[0], 100e18);
        assertEq(overview.settings.length, 1);
        assertEq(overview.settings[0].maxCapacity, 1);
        assertEq(overview.settings[0].minProportionality, 2);
        assertEq(overview.settings[0].maxProportionality, 3);
        assertEq(overview.totalAssets, 100e18);
        assertEq(overview.totalValue, 110e18);
    }

    function test_shouldReturnOverview_whenMultipleVaults() public {
        _mockVault(makeAddr("vault1"), makeAddr("asset1"), 100e18, makeAddr("feed1"), 1.1e8, 8, 1, 2, 3);
        _mockVault(makeAddr("vault2"), makeAddr("asset2"), 200e18, makeAddr("feed2"), 1.2e8, 8, 4, 5, 6);
        _mockVault(makeAddr("vault3"), makeAddr("asset3"), 300e18, makeAddr("feed3"), 1.3e8, 8, 7, 8, 9);

        VaultManager.VaultsOverview memory overview = controller.exposed_vaultsOverview(true);

        assertEq(overview.vaults.length, 3);
        assertEq(overview.vaults[2], makeAddr("vault1"));
        assertEq(overview.vaults[1], makeAddr("vault2"));
        assertEq(overview.vaults[0], makeAddr("vault3"));
        assertEq(overview.assets.length, 3);
        assertEq(overview.assets[2], 100e18);
        assertEq(overview.assets[1], 200e18);
        assertEq(overview.assets[0], 300e18);
        assertEq(overview.settings.length, 3);
        assertEq(overview.settings[2].maxCapacity, 1);
        assertEq(overview.settings[2].minProportionality, 2);
        assertEq(overview.settings[2].maxProportionality, 3);
        assertEq(overview.settings[1].maxCapacity, 4);
        assertEq(overview.settings[1].minProportionality, 5);
        assertEq(overview.settings[1].maxProportionality, 6);
        assertEq(overview.settings[0].maxCapacity, 7);
        assertEq(overview.settings[0].minProportionality, 8);
        assertEq(overview.settings[0].maxProportionality, 9);
        assertEq(overview.totalAssets, 600e18);
        assertEq(overview.totalValue, 740e18);
    }

    function test_shouldReturnOverviewWithoutTotalValue_whenMultipleVaults() public {
        _mockVault(makeAddr("vault1"), makeAddr("asset1"), 100e18, makeAddr("feed1"), 1.1e8, 8, 1, 2, 3);
        _mockVault(makeAddr("vault2"), makeAddr("asset2"), 200e18, makeAddr("feed2"), 1.2e8, 9, 4, 5, 6);
        _mockVault(makeAddr("vault3"), makeAddr("asset3"), 300e18, makeAddr("feed3"), 1.3e8, 10, 7, 8, 9);

        VaultManager.VaultsOverview memory overview = controller.exposed_vaultsOverview(false);

        assertEq(overview.vaults.length, 3);
        assertEq(overview.vaults[2], makeAddr("vault1"));
        assertEq(overview.vaults[1], makeAddr("vault2"));
        assertEq(overview.vaults[0], makeAddr("vault3"));
        assertEq(overview.assets.length, 3);
        assertEq(overview.assets[2], 100e18);
        assertEq(overview.assets[1], 200e18);
        assertEq(overview.assets[0], 300e18);
        assertEq(overview.settings.length, 3);
        assertEq(overview.settings[2].maxCapacity, 1);
        assertEq(overview.settings[2].minProportionality, 2);
        assertEq(overview.settings[2].maxProportionality, 3);
        assertEq(overview.settings[1].maxCapacity, 4);
        assertEq(overview.settings[1].minProportionality, 5);
        assertEq(overview.settings[1].maxProportionality, 6);
        assertEq(overview.settings[0].maxCapacity, 7);
        assertEq(overview.settings[0].minProportionality, 8);
        assertEq(overview.settings[0].maxProportionality, 9);
        assertEq(overview.totalAssets, 600e18);
        assertEq(overview.totalValue, 0);
    }
}
