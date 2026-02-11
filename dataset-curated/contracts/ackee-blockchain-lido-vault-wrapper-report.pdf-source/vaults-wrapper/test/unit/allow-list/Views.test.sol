// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupAllowList} from "./SetupAllowList.sol";
import {Test} from "forge-std/Test.sol";

contract AllowListViewsTest is Test, SetupAllowList {
    // ALLOW_LIST_ENABLED

    function test_WithAllowList_allowListEnabled() public view {
        assertTrue(poolWithAllowList.ALLOW_LIST_ENABLED());
    }

    function test_WithoutAllowList_allowListEnabled() public view {
        assertFalse(poolWithoutAllowList.ALLOW_LIST_ENABLED());
    }

    // Roles

    function test_WithAllowList_AllowListManagerRole() public view {
        bytes32 role = poolWithAllowList.ALLOW_LIST_MANAGER_ROLE();
        assertEq(role, keccak256("ALLOW_LIST_MANAGER_ROLE"));
    }

    function test_WithAllowList_DepositRole() public view {
        bytes32 role = poolWithAllowList.DEPOSIT_ROLE();
        assertEq(role, keccak256("DEPOSIT_ROLE"));
    }

    // isAllowListed

    function test_WithAllowList_IsAllowListed() public view {
        assertTrue(poolWithAllowList.isAllowListed(userAllowListed));
        assertFalse(poolWithAllowList.isAllowListed(userNotAllowListed));
    }

    function test_WithoutAllowList_IsAllowListed() public view {
        assertFalse(poolWithoutAllowList.isAllowListed(userAny));
    }

    // getAllowListSize

    function test_WithAllowList_GetAllowListSize() public view {
        assertEq(poolWithAllowList.getAllowListSize(), 1);
    }

    function test_WithAllowList_GetAllowListSize_AfterAdding() public {
        assertEq(poolWithAllowList.getAllowListSize(), 1);

        vm.prank(owner);
        poolWithAllowList.addToAllowList(userNotAllowListed);
        assertEq(poolWithAllowList.getAllowListSize(), 2);
    }

    function test_WithoutAllowList_GetAllowListSize() public view {
        assertEq(poolWithoutAllowList.getAllowListSize(), 0);
    }

    // getAllowListAddresses

    function test_WithAllowList_GetAllowListAddresses() public view {
        address[] memory allowList = poolWithAllowList.getAllowListAddresses();
        assertEq(allowList.length, 1);
        assertEq(allowList[0], userAllowListed);
    }

    function test_WithoutAllowList_GetAllowListAddresses() public view {
        address[] memory allowList = poolWithoutAllowList.getAllowListAddresses();
        assertEq(allowList.length, 0);
    }
}
