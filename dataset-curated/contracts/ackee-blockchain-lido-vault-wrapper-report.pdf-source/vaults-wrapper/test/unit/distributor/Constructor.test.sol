// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SetupDistributor} from "./SetupDistributor.sol";
import {Test} from "forge-std/Test.sol";
import {Distributor} from "src/Distributor.sol";

contract ConstructorTest is Test, SetupDistributor {
    function setUp() public override {
        super.setUp();
    }

    function test_Constructor_SetsOwnerAsDefaultAdmin() public view {
        assertTrue(distributor.hasRole(distributor.DEFAULT_ADMIN_ROLE(), owner));
    }

    function test_Constructor_SetsManagerRole() public view {
        assertTrue(distributor.hasRole(distributor.MANAGER_ROLE(), manager));
    }

    function test_Constructor_InitializesLastProcessedBlock() public view {
        assertEq(distributor.lastProcessedBlock(), 0);
    }

    function test_Constructor_InitializesRootToZero() public view {
        assertEq(distributor.root(), bytes32(0));
    }

    function test_Constructor_InitializesCidToEmpty() public view {
        assertEq(distributor.cid(), "");
    }

    function test_Constructor_CanDeployWithDifferentOwner() public {
        address newOwner = makeAddr("newOwner");
        address newManager = makeAddr("newManager");
        Distributor newDistributor = new Distributor(newOwner, newManager);

        assertTrue(newDistributor.hasRole(newDistributor.DEFAULT_ADMIN_ROLE(), newOwner));
        assertTrue(newDistributor.hasRole(newDistributor.MANAGER_ROLE(), newManager));
    }

    function test_Constructor_ManagerRoleConstant() public view {
        bytes32 expectedRole = keccak256("MANAGER_ROLE");
        assertEq(distributor.MANAGER_ROLE(), expectedRole);
    }
}
