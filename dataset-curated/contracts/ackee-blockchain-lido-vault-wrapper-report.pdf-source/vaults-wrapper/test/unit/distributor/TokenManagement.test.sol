// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SetupDistributor} from "./SetupDistributor.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {Distributor} from "src/Distributor.sol";

contract TokenManagementTest is Test, SetupDistributor {
    function setUp() public override {
        super.setUp();
    }

    // ==================== Error Cases ====================

    function test_AddToken_RevertsIfNotManager() public {
        bytes32 managerRole = distributor.MANAGER_ROLE();

        vm.prank(userAlice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, userAlice, managerRole)
        );
        distributor.addToken(address(token1));
    }

    function test_AddToken_RevertsOnZeroAddress() public {
        vm.prank(manager);
        vm.expectRevert(Distributor.ZeroAddress.selector);
        distributor.addToken(address(0));
    }

    function test_AddToken_RevertsOnDuplicateToken() public {
        vm.startPrank(manager);
        distributor.addToken(address(token1));

        vm.expectRevert(abi.encodeWithSelector(Distributor.TokenAlreadyAdded.selector, address(token1)));
        distributor.addToken(address(token1));
        vm.stopPrank();
    }

    // ==================== Successful Token Addition ====================

    function test_AddToken_SuccessfullyAddsToken() public {
        vm.prank(manager);
        distributor.addToken(address(token1));

        address[] memory tokens = distributor.getTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(token1));
    }

    function test_AddToken_EmitsTokenAddedEvent() public {
        vm.expectEmit(true, false, false, false);
        emit TokenAdded(address(token1));

        vm.prank(manager);
        distributor.addToken(address(token1));
    }

    function test_AddToken_CanAddMultipleTokens() public {
        vm.startPrank(manager);
        distributor.addToken(address(token1));
        distributor.addToken(address(token2));
        distributor.addToken(address(token3));
        vm.stopPrank();

        address[] memory tokens = distributor.getTokens();
        assertEq(tokens.length, 3);

        // Check all tokens are in the list
        bool hasToken1 = false;
        bool hasToken2 = false;
        bool hasToken3 = false;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(token1)) hasToken1 = true;
            if (tokens[i] == address(token2)) hasToken2 = true;
            if (tokens[i] == address(token3)) hasToken3 = true;
        }

        assertTrue(hasToken1);
        assertTrue(hasToken2);
        assertTrue(hasToken3);
    }

    function test_AddToken_OwnerCanAddTokenAfterGrant() public {
        vm.startPrank(owner);
        distributor.grantRole(distributor.MANAGER_ROLE(), owner);
        distributor.addToken(address(token1));
        vm.stopPrank();

        address[] memory tokens = distributor.getTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(token1));
    }
}

