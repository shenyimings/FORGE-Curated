// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {
    IAccessControl
} from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Upgrades, UnsafeUpgrades } from "../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IBlacklistable } from "../../../src/components/IBlacklistable.sol";

import { BlacklistableHarness } from "../../harness/BlacklistableHarness.sol";

import { BaseUnitTest } from "../../utils/BaseUnitTest.sol";

contract BlacklistableUnitTests is BaseUnitTest {
    // Roles
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");

    BlacklistableHarness public blacklistable;

    function setUp() public override {
        super.setUp();

        blacklistable = BlacklistableHarness(
            Upgrades.deployUUPSProxy(
                "BlacklistableHarness.sol:BlacklistableHarness",
                abi.encodeWithSelector(BlacklistableHarness.initialize.selector, blacklistManager)
            )
        );
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertTrue(IAccessControl(address(blacklistable)).hasRole(BLACKLIST_MANAGER_ROLE, blacklistManager));
    }

    function test_initialize_zeroBlacklistManager() external {
        address implementation = address(new BlacklistableHarness());

        vm.expectRevert(IBlacklistable.ZeroBlacklistManager.selector);
        UnsafeUpgrades.deployUUPSProxy(
            implementation,
            abi.encodeWithSelector(BlacklistableHarness.initialize.selector, address(0))
        );
    }

    /* ============ blacklist ============ */

    function test_blacklist_onlyBlacklistManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                BLACKLIST_MANAGER_ROLE
            )
        );

        vm.prank(alice);
        blacklistable.blacklist(bob);
    }

    function test_blacklist_revertIfBlacklisted() public {
        vm.prank(blacklistManager);
        blacklistable.blacklist(alice);

        vm.expectRevert(abi.encodeWithSelector(IBlacklistable.AccountBlacklisted.selector, alice));

        vm.prank(blacklistManager);
        blacklistable.blacklist(alice);
    }

    function test_blacklist() public {
        vm.expectEmit();
        emit IBlacklistable.Blacklisted(alice, block.timestamp);

        vm.prank(blacklistManager);
        blacklistable.blacklist(alice);

        assertTrue(blacklistable.isBlacklisted(alice));
    }

    /* ============ blacklistAccounts ============ */

    function test_blacklistAccounts_onlyBlacklistManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                BLACKLIST_MANAGER_ROLE
            )
        );

        vm.prank(alice);
        blacklistable.blacklistAccounts(accounts);
    }

    function test_blacklistAccounts_revertIfBlacklisted() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = alice;

        vm.expectRevert(abi.encodeWithSelector(IBlacklistable.AccountBlacklisted.selector, alice));

        vm.prank(blacklistManager);
        blacklistable.blacklistAccounts(accounts);
    }

    function test_blacklistAccounts() public {
        for (uint256 i; i < accounts.length; ++i) {
            vm.expectEmit();
            emit IBlacklistable.Blacklisted(accounts[i], block.timestamp);
        }

        vm.prank(blacklistManager);
        blacklistable.blacklistAccounts(accounts);

        for (uint256 i; i < accounts.length; ++i) {
            assertTrue(blacklistable.isBlacklisted(accounts[i]));
        }
    }

    /* ============ unblacklist ============ */

    function test_unblacklist_onlyBlacklistManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                BLACKLIST_MANAGER_ROLE
            )
        );

        vm.prank(alice);
        blacklistable.unblacklist(bob);
    }

    function test_blacklist_revertIfNotBlacklisted() public {
        vm.expectRevert(abi.encodeWithSelector(IBlacklistable.AccountNotBlacklisted.selector, alice));

        vm.prank(blacklistManager);
        blacklistable.unblacklist(alice);
    }

    function test_unblacklist() public {
        vm.prank(blacklistManager);
        blacklistable.blacklist(alice);

        assertTrue(blacklistable.isBlacklisted(alice));

        vm.expectEmit();
        emit IBlacklistable.Unblacklisted(alice, block.timestamp);

        vm.prank(blacklistManager);
        blacklistable.unblacklist(alice);

        assertFalse(blacklistable.isBlacklisted(alice));
    }

    /* ============ unblacklistAccounts ============ */

    function test_unblacklistAccounts_onlyBlacklistManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                BLACKLIST_MANAGER_ROLE
            )
        );

        vm.prank(alice);
        blacklistable.unblacklistAccounts(accounts);
    }

    function test_unblacklistAccounts_revertIfNotBlacklisted() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        vm.expectRevert(abi.encodeWithSelector(IBlacklistable.AccountNotBlacklisted.selector, alice));

        vm.prank(blacklistManager);
        blacklistable.unblacklistAccounts(accounts);
    }

    function test_unblacklistAccounts() public {
        vm.prank(blacklistManager);
        blacklistable.blacklistAccounts(accounts);

        for (uint256 i; i < accounts.length; ++i) {
            vm.expectEmit();
            emit IBlacklistable.Unblacklisted(accounts[i], block.timestamp);
        }

        vm.prank(blacklistManager);
        blacklistable.unblacklistAccounts(accounts);

        for (uint256 i; i < accounts.length; ++i) {
            assertFalse(blacklistable.isBlacklisted(accounts[i]));
        }
    }
}
