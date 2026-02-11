// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {Test} from "forge-std/Test.sol";

contract SyncVaultParametersTest is Test, SetupStvStETHPool {
    address public randomUser;

    function setUp() public override {
        super.setUp();
        randomUser = makeAddr("randomUser");
    }

    function test_SyncVaultParameters_Permissionless() public {
        vm.prank(randomUser);
        pool.syncVaultParameters();
    }

    function test_SyncVaultParameters_AddsGapToReserveRatio() public {
        address stakingVault = dashboard.stakingVault();
        uint16 baseReserveRatioBP = 2000;
        uint16 baseForcedThresholdBP = 1500;
        vaultHub.mock_setConnectionParameters(stakingVault, baseReserveRatioBP, baseForcedThresholdBP);

        pool.syncVaultParameters();

        assertEq(pool.poolReserveRatioBP(), baseReserveRatioBP + RESERVE_RATIO_GAP_BP);
    }

    function test_SyncVaultParameters_AddsGapToThreshold() public {
        address stakingVault = dashboard.stakingVault();
        uint16 baseReserveRatioBP = 2000;
        uint16 baseForcedThresholdBP = 1500;
        vaultHub.mock_setConnectionParameters(stakingVault, baseReserveRatioBP, baseForcedThresholdBP);

        pool.syncVaultParameters();

        assertEq(pool.poolForcedRebalanceThresholdBP(), baseForcedThresholdBP + RESERVE_RATIO_GAP_BP);
    }

    function test_SyncVaultParameters_CapsAtMaximum() public {
        address stakingVault = dashboard.stakingVault();
        uint16 baseReserveRatioBP = 9900;
        uint16 baseForcedThresholdBP = 9800;
        vaultHub.mock_setConnectionParameters(stakingVault, baseReserveRatioBP, baseForcedThresholdBP);

        pool.syncVaultParameters();

        assertEq(pool.poolReserveRatioBP(), 9999);
        assertEq(pool.poolForcedRebalanceThresholdBP(), 9998);
    }

    function test_SyncVaultParameters_AfterVaultUpdate_Syncs() public {
        address stakingVault = dashboard.stakingVault();
        uint16 initialReserveRatioBP = 2000;
        uint16 initialForcedThresholdBP = 1500;
        vaultHub.mock_setConnectionParameters(stakingVault, initialReserveRatioBP, initialForcedThresholdBP);
        pool.syncVaultParameters();

        uint16 newReserveRatioBP = 3000;
        uint16 newForcedThresholdBP = 2500;
        vaultHub.mock_setConnectionParameters(stakingVault, newReserveRatioBP, newForcedThresholdBP);

        pool.syncVaultParameters();

        assertEq(pool.poolReserveRatioBP(), newReserveRatioBP + RESERVE_RATIO_GAP_BP);
        assertEq(pool.poolForcedRebalanceThresholdBP(), newForcedThresholdBP + RESERVE_RATIO_GAP_BP);
    }

    function test_SyncVaultParameters_AffectsMintingCapacity() public {
        vm.prank(userAlice);
        pool.depositETH{value: 10 ether}(userAlice, address(0));

        uint256 capacityBefore = pool.remainingMintingCapacitySharesOf(userAlice, 0);

        address stakingVault = dashboard.stakingVault();
        uint16 lowerReserveRatioBP = 500;
        uint16 lowerForcedThresholdBP = 400;
        vaultHub.mock_setConnectionParameters(stakingVault, lowerReserveRatioBP, lowerForcedThresholdBP);

        pool.syncVaultParameters();

        uint256 capacityAfter = pool.remainingMintingCapacitySharesOf(userAlice, 0);

        assertGt(capacityAfter, capacityBefore);
    }
}
