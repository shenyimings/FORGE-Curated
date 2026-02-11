// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

/* solhint-disable func-name-mixedcase  */

import {LevelMintingUtils} from "../LevelMinting.utils.sol";
import "../../../../src/interfaces/ISingleAdminAccessControl.sol";
import {LevelMinting} from "../../../../src/LevelMinting.sol";
import {ILevelMinting} from "../../../../src/interfaces/ILevelMinting.sol";
import {IlvlUSD} from "../../../../src/interfaces/IlvlUSD.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {LevelMintingChild} from "../LevelMintingChild.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract LevelMintingACLTest is LevelMintingUtils {
    function setUp() public override {
        super.setUp();
    }

    function test_role_authorization() public {
        vm.deal(trader1, 1 ether);
        vm.deal(maker1, 1 ether);
        vm.deal(maker2, 1 ether);
        vm.startPrank(minter);
        DAIToken.mint(1 * 1e18, maker1);
        DAIToken.mint(1 * 1e18, trader1);
        vm.expectRevert(OnlyMinterErr);
        lvlusdToken.mint(address(maker2), 2000 * 1e18);
        vm.expectRevert(OnlyMinterErr);
        lvlusdToken.mint(address(trader2), 2000 * 1e18);
    }

    function test_fuzz_nonOwner_cannot_add_supportedAsset_revert(
        address nonOwner
    ) public {
        vm.assume(nonOwner != owner);
        address asset = address(20);
        vm.expectRevert();
        vm.prank(nonOwner);
        LevelMintingContract.addSupportedAsset(asset);
        assertFalse(LevelMintingContract.isSupportedAsset(asset));
    }

    function test_fuzz_nonOwner_cannot_remove_supportedAsset_revert(
        address nonOwner
    ) public {
        vm.assume(nonOwner != owner);
        address asset = address(20);
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit AssetAdded(asset);
        LevelMintingContract.addSupportedAsset(asset);
        assertTrue(LevelMintingContract.isSupportedAsset(asset));

        vm.expectRevert();
        vm.prank(nonOwner);
        LevelMintingContract.removeSupportedAsset(asset);
        assertTrue(LevelMintingContract.isSupportedAsset(asset));
    }

    function test_owner_canTransfer_reserve() public {
        vm.startPrank(owner);
        DAIToken.mint(1000, address(LevelMintingContract));
        LevelMintingContract.addReserveAddress(beneficiary);
        vm.expectEmit(true, true, true, true);
        emit ReserveTransfer(beneficiary, address(DAIToken), 1000);
        LevelMintingContract.transferToReserve(
            beneficiary,
            address(DAIToken),
            1000
        );
        assertEq(DAIToken.balanceOf(beneficiary), 1000);
        assertEq(DAIToken.balanceOf(address(LevelMintingContract)), 0);
    }

    function test_fuzz_nonAdmin_cannot_transferReserve_revert(
        address nonAdmin
    ) public {
        vm.assume(nonAdmin != owner);
        DAIToken.mint(1000, address(LevelMintingContract));

        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(nonAdmin),
                    " is missing role ",
                    vm.toString(adminRole)
                )
            )
        );
        vm.prank(nonAdmin);
        LevelMintingContract.transferToReserve(
            beneficiary,
            address(DAIToken),
            1000
        );
    }

    /**
     * Gatekeeper tests
     */

    function test_gatekeeper_cannot_add_minters_revert() public {
        vm.startPrank(gatekeeper);
        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(gatekeeper),
                    " is missing role ",
                    vm.toString(adminRole)
                )
            )
        );
        LevelMintingContract.grantRole(minterRole, bob);
        assertFalse(
            LevelMintingContract.hasRole(minterRole, bob),
            "Bob should lack the minter role"
        );
    }

    function test_gatekeeper_can_disable_mintRedeem() public {
        vm.startPrank(gatekeeper);
        LevelMintingContract.disableMintRedeem();

        (
            ILevelMinting.Order memory order,
            ILevelMinting.Route memory route
        ) = mint_setup(_lvlusdToMint, _DAIToDeposit, false, address(DAIToken));

        vm.prank(minter);
        vm.expectRevert(MaxMintPerBlockExceeded);
        LevelMintingContract.__mint(order, route);

        vm.prank(redeemer);
        vm.expectRevert(MaxRedeemPerBlockExceeded);
        LevelMintingContract.__redeem(order);

        assertEq(
            LevelMintingContract.maxMintPerBlock(),
            0,
            "Minting should be disabled"
        );
        assertEq(
            LevelMintingContract.maxRedeemPerBlock(),
            0,
            "Redeeming should be disabled"
        );
    }

    // Ensure that the gatekeeper is not allowed to enable/modify the minting
    function test_gatekeeper_cannot_enable_mint_revert() public {
        test_fuzz_nonAdmin_cannot_enable_mint_revert(gatekeeper);
    }

    // Ensure that the gatekeeper is not allowed to enable/modify the redeeming
    function test_gatekeeper_cannot_enable_redeem_revert() public {
        test_fuzz_nonAdmin_cannot_enable_redeem_revert(gatekeeper);
    }

    function test_fuzz_not_gatekeeper_cannot_disable_mintRedeem_revert(
        address notGatekeeper
    ) public {
        vm.assume(notGatekeeper != gatekeeper);
        vm.startPrank(notGatekeeper);
        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(notGatekeeper),
                    " is missing role ",
                    vm.toString(gatekeeperRole)
                )
            )
        );
        LevelMintingContract.disableMintRedeem();

        assertTrue(LevelMintingContract.maxMintPerBlock() > 0);
        assertTrue(LevelMintingContract.maxRedeemPerBlock() > 0);
    }

    /**
     * Admin tests
     */
    function test_admin_can_disable_mint(bool performCheckMint) public {
        vm.prank(owner);
        LevelMintingContract.setMaxMintPerBlock(0);

        if (performCheckMint) maxMint_perBlock_exceeded_revert(1e18);

        assertEq(
            LevelMintingContract.maxMintPerBlock(),
            0,
            "The minting should be disabled"
        );
    }

    function test_admin_can_disable__redeem(bool performCheckRedeem) public {
        vm.prank(owner);
        LevelMintingContract.setMaxRedeemPerBlock(0);

        if (performCheckRedeem) maxRedeem_perBlock_exceeded_revert(1e18);

        assertEq(
            LevelMintingContract.maxRedeemPerBlock(),
            0,
            "The redeem should be disabled"
        );
    }

    function test_admin_can_enable_mint() public {
        vm.startPrank(owner);
        LevelMintingContract.setMaxMintPerBlock(0);

        assertEq(
            LevelMintingContract.maxMintPerBlock(),
            0,
            "The minting should be disabled"
        );

        // Re-enable the minting
        LevelMintingContract.setMaxMintPerBlock(_maxMintPerBlock);

        vm.stopPrank();

        executeMint();

        assertTrue(
            LevelMintingContract.maxMintPerBlock() > 0,
            "The minting should be enabled"
        );
    }

    function test_fuzz_nonAdmin_cannot_enable_mint_revert(
        address notAdmin
    ) public {
        vm.assume(notAdmin != owner);

        test_admin_can_disable_mint(false);

        vm.prank(notAdmin);
        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(notAdmin),
                    " is missing role ",
                    vm.toString(adminRole)
                )
            )
        );
        LevelMintingContract.setMaxMintPerBlock(_maxMintPerBlock);

        maxMint_perBlock_exceeded_revert(1e18);

        assertEq(
            LevelMintingContract.maxMintPerBlock(),
            0,
            "The minting should remain disabled"
        );
    }

    function test_fuzz_nonAdmin_cannot_enable_redeem_revert(
        address notAdmin
    ) public {
        vm.assume(notAdmin != owner);

        test_admin_can_disable__redeem(false);

        vm.prank(notAdmin);
        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(notAdmin),
                    " is missing role ",
                    vm.toString(adminRole)
                )
            )
        );
        LevelMintingContract.setMaxRedeemPerBlock(_maxRedeemPerBlock);

        maxRedeem_perBlock_exceeded_revert(1e18);

        assertEq(
            LevelMintingContract.maxRedeemPerBlock(),
            0,
            "The redeeming should remain disabled"
        );
    }

    function test_admin_can_enable__redeem() public {
        vm.startPrank(owner);
        LevelMintingContract.setMaxRedeemPerBlock(0);

        assertEq(
            LevelMintingContract.maxRedeemPerBlock(),
            0,
            "The redeem should be disabled"
        );

        // Re-enable the redeeming
        LevelMintingContract.setMaxRedeemPerBlock(_maxRedeemPerBlock);

        vm.stopPrank();

        executeRedeem();

        assertTrue(
            LevelMintingContract.maxRedeemPerBlock() > 0,
            "The redeeming should be enabled"
        );
    }

    function test_admin_can_add_gatekeeper() public {
        vm.startPrank(owner);
        LevelMintingContract.grantRole(gatekeeperRole, bob);

        assertTrue(
            LevelMintingContract.hasRole(gatekeeperRole, bob),
            "Bob should have the gatekeeper role"
        );
        vm.stopPrank();
    }

    function test_admin_can_remove_gatekeeper() public {
        test_admin_can_add_gatekeeper();

        vm.startPrank(owner);
        LevelMintingContract.revokeRole(gatekeeperRole, bob);

        assertFalse(
            LevelMintingContract.hasRole(gatekeeperRole, bob),
            "Bob should no longer have the gatekeeper role"
        );

        vm.stopPrank();
    }

    function test_fuzz_notAdmin_cannot_remove_gatekeeper(
        address notAdmin
    ) public {
        test_admin_can_add_gatekeeper();

        vm.assume(notAdmin != owner);
        vm.startPrank(notAdmin);
        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(notAdmin),
                    " is missing role ",
                    vm.toString(adminRole)
                )
            )
        );
        LevelMintingContract.revokeRole(gatekeeperRole, bob);

        assertTrue(
            LevelMintingContract.hasRole(gatekeeperRole, bob),
            "Bob should maintain the gatekeeper role"
        );

        vm.stopPrank();
    }

    function test_fuzz_notAdmin_cannot_add_gatekeeper(address notAdmin) public {
        vm.assume(notAdmin != owner);
        vm.startPrank(notAdmin);
        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    Strings.toHexString(notAdmin),
                    " is missing role ",
                    vm.toString(adminRole)
                )
            )
        );
        LevelMintingContract.grantRole(gatekeeperRole, bob);

        assertFalse(
            LevelMintingContract.hasRole(gatekeeperRole, bob),
            "Bob should lack the gatekeeper role"
        );

        vm.stopPrank();
    }

    function test_base_transferAdmin() public {
        vm.prank(owner);
        LevelMintingContract.transferAdmin(newOwner);
        assertTrue(LevelMintingContract.hasRole(adminRole, owner));
        assertFalse(LevelMintingContract.hasRole(adminRole, newOwner));

        vm.prank(newOwner);
        LevelMintingContract.acceptAdmin();
        assertFalse(LevelMintingContract.hasRole(adminRole, owner));
        assertTrue(LevelMintingContract.hasRole(adminRole, newOwner));
    }

    function test_transferAdmin_notAdmin() public {
        vm.startPrank(randomer);
        vm.expectRevert();
        LevelMintingContract.transferAdmin(randomer);
    }

    function test_grantRole_AdminRoleExternally() public {
        vm.startPrank(randomer);
        vm.expectRevert(
            "AccessControl: account 0xc91041eae7bf78e1040f4abd7b29908651f45546 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        LevelMintingContract.grantRole(adminRole, randomer);
        vm.stopPrank();
    }

    function test_revokeRole_notAdmin() public {
        vm.startPrank(randomer);
        vm.expectRevert(
            "AccessControl: account 0xc91041eae7bf78e1040f4abd7b29908651f45546 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        LevelMintingContract.revokeRole(adminRole, owner);
    }

    function test_revokeRole_AdminRole() public {
        vm.startPrank(owner);
        vm.expectRevert();
        LevelMintingContract.revokeRole(adminRole, owner);
    }

    function test_renounceRole_notAdmin() public {
        vm.startPrank(randomer);
        vm.expectRevert(InvalidAdminChange);
        LevelMintingContract.renounceRole(adminRole, owner);
    }

    function test_renounceRole_AdminRole() public {
        vm.prank(owner);
        vm.expectRevert(InvalidAdminChange);
        LevelMintingContract.renounceRole(adminRole, owner);
    }

    function test_revoke_AdminRole() public {
        vm.prank(owner);
        vm.expectRevert(InvalidAdminChange);
        LevelMintingContract.revokeRole(adminRole, owner);
    }

    function testCanRepeatedlyTransferAdmin() public {
        vm.startPrank(owner);
        LevelMintingContract.transferAdmin(newOwner);
        LevelMintingContract.transferAdmin(randomer);
        vm.stopPrank();
    }

    function testCancelTransferAdmin() public {
        vm.startPrank(owner);
        LevelMintingContract.transferAdmin(newOwner);
        LevelMintingContract.transferAdmin(address(0));
        vm.stopPrank();
        assertTrue(LevelMintingContract.hasRole(adminRole, owner));
        assertFalse(LevelMintingContract.hasRole(adminRole, address(0)));
        assertFalse(LevelMintingContract.hasRole(adminRole, newOwner));
    }

    function test_admin_cannot_transfer_self() public {
        vm.startPrank(owner);
        vm.expectRevert(InvalidAdminChange);
        LevelMintingContract.transferAdmin(owner);
        vm.stopPrank();
        assertTrue(LevelMintingContract.hasRole(adminRole, owner));
    }

    function testAdminCanCancelTransfer() public {
        vm.startPrank(owner);
        LevelMintingContract.transferAdmin(newOwner);
        LevelMintingContract.transferAdmin(address(0));
        vm.stopPrank();

        vm.prank(newOwner);
        vm.expectRevert(ISingleAdminAccessControl.NotPendingAdmin.selector);
        LevelMintingContract.acceptAdmin();

        assertTrue(LevelMintingContract.hasRole(adminRole, owner));
        assertFalse(LevelMintingContract.hasRole(adminRole, address(0)));
        assertFalse(LevelMintingContract.hasRole(adminRole, newOwner));
    }

    function testOwnershipCannotBeRenounced() public {
        vm.startPrank(owner);
        vm.expectRevert(ISingleAdminAccessControl.InvalidAdminChange.selector);
        LevelMintingContract.renounceRole(adminRole, owner);

        vm.expectRevert(ISingleAdminAccessControl.InvalidAdminChange.selector);
        LevelMintingContract.revokeRole(adminRole, owner);
        vm.stopPrank();
        assertEq(LevelMintingContract.owner(), owner);
        assertTrue(LevelMintingContract.hasRole(adminRole, owner));
    }

    function testOwnershipTransferRequiresTwoSteps() public {
        vm.prank(owner);
        LevelMintingContract.transferAdmin(newOwner);
        assertEq(LevelMintingContract.owner(), owner);
        assertTrue(LevelMintingContract.hasRole(adminRole, owner));
        assertNotEq(LevelMintingContract.owner(), newOwner);
        assertFalse(LevelMintingContract.hasRole(adminRole, newOwner));
    }

    function testCanTransferOwnership() public {
        vm.prank(owner);
        LevelMintingContract.transferAdmin(newOwner);
        vm.prank(newOwner);
        LevelMintingContract.acceptAdmin();
        assertTrue(LevelMintingContract.hasRole(adminRole, newOwner));
        assertFalse(LevelMintingContract.hasRole(adminRole, owner));
    }

    function testNewOwnerCanPerformOwnerActions() public {
        vm.prank(owner);
        LevelMintingContract.transferAdmin(newOwner);
        vm.startPrank(newOwner);
        LevelMintingContract.acceptAdmin();
        LevelMintingContract.grantRole(gatekeeperRole, bob);
        vm.stopPrank();
        assertTrue(LevelMintingContract.hasRole(adminRole, newOwner));
        assertTrue(LevelMintingContract.hasRole(gatekeeperRole, bob));
    }

    function testOldOwnerCantPerformOwnerActions() public {
        vm.prank(owner);
        LevelMintingContract.transferAdmin(newOwner);
        vm.prank(newOwner);
        LevelMintingContract.acceptAdmin();
        assertTrue(LevelMintingContract.hasRole(adminRole, newOwner));
        assertFalse(LevelMintingContract.hasRole(adminRole, owner));
        vm.prank(owner);
        vm.expectRevert(
            "AccessControl: account 0xe05fcc23807536bee418f142d19fa0d21bb0cff7 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        LevelMintingContract.grantRole(gatekeeperRole, bob);
        assertFalse(LevelMintingContract.hasRole(gatekeeperRole, bob));
    }

    function testOldOwnerCantTransferOwnership() public {
        vm.prank(owner);
        LevelMintingContract.transferAdmin(newOwner);
        vm.prank(newOwner);
        LevelMintingContract.acceptAdmin();
        assertTrue(LevelMintingContract.hasRole(adminRole, newOwner));
        assertFalse(LevelMintingContract.hasRole(adminRole, owner));
        vm.prank(owner);
        vm.expectRevert(
            "AccessControl: account 0xe05fcc23807536bee418f142d19fa0d21bb0cff7 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        LevelMintingContract.transferAdmin(bob);
        assertFalse(LevelMintingContract.hasRole(adminRole, bob));
    }

    function testNonAdminCanRenounceRoles() public {
        vm.prank(owner);
        LevelMintingContract.grantRole(gatekeeperRole, bob);
        assertTrue(LevelMintingContract.hasRole(gatekeeperRole, bob));

        vm.prank(bob);
        LevelMintingContract.renounceRole(gatekeeperRole, bob);
        assertFalse(LevelMintingContract.hasRole(gatekeeperRole, bob));
    }

    function testCorrectInitConfig() public {
        LevelMinting levelMinting2 = new LevelMintingChild(
            IlvlUSD(address(lvlusdToken)),
            assets,
            oracles,
            reserves,
            ratios,
            randomer,
            _maxMintPerBlock,
            _maxRedeemPerBlock
        );
        assertFalse(levelMinting2.hasRole(adminRole, owner));
        assertNotEq(levelMinting2.owner(), owner);
        assertTrue(levelMinting2.hasRole(adminRole, randomer));
        assertEq(levelMinting2.owner(), randomer);
    }
}
