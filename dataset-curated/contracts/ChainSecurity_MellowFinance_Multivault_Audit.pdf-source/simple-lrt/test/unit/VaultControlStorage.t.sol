// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../Imports.sol";
import "../mocks/MockVaultControlStorage.sol";

contract Unit is Test {
    function testConstructor() external {
        {
            MockVaultControlStorage c = new MockVaultControlStorage("name", 1);
            assertEq(c.depositPause(), false);
            assertEq(c.withdrawalPause(), false);
            assertEq(c.limit(), 0);
            assertEq(c.depositWhitelist(), false);
            assertNotEq(address(c), address(0));
        }
        // zero params
        {
            // no revert
            MockVaultControlStorage c = new MockVaultControlStorage(0, 0);
            assertEq(c.depositPause(), false);
            assertEq(c.withdrawalPause(), false);
            assertEq(c.limit(), 0);
            assertEq(c.depositWhitelist(), false);
            assertNotEq(address(c), address(0));
        }
    }

    function testInitializeVaultControlStorage() external {
        // 1. reverts on consecutive calls
        {
            MockVaultControlStorage c = new MockVaultControlStorage("name", 1);
            c.initializeVaultControlStorage(1, false, false, false);
            vm.expectRevert();
            c.initializeVaultControlStorage(1, false, false, false);
        }

        // zero params
        {
            MockVaultControlStorage c = new MockVaultControlStorage("name", 1);
            c.initializeVaultControlStorage(0, false, false, false);
            assertEq(c.limit(), 0);
            assertEq(c.depositPause(), false);
            assertEq(c.withdrawalPause(), false);
            assertEq(c.depositWhitelist(), false);
        }

        // non-zero params
        {
            MockVaultControlStorage c = new MockVaultControlStorage("name", 1);
            c.initializeVaultControlStorage(1, true, true, true);
            assertEq(c.limit(), 1);
            assertEq(c.depositPause(), true);
            assertEq(c.withdrawalPause(), true);
            assertEq(c.depositWhitelist(), true);
        }

        // events
        {
            MockVaultControlStorage c = new MockVaultControlStorage("name", 1);
            vm.recordLogs();
            c.initializeVaultControlStorage(1, true, true, true);
            Vm.Log[] memory logs = vm.getRecordedLogs();

            assertEq(logs.length, 5);

            assertEq(logs[0].emitter, address(c));
            assertEq(logs[0].topics[0], keccak256("LimitSet(uint256,uint256,address)"));

            assertEq(logs[1].emitter, address(c));
            assertEq(logs[1].topics[0], keccak256("DepositPauseSet(bool,uint256,address)"));

            assertEq(logs[2].emitter, address(c));
            assertEq(logs[2].topics[0], keccak256("WithdrawalPauseSet(bool,uint256,address)"));

            assertEq(logs[3].emitter, address(c));
            assertEq(logs[3].topics[0], keccak256("DepositWhitelistSet(bool,uint256,address)"));

            assertEq(logs[4].emitter, address(c));
            assertEq(logs[4].topics[0], keccak256("Initialized(uint64)"));
        }
    }

    function testSetDepositWhitelist() external {
        MockVaultControlStorage c = new MockVaultControlStorage("name", 1);
        assertEq(c.depositWhitelist(), false);
        vm.recordLogs();
        c.setDepositWhitelist(true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("DepositWhitelistSet(bool,uint256,address)"));
        assertEq(c.depositWhitelist(), true);
        vm.recordLogs();
        c.setDepositWhitelist(false);
        logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("DepositWhitelistSet(bool,uint256,address)"));
        assertEq(c.depositWhitelist(), false);
    }

    function testSetLimit() external {
        MockVaultControlStorage c = new MockVaultControlStorage("name", 1);
        assertEq(c.limit(), 0);
        vm.recordLogs();
        c.setLimit(1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("LimitSet(uint256,uint256,address)"));
        assertEq(c.limit(), 1);
        vm.recordLogs();
        c.setLimit(0);
        logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("LimitSet(uint256,uint256,address)"));
        assertEq(c.limit(), 0);
    }

    function testSetDepositPause() external {
        MockVaultControlStorage c = new MockVaultControlStorage("name", 1);
        assertEq(c.depositPause(), false);
        vm.recordLogs();
        c.setDepositPause(true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("DepositPauseSet(bool,uint256,address)"));
        assertEq(c.depositPause(), true);
        vm.recordLogs();
        c.setDepositPause(false);
        logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("DepositPauseSet(bool,uint256,address)"));
        assertEq(c.depositPause(), false);
    }

    function testSetWithdrawalPause() external {
        MockVaultControlStorage c = new MockVaultControlStorage("name", 1);
        assertEq(c.withdrawalPause(), false);
        vm.recordLogs();
        c.setWithdrawalPause(true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("WithdrawalPauseSet(bool,uint256,address)"));
        assertEq(c.withdrawalPause(), true);
        vm.recordLogs();
        c.setWithdrawalPause(false);
        logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(logs[0].topics[0], keccak256("WithdrawalPauseSet(bool,uint256,address)"));
        assertEq(c.withdrawalPause(), false);
    }

    function testSetDepositorWhitelistStatus() external {
        MockVaultControlStorage c = new MockVaultControlStorage("name", 1);
        assertEq(c.isDepositorWhitelisted(address(this)), false);
        vm.recordLogs();
        c.setDepositorWhitelistStatus(address(this), true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(
            logs[0].topics[0],
            keccak256("DepositorWhitelistStatusSet(address,bool,uint256,address)")
        );
        assertEq(c.isDepositorWhitelisted(address(this)), true);
        vm.recordLogs();
        c.setDepositorWhitelistStatus(address(this), false);
        logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(c));
        assertEq(
            logs[0].topics[0],
            keccak256("DepositorWhitelistStatusSet(address,bool,uint256,address)")
        );
        assertEq(c.isDepositorWhitelisted(address(this)), false);
    }
}
