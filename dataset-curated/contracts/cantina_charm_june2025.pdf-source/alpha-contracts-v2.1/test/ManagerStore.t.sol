// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ManagerStore} from "../contracts/ManagerStore.sol";

import {VaultTestUtils} from "./VaultTestUtils.sol";

contract ManagerStoreTest is Test, VaultTestUtils {
    function setUp() public {
        vm.createSelectFork(vm.envString("ALCHEMY_RPC"), 17073835);
        prepareTokens();
        deployManagerStore();
    }

    function test_shouldBeAbleToResetAuthWithRegisteringAgain() public {
        vm.startPrank(other);
        managerStore.registerManager("dummy1");
        // TODO: Rewrite to encoded paramateres
        vm.expectRevert("OwnableUnauthorizedAccount(0x748960E2d176D9033d500D7Aa997cC2c444F57bc)");
        managerStore.authorizeManager(other);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert("Manager not authorized");
        managerStore.deauthorizeManager(other);

        managerStore.authorizeManager(other);
        (,, bool isAuthorized) = managerStore.managersMap(other);
        vm.assertEq(isAuthorized, true, "managerStore.managersMap[other].isAuthorized != true");

        // deauth
        managerStore.deauthorizeManager(other);
        (,, isAuthorized) = managerStore.managersMap(other);
        vm.assertEq(isAuthorized, false, "managerStore.managersMap[other].isAuthorized != false");

        // auth back
        managerStore.authorizeManager(other);
        (,, isAuthorized) = managerStore.managersMap(other);
        vm.assertEq(isAuthorized, true, "managerStore.managersMap[other].isAuthorized != true");
        vm.stopPrank();

        // registering again to reset auth
        vm.startPrank(other);
        managerStore.registerManager("dummy2");
        (,, isAuthorized) = managerStore.managersMap(other);
        vm.assertEq(isAuthorized, false, "(after dummy2) managerStore.managersMap[other].isAuthorized != false");
        vm.stopPrank();
    }
}
