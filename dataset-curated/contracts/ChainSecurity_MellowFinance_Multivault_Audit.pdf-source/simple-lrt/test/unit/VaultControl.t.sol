// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../Imports.sol";
import "../mocks/MockVaultControl.sol";

contract Unit is Test {
    address admin = makeAddr("admin");
    uint256 limit = 1 ether;

    bytes32 private constant SET_LIMIT_ROLE = keccak256("SET_LIMIT_ROLE");
    bytes32 private constant PAUSE_WITHDRAWALS_ROLE = keccak256("PAUSE_WITHDRAWALS_ROLE");
    bytes32 private constant UNPAUSE_WITHDRAWALS_ROLE = keccak256("UNPAUSE_WITHDRAWALS_ROLE");
    bytes32 private constant PAUSE_DEPOSITS_ROLE = keccak256("PAUSE_DEPOSITS_ROLE");
    bytes32 private constant UNPAUSE_DEPOSITS_ROLE = keccak256("UNPAUSE_DEPOSITS_ROLE");
    bytes32 private constant SET_DEPOSIT_WHITELIST_ROLE = keccak256("SET_DEPOSIT_WHITELIST_ROLE");
    bytes32 private constant SET_DEPOSITOR_WHITELIST_STATUS_ROLE =
        keccak256("SET_DEPOSITOR_WHITELIST_STATUS_ROLE");

    bytes32 constant DEFAULT_ADMIN_ROLE = bytes32(0);

    function testConstructor() external {
        MockVaultControl c = new MockVaultControl(keccak256("mock"), 1);
        assertNotEq(address(c), address(0));
    }

    function testInitialize() external {
        {
            MockVaultControl c = new MockVaultControl(keccak256("mock"), 1);
            vm.recordLogs();
            c.initializeVaultControl(admin, limit, false, false, false);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(logs.length, 6);
            bytes32[6] memory topics = [
                keccak256("RoleGranted(bytes32,address,address)"),
                keccak256("LimitSet(uint256,uint256,address)"),
                keccak256("DepositPauseSet(bool,uint256,address)"),
                keccak256("WithdrawalPauseSet(bool,uint256,address)"),
                keccak256("DepositWhitelistSet(bool,uint256,address)"),
                keccak256("Initialized(uint64)")
            ];
            for (uint256 i = 0; i < 6; i++) {
                assertEq(logs[i].emitter, address(c));
                assertEq(logs[i].topics[0], topics[i]);
            }
            assertEq(c.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
            assertTrue(c.hasRole(DEFAULT_ADMIN_ROLE, admin));
            assertEq(c.getRoleMemberCount(SET_LIMIT_ROLE), 0);
            assertEq(c.getRoleMemberCount(PAUSE_WITHDRAWALS_ROLE), 0);
            assertEq(c.getRoleMemberCount(UNPAUSE_WITHDRAWALS_ROLE), 0);
            assertEq(c.getRoleMemberCount(PAUSE_DEPOSITS_ROLE), 0);
            assertEq(c.getRoleMemberCount(UNPAUSE_DEPOSITS_ROLE), 0);
            assertEq(c.getRoleMemberCount(SET_DEPOSIT_WHITELIST_ROLE), 0);
            assertEq(c.getRoleMemberCount(SET_DEPOSITOR_WHITELIST_STATUS_ROLE), 0);
            assertEq(c.limit(), limit);
            assertEq(c.depositPause(), false);
            assertEq(c.withdrawalPause(), false);
            assertEq(c.depositWhitelist(), false);
        }

        {
            MockVaultControl c = new MockVaultControl(keccak256("mock"), 1);
            vm.recordLogs();
            c.initializeVaultControl(admin, limit * 2, true, true, true);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(logs.length, 6);
            bytes32[6] memory topics = [
                keccak256("RoleGranted(bytes32,address,address)"),
                keccak256("LimitSet(uint256,uint256,address)"),
                keccak256("DepositPauseSet(bool,uint256,address)"),
                keccak256("WithdrawalPauseSet(bool,uint256,address)"),
                keccak256("DepositWhitelistSet(bool,uint256,address)"),
                keccak256("Initialized(uint64)")
            ];
            for (uint256 i = 0; i < 6; i++) {
                assertEq(logs[i].emitter, address(c));
                assertEq(logs[i].topics[0], topics[i]);
            }
            assertEq(c.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
            assertTrue(c.hasRole(DEFAULT_ADMIN_ROLE, admin));
            assertEq(c.getRoleMemberCount(SET_LIMIT_ROLE), 0);
            assertEq(c.getRoleMemberCount(PAUSE_WITHDRAWALS_ROLE), 0);
            assertEq(c.getRoleMemberCount(UNPAUSE_WITHDRAWALS_ROLE), 0);
            assertEq(c.getRoleMemberCount(PAUSE_DEPOSITS_ROLE), 0);
            assertEq(c.getRoleMemberCount(UNPAUSE_DEPOSITS_ROLE), 0);
            assertEq(c.getRoleMemberCount(SET_DEPOSIT_WHITELIST_ROLE), 0);
            assertEq(c.getRoleMemberCount(SET_DEPOSITOR_WHITELIST_STATUS_ROLE), 0);
            assertEq(c.limit(), limit * 2);
            assertEq(c.depositPause(), true);
            assertEq(c.withdrawalPause(), true);
            assertEq(c.depositWhitelist(), true);
        }
    }

    function testSetLimit() external {
        MockVaultControl c = new MockVaultControl(keccak256("mock"), 1);
        c.initializeVaultControl(admin, limit, false, false, false);

        assertEq(c.limit(), limit);

        vm.expectRevert();
        c.setLimit(limit * 2);
        assertEq(c.limit(), limit);

        vm.expectRevert();
        c.setLimit(limit * 2);
        assertEq(c.limit(), limit);

        vm.prank(admin);
        c.grantRole(SET_LIMIT_ROLE, admin);

        vm.recordLogs();
        vm.prank(admin);
        c.setLimit(limit * 2);
        assertEq(c.limit(), limit * 2);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("LimitSet(uint256,uint256,address)"));
    }

    function testPauseWithdrawals() external {
        MockVaultControl c = new MockVaultControl(keccak256("mock"), 1);
        c.initializeVaultControl(admin, limit, false, false, false);

        assertEq(c.withdrawalPause(), false);

        vm.expectRevert();
        c.pauseWithdrawals();
        assertEq(c.withdrawalPause(), false);

        vm.prank(admin);
        c.grantRole(PAUSE_WITHDRAWALS_ROLE, admin);

        vm.recordLogs();
        vm.prank(admin);
        c.pauseWithdrawals();
        assertEq(c.withdrawalPause(), true);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("WithdrawalPauseSet(bool,uint256,address)"));
        assertEq(logs[1].emitter, address(c));
        assertEq(logs[1].topics[0], keccak256("RoleRevoked(bytes32,address,address)"));
    }

    function testUnpauseWithdrawals() external {
        MockVaultControl c = new MockVaultControl(keccak256("mock"), 1);
        c.initializeVaultControl(admin, limit, false, false, false);

        vm.prank(admin);
        c.grantRole(PAUSE_WITHDRAWALS_ROLE, admin);

        vm.prank(admin);
        c.pauseWithdrawals();
        assertEq(c.withdrawalPause(), true);

        vm.expectRevert();
        c.unpauseWithdrawals();
        assertEq(c.withdrawalPause(), true);

        vm.prank(admin);
        c.grantRole(UNPAUSE_WITHDRAWALS_ROLE, admin);

        vm.recordLogs();
        vm.prank(admin);
        c.unpauseWithdrawals();
        assertEq(c.withdrawalPause(), false);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("WithdrawalPauseSet(bool,uint256,address)"));
    }

    function testPauseDeposits() external {
        MockVaultControl c = new MockVaultControl(keccak256("mock"), 1);
        c.initializeVaultControl(admin, limit, false, false, false);

        assertEq(c.depositPause(), false);

        vm.expectRevert();
        c.pauseDeposits();
        assertEq(c.depositPause(), false);

        vm.prank(admin);
        c.grantRole(PAUSE_DEPOSITS_ROLE, admin);

        vm.recordLogs();
        vm.prank(admin);
        c.pauseDeposits();
        assertEq(c.depositPause(), true);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("DepositPauseSet(bool,uint256,address)"));
        assertEq(logs[1].emitter, address(c));
        assertEq(logs[1].topics[0], keccak256("RoleRevoked(bytes32,address,address)"));
    }

    function testUnpauseDeposits() external {
        MockVaultControl c = new MockVaultControl(keccak256("mock"), 1);
        c.initializeVaultControl(admin, limit, false, false, false);

        vm.prank(admin);
        c.grantRole(PAUSE_DEPOSITS_ROLE, admin);

        vm.prank(admin);
        c.pauseDeposits();
        assertEq(c.depositPause(), true);

        vm.expectRevert();
        c.unpauseDeposits();
        assertEq(c.depositPause(), true);

        vm.prank(admin);
        c.grantRole(UNPAUSE_DEPOSITS_ROLE, admin);

        vm.recordLogs();
        vm.prank(admin);
        c.unpauseDeposits();
        assertEq(c.depositPause(), false);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("DepositPauseSet(bool,uint256,address)"));
    }

    function testSetDepositWhitelist() external {
        MockVaultControl c = new MockVaultControl(keccak256("mock"), 1);
        c.initializeVaultControl(admin, limit, false, false, false);

        assertEq(c.depositWhitelist(), false);

        vm.expectRevert();
        c.setDepositWhitelist(true);
        assertEq(c.depositWhitelist(), false);

        vm.prank(admin);
        c.grantRole(SET_DEPOSIT_WHITELIST_ROLE, admin);

        vm.recordLogs();
        vm.prank(admin);
        c.setDepositWhitelist(true);
        assertEq(c.depositWhitelist(), true);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("DepositWhitelistSet(bool,uint256,address)"));
    }

    function testSetDepositorWhitelistStatus() external {
        MockVaultControl c = new MockVaultControl(keccak256("mock"), 1);
        c.initializeVaultControl(admin, limit, false, false, false);

        address account = makeAddr("account");

        vm.expectRevert();
        c.setDepositorWhitelistStatus(account, true);

        vm.prank(admin);
        c.grantRole(SET_DEPOSITOR_WHITELIST_STATUS_ROLE, admin);

        vm.recordLogs();
        vm.prank(admin);
        c.setDepositorWhitelistStatus(account, true);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(
            logs[0].topics[0],
            keccak256("DepositorWhitelistStatusSet(address,bool,uint256,address)")
        );
    }

    function testRole() external {
        MockVaultControl c = new MockVaultControl(keccak256("mock"), 1);
        c.initializeVaultControl(admin, limit, false, false, false);

        assertEq(c.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertTrue(c.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertEq(c.getRoleMemberCount(SET_LIMIT_ROLE), 0);
        assertEq(c.getRoleMemberCount(PAUSE_WITHDRAWALS_ROLE), 0);
        assertEq(c.getRoleMemberCount(UNPAUSE_WITHDRAWALS_ROLE), 0);
        assertEq(c.getRoleMemberCount(PAUSE_DEPOSITS_ROLE), 0);
        assertEq(c.getRoleMemberCount(UNPAUSE_DEPOSITS_ROLE), 0);
        assertEq(c.getRoleMemberCount(SET_DEPOSIT_WHITELIST_ROLE), 0);
        assertEq(c.getRoleMemberCount(SET_DEPOSITOR_WHITELIST_STATUS_ROLE), 0);

        vm.expectRevert();
        c.grantRole(SET_LIMIT_ROLE, admin);
        vm.expectRevert();
        c.grantRole(PAUSE_WITHDRAWALS_ROLE, admin);
        vm.expectRevert();
        c.grantRole(UNPAUSE_WITHDRAWALS_ROLE, admin);
        vm.expectRevert();
        c.grantRole(PAUSE_DEPOSITS_ROLE, admin);
        vm.expectRevert();
        c.grantRole(UNPAUSE_DEPOSITS_ROLE, admin);
        vm.expectRevert();
        c.grantRole(SET_DEPOSIT_WHITELIST_ROLE, admin);
        vm.expectRevert();
        c.grantRole(SET_DEPOSITOR_WHITELIST_STATUS_ROLE, admin);

        vm.prank(admin);
        c.grantRole(SET_LIMIT_ROLE, admin);
        assertEq(c.getRoleMemberCount(SET_LIMIT_ROLE), 1);
        assertTrue(c.hasRole(SET_LIMIT_ROLE, admin));

        vm.prank(admin);
        c.revokeRole(SET_LIMIT_ROLE, admin);
        assertEq(c.getRoleMemberCount(SET_LIMIT_ROLE), 0);
        assertFalse(c.hasRole(SET_LIMIT_ROLE, admin));

        vm.prank(admin);
        c.grantRole(PAUSE_WITHDRAWALS_ROLE, admin);
        assertEq(c.getRoleMemberCount(PAUSE_WITHDRAWALS_ROLE), 1);
        assertTrue(c.hasRole(PAUSE_WITHDRAWALS_ROLE, admin));

        vm.prank(admin);
        c.revokeRole(PAUSE_WITHDRAWALS_ROLE, admin);
        assertEq(c.getRoleMemberCount(PAUSE_WITHDRAWALS_ROLE), 0);
        assertFalse(c.hasRole(PAUSE_WITHDRAWALS_ROLE, admin));

        vm.prank(admin);
        c.grantRole(UNPAUSE_WITHDRAWALS_ROLE, admin);
        assertEq(c.getRoleMemberCount(UNPAUSE_WITHDRAWALS_ROLE), 1);
        assertTrue(c.hasRole(UNPAUSE_WITHDRAWALS_ROLE, admin));

        vm.prank(admin);
        c.revokeRole(UNPAUSE_WITHDRAWALS_ROLE, admin);
        assertEq(c.getRoleMemberCount(UNPAUSE_WITHDRAWALS_ROLE), 0);
        assertFalse(c.hasRole(UNPAUSE_WITHDRAWALS_ROLE, admin));

        vm.prank(admin);
        c.grantRole(PAUSE_DEPOSITS_ROLE, admin);
        assertEq(c.getRoleMemberCount(PAUSE_DEPOSITS_ROLE), 1);
        assertTrue(c.hasRole(PAUSE_DEPOSITS_ROLE, admin));

        vm.prank(admin);
        c.revokeRole(PAUSE_DEPOSITS_ROLE, admin);
        assertEq(c.getRoleMemberCount(PAUSE_DEPOSITS_ROLE), 0);
        assertFalse(c.hasRole(PAUSE_DEPOSITS_ROLE, admin));

        vm.prank(admin);
        c.grantRole(UNPAUSE_DEPOSITS_ROLE, admin);
        assertEq(c.getRoleMemberCount(UNPAUSE_DEPOSITS_ROLE), 1);
        assertTrue(c.hasRole(UNPAUSE_DEPOSITS_ROLE, admin));

        vm.prank(admin);
        c.revokeRole(UNPAUSE_DEPOSITS_ROLE, admin);
        assertEq(c.getRoleMemberCount(UNPAUSE_DEPOSITS_ROLE), 0);
        assertFalse(c.hasRole(UNPAUSE_DEPOSITS_ROLE, admin));

        vm.prank(admin);
        c.grantRole(SET_DEPOSIT_WHITELIST_ROLE, admin);
        assertEq(c.getRoleMemberCount(SET_DEPOSIT_WHITELIST_ROLE), 1);
        assertTrue(c.hasRole(SET_DEPOSIT_WHITELIST_ROLE, admin));

        vm.prank(admin);
        c.revokeRole(SET_DEPOSIT_WHITELIST_ROLE, admin);
        assertEq(c.getRoleMemberCount(SET_DEPOSIT_WHITELIST_ROLE), 0);
        assertFalse(c.hasRole(SET_DEPOSIT_WHITELIST_ROLE, admin));

        vm.prank(admin);
        c.grantRole(SET_DEPOSITOR_WHITELIST_STATUS_ROLE, admin);
        assertEq(c.getRoleMemberCount(SET_DEPOSITOR_WHITELIST_STATUS_ROLE), 1);
        assertTrue(c.hasRole(SET_DEPOSITOR_WHITELIST_STATUS_ROLE, admin));

        vm.prank(admin);
        c.revokeRole(SET_DEPOSITOR_WHITELIST_STATUS_ROLE, admin);
        assertEq(c.getRoleMemberCount(SET_DEPOSITOR_WHITELIST_STATUS_ROLE), 0);
        assertFalse(c.hasRole(SET_DEPOSITOR_WHITELIST_STATUS_ROLE, admin));

        vm.expectRevert();
        c.revokeRole(DEFAULT_ADMIN_ROLE, admin);

        vm.expectRevert();
        c.revokeRole(SET_LIMIT_ROLE, admin);

        vm.expectRevert();
        c.revokeRole(PAUSE_WITHDRAWALS_ROLE, admin);

        vm.expectRevert();
        c.revokeRole(UNPAUSE_WITHDRAWALS_ROLE, admin);

        vm.expectRevert();
        c.revokeRole(PAUSE_DEPOSITS_ROLE, admin);

        vm.expectRevert();
        c.revokeRole(UNPAUSE_DEPOSITS_ROLE, admin);

        vm.expectRevert();
        c.revokeRole(SET_DEPOSIT_WHITELIST_ROLE, admin);

        vm.expectRevert();
        c.revokeRole(SET_DEPOSITOR_WHITELIST_STATUS_ROLE, admin);
    }
}
