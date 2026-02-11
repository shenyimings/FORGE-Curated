// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {MockVaultHub} from "../../mocks/MockVaultHub.sol";
import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";

contract VaultParametersTest is Test, SetupStvStETHPool {
    function test_ReserveRatioBP_ReturnsExpectedValue() public view {
        MockVaultHub vaultHub = dashboard.VAULT_HUB();
        address stakingVault = dashboard.stakingVault();
        uint256 vaultReserveRatioBP = vaultHub.vaultConnection(stakingVault).reserveRatioBP;

        assertEq(pool.poolReserveRatioBP(), vaultReserveRatioBP + RESERVE_RATIO_GAP_BP);
    }

    function test_ForcedRebalanceThresholdBP_ReturnsExpectedValue() public view {
        MockVaultHub vaultHub = dashboard.VAULT_HUB();
        address stakingVault = dashboard.stakingVault();
        uint256 vaultForcedRebalanceThresholdBP = vaultHub.vaultConnection(stakingVault).forcedRebalanceThresholdBP;

        assertEq(pool.poolForcedRebalanceThresholdBP(), vaultForcedRebalanceThresholdBP + RESERVE_RATIO_GAP_BP);
    }

    function test_SyncVaultParameters_UpdatesParameters() public {
        MockVaultHub vaultHub = dashboard.VAULT_HUB();
        address stakingVault = dashboard.stakingVault();
        uint16 baseReserveRatioBP = 1_000;
        uint16 baseForcedThresholdBP = 800;
        vaultHub.mock_setConnectionParameters(stakingVault, baseReserveRatioBP, baseForcedThresholdBP);

        pool.syncVaultParameters();

        assertEq(pool.poolReserveRatioBP(), baseReserveRatioBP + RESERVE_RATIO_GAP_BP);
        assertEq(pool.poolForcedRebalanceThresholdBP(), baseForcedThresholdBP + RESERVE_RATIO_GAP_BP);
    }

    function test_SyncVaultParameters_EmitsEvent() public {
        MockVaultHub vaultHub = dashboard.VAULT_HUB();
        address stakingVault = dashboard.stakingVault();
        uint16 baseReserveRatioBP = 1_000;
        uint16 baseForcedThresholdBP = 800;
        vaultHub.mock_setConnectionParameters(stakingVault, baseReserveRatioBP, baseForcedThresholdBP);

        vm.expectEmit(false, false, false, true);
        emit StvStETHPool.VaultParametersUpdated(
            baseReserveRatioBP + RESERVE_RATIO_GAP_BP, baseForcedThresholdBP + RESERVE_RATIO_GAP_BP
        );
        pool.syncVaultParameters();
    }

    function test_SyncVaultParameters_NoOpWhenParametersUnchanged() public {
        vm.recordLogs();

        pool.syncVaultParameters();

        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_SyncVaultParameters_RevertsWhenReserveRatioTooHigh() public {
        MockVaultHub vaultHub = dashboard.VAULT_HUB();
        address stakingVault = dashboard.stakingVault();
        uint16 baseReserveRatioBP = 9_600;
        uint16 baseForcedThresholdBP = 0;
        vaultHub.mock_setConnectionParameters(stakingVault, baseReserveRatioBP, baseForcedThresholdBP);

        vm.expectRevert(0x01); // assertion failure
        pool.syncVaultParameters();
    }

    function test_SyncVaultParameters_RevertsWhenForcedThresholdTooHigh() public {
        MockVaultHub vaultHub = dashboard.VAULT_HUB();
        address stakingVault = dashboard.stakingVault();
        uint16 baseReserveRatioBP = 4_000;
        uint16 baseForcedThresholdBP = 9_700;
        vaultHub.mock_setConnectionParameters(stakingVault, baseReserveRatioBP, baseForcedThresholdBP);

        vm.expectRevert(0x01); // assertion failure
        pool.syncVaultParameters();
    }
}
