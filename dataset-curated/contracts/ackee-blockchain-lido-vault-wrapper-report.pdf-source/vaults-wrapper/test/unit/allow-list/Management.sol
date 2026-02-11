// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupAllowList} from "./SetupAllowList.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {AllowList} from "src/AllowList.sol";

contract AllowListManagementTest is Test, SetupAllowList {
    function test_WithAllowList_UserIsAllowListed() public view {
        assertTrue(poolWithAllowList.isAllowListed(userAllowListed));
    }

    function test_WithAllowList_UserIsNotAllowListed() public view {
        assertFalse(poolWithAllowList.isAllowListed(userNotAllowListed));
    }

    function test_WithoutAllowList_NotAllowListed() public view {
        assertFalse(poolWithoutAllowList.isAllowListed(userAny));
    }

    // Owner list management

    function test_AllowListManagement_AddToListByOwner() public {
        vm.prank(owner);
        poolWithAllowList.addToAllowList(userNotAllowListed);
    }

    function test_AllowListManagement_RemoveFromListByOwner() public {
        vm.prank(owner);
        poolWithAllowList.removeFromAllowList(userAllowListed);
    }

    // Unauthorized list management

    function test_AllowListManagement_AddToListByNonOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                userAny,
                poolWithAllowList.ALLOW_LIST_MANAGER_ROLE()
            )
        );
        vm.prank(userAny);
        poolWithAllowList.addToAllowList(userNotAllowListed);
    }

    function test_AllowListManagement_RemoveFromListByNonOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                userAny,
                poolWithAllowList.ALLOW_LIST_MANAGER_ROLE()
            )
        );
        vm.prank(userAny);
        poolWithAllowList.removeFromAllowList(userAllowListed);
    }

    // Events

    function test_AllowListManagement_AddToList_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit AllowList.AllowListAdded(userNotAllowListed);

        vm.prank(owner);
        poolWithAllowList.addToAllowList(userNotAllowListed);
    }

    function test_AllowListManagement_RemoveFromList_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit AllowList.AllowListRemoved(userAllowListed);

        vm.prank(owner);
        poolWithAllowList.removeFromAllowList(userAllowListed);
    }
}
