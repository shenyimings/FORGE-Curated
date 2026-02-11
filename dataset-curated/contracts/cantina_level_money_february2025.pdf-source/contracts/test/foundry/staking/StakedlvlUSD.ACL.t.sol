// SPDX-License-Identifier: MIT
pragma solidity >=0.8;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import {SigUtils} from "../../utils/SigUtils.sol";

import {lvlUSD} from "../../../src/lvlUSD.sol";
import {StakedlvlUSD} from "../../../src/StakedlvlUSD.sol";
import {IStakedlvlUSD} from "../../../src/interfaces/IStakedlvlUSD.sol";
import {IlvlUSD} from "../../../src/interfaces/IlvlUSD.sol";
import "../../../src/interfaces/ISingleAdminAccessControl.sol";
import "../../../src/interfaces/IERC20Events.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin-4.9.0/contracts/interfaces/IERC20.sol";

contract StakedlvlUSDACL is Test, IERC20Events {
    lvlUSD public lvlUSDToken;
    StakedlvlUSD public stakedlvlUSD;
    SigUtils public sigUtilslvlUSD;
    SigUtils public sigUtilsStakedlvlUSD;

    address public owner;
    address public rewarder;
    address public alice;
    address public newOwner;
    address public greg;

    bytes32 public DEFAULT_ADMIN_ROLE;
    bytes32 public constant DENYLIST_MANAGER_ROLE =
        keccak256("DENYLIST_MANAGER_ROLE");
    bytes32 public constant FULL_RESTRICTED_STAKER_ROLE =
        keccak256("FULL_RESTRICTED_STAKER_ROLE");

    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event RewardsReceived(uint256 indexed amount);

    function setUp() public virtual {
        lvlUSDToken = new lvlUSD(address(this));

        alice = vm.addr(0xB44DE);
        newOwner = vm.addr(0x1DE);
        greg = vm.addr(0x6ED);
        owner = vm.addr(0xA11CE);
        rewarder = vm.addr(0x1DEA);
        vm.label(alice, "alice");
        vm.label(newOwner, "newOwner");
        vm.label(greg, "greg");
        vm.label(owner, "owner");
        vm.label(rewarder, "rewarder");

        vm.prank(owner);
        stakedlvlUSD = new StakedlvlUSD(
            IERC20(address(lvlUSDToken)),
            rewarder,
            owner
        );

        DEFAULT_ADMIN_ROLE = stakedlvlUSD.DEFAULT_ADMIN_ROLE();

        sigUtilslvlUSD = new SigUtils(lvlUSDToken.DOMAIN_SEPARATOR());
        sigUtilsStakedlvlUSD = new SigUtils(stakedlvlUSD.DOMAIN_SEPARATOR());
    }

    function testCorrectSetup() public {
        assertTrue(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
    }

    function testCancelTransferAdmin() public {
        vm.startPrank(owner);
        stakedlvlUSD.transferAdmin(newOwner);
        stakedlvlUSD.transferAdmin(address(0));
        vm.stopPrank();
        assertTrue(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertFalse(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, address(0)));
        assertFalse(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, newOwner));
    }

    function test_admin_cannot_transfer_self() public {
        vm.startPrank(owner);
        assertTrue(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
        vm.expectRevert(ISingleAdminAccessControl.InvalidAdminChange.selector);
        stakedlvlUSD.transferAdmin(owner);
        vm.stopPrank();
        assertTrue(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
    }

    function testAdminCanCancelTransfer() public {
        vm.startPrank(owner);
        stakedlvlUSD.transferAdmin(newOwner);
        stakedlvlUSD.transferAdmin(address(0));
        vm.stopPrank();

        vm.prank(newOwner);
        vm.expectRevert(ISingleAdminAccessControl.NotPendingAdmin.selector);
        stakedlvlUSD.acceptAdmin();

        assertTrue(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertFalse(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, address(0)));
        assertFalse(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, newOwner));
    }

    function testOwnershipCannotBeRenounced() public {
        vm.startPrank(owner);
        vm.expectRevert(IStakedlvlUSD.OperationNotAllowed.selector);
        stakedlvlUSD.renounceRole(DEFAULT_ADMIN_ROLE, owner);

        vm.expectRevert(ISingleAdminAccessControl.InvalidAdminChange.selector);
        stakedlvlUSD.revokeRole(DEFAULT_ADMIN_ROLE, owner);
        vm.stopPrank();
        assertEq(stakedlvlUSD.owner(), owner);
        assertTrue(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
    }

    function testOwnershipTransferRequiresTwoSteps() public {
        vm.prank(owner);
        stakedlvlUSD.transferAdmin(newOwner);
        assertEq(stakedlvlUSD.owner(), owner);
        assertTrue(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertNotEq(stakedlvlUSD.owner(), newOwner);
        assertFalse(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, newOwner));
    }

    function testCanTransferOwnership() public {
        vm.prank(owner);
        stakedlvlUSD.transferAdmin(newOwner);
        vm.prank(newOwner);
        stakedlvlUSD.acceptAdmin();
        assertTrue(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, newOwner));
        assertFalse(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
    }

    function testNewOwnerCanPerformOwnerActions() public {
        vm.prank(owner);
        stakedlvlUSD.transferAdmin(newOwner);
        vm.startPrank(newOwner);
        stakedlvlUSD.acceptAdmin();
        stakedlvlUSD.grantRole(DENYLIST_MANAGER_ROLE, newOwner);
        stakedlvlUSD.addToDenylist(alice, true);
        vm.stopPrank();
        assertTrue(stakedlvlUSD.hasRole(FULL_RESTRICTED_STAKER_ROLE, alice));
    }

    function testOldOwnerCantPerformOwnerActions() public {
        vm.prank(owner);
        stakedlvlUSD.transferAdmin(newOwner);
        vm.prank(newOwner);
        stakedlvlUSD.acceptAdmin();
        assertTrue(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, newOwner));
        assertFalse(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
        vm.prank(owner);
        vm.expectRevert(
            "AccessControl: account 0xe05fcc23807536bee418f142d19fa0d21bb0cff7 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        stakedlvlUSD.grantRole(DENYLIST_MANAGER_ROLE, alice);
        assertFalse(stakedlvlUSD.hasRole(DENYLIST_MANAGER_ROLE, alice));
    }

    function testOldOwnerCantTransferOwnership() public {
        vm.prank(owner);
        stakedlvlUSD.transferAdmin(newOwner);
        vm.prank(newOwner);
        stakedlvlUSD.acceptAdmin();
        assertTrue(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, newOwner));
        assertFalse(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, owner));
        vm.prank(owner);
        vm.expectRevert(
            "AccessControl: account 0xe05fcc23807536bee418f142d19fa0d21bb0cff7 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        stakedlvlUSD.transferAdmin(alice);
        assertFalse(stakedlvlUSD.hasRole(DEFAULT_ADMIN_ROLE, alice));
    }

    function testNonAdminCantRenounceRoles() public {
        vm.prank(owner);
        stakedlvlUSD.grantRole(DENYLIST_MANAGER_ROLE, alice);
        assertTrue(stakedlvlUSD.hasRole(DENYLIST_MANAGER_ROLE, alice));

        vm.prank(alice);
        vm.expectRevert(IStakedlvlUSD.OperationNotAllowed.selector);
        stakedlvlUSD.renounceRole(DENYLIST_MANAGER_ROLE, alice);
        assertTrue(stakedlvlUSD.hasRole(DENYLIST_MANAGER_ROLE, alice));
    }
}
