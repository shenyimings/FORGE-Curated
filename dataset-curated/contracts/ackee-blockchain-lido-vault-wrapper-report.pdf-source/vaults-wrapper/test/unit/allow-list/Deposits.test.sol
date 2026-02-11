// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupAllowList} from "./SetupAllowList.sol";
import {Test} from "forge-std/Test.sol";
import {AllowList} from "src/AllowList.sol";

contract AllowListDepositsTest is Test, SetupAllowList {
    // With allow list enabled

    function test_WithAllowList_DepositByAllowListedUser() public {
        vm.prank(userAllowListed);
        poolWithAllowList.depositETH{value: 10 ether}(userAllowListed, address(0));
    }

    function test_WithAllowList_DepositByNotAllowListedUser_Reverts() public {
        vm.prank(userNotAllowListed);
        vm.expectRevert(abi.encodeWithSelector(AllowList.NotAllowListed.selector, userNotAllowListed));
        poolWithAllowList.depositETH{value: 10 ether}(userNotAllowListed, address(0));
    }

    // With allow list disabled

    function test_WithoutAllowList_DepositByAnyUser() public {
        vm.prank(userAny);
        poolWithoutAllowList.depositETH{value: 10 ether}(userAny, address(0));
    }
}
