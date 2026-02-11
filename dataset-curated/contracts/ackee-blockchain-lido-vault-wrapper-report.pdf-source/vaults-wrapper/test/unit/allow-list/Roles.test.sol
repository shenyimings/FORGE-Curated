// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupAllowList} from "./SetupAllowList.sol";
import {Test} from "forge-std/Test.sol";

contract AllowListRolesTest is Test, SetupAllowList {
    bytes32 ALLOW_LIST_MANAGER_ROLE;
    bytes32 DEFAULT_ADMIN_ROLE;
    bytes32 DEPOSIT_ROLE;

    function setUp() public override {
        super.setUp();

        ALLOW_LIST_MANAGER_ROLE = poolWithAllowList.ALLOW_LIST_MANAGER_ROLE();
        DEFAULT_ADMIN_ROLE = poolWithAllowList.DEFAULT_ADMIN_ROLE();
        DEPOSIT_ROLE = poolWithAllowList.DEPOSIT_ROLE();
    }

    // ALLOW_LIST_MANAGER_ROLE

    function test_AllowListManagerRole_Admin() public view {
        assertEq(poolWithAllowList.getRoleAdmin(ALLOW_LIST_MANAGER_ROLE), DEFAULT_ADMIN_ROLE);
    }

    function test_AllowListManagerRole_OnlyOwnerIsAssigned() public view {
        assertTrue(poolWithAllowList.hasRole(ALLOW_LIST_MANAGER_ROLE, owner));
        assertEq(poolWithAllowList.getRoleMemberCount(ALLOW_LIST_MANAGER_ROLE), 1);

        address[] memory roleMembers = poolWithAllowList.getRoleMembers(ALLOW_LIST_MANAGER_ROLE);
        assertEq(roleMembers.length, 1);
        assertEq(roleMembers[0], owner);
    }

    // DEPOSIT_ROLE

    function test_AllowListDepositRole_Admin() public view {
        assertEq(poolWithAllowList.getRoleAdmin(DEPOSIT_ROLE), ALLOW_LIST_MANAGER_ROLE);
    }

    function test_AllowListDepositRole_OnlyOneMemberIsAssigned() public view {
        assertTrue(poolWithAllowList.hasRole(DEPOSIT_ROLE, userAllowListed));
        assertEq(poolWithAllowList.getRoleMemberCount(DEPOSIT_ROLE), 1);

        address[] memory roleMembers = poolWithAllowList.getRoleMembers(DEPOSIT_ROLE);
        assertEq(roleMembers.length, 1);
        assertEq(roleMembers[0], userAllowListed);
    }
}
