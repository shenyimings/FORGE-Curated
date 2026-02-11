// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupWithdrawalQueue} from "./SetupWithdrawalQueue.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {FeaturePausable} from "src/utils/FeaturePausable.sol";

contract FinalizationTest is Test, SetupWithdrawalQueue {
    function setUp() public override {
        super.setUp();
        pool.depositETH{value: 10_000 ether}(address(this), address(0));
    }

    // Basic Finalization

    function test_Finalize_SimpleRequestAndFinalization() public {
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        // Verify request was created
        assertEq(requestId, 1);
        assertEq(withdrawalQueue.getLastRequestId(), 1);
        assertEq(withdrawalQueue.getLastFinalizedRequestId(), 0);

        // Check request status - should not be finalized yet
        WithdrawalQueue.WithdrawalRequestStatus memory status = withdrawalQueue.getWithdrawalStatus(requestId);
        assertFalse(status.isFinalized);
        assertEq(status.owner, address(this));

        // Move time forward to pass minimum delay
        _warpAndMockOracleReport();

        // Finalize the request
        vm.prank(finalizeRoleHolder);
        uint256 finalizedCount = withdrawalQueue.finalize(1, address(0));

        // Verify finalization succeeded
        assertEq(finalizedCount, 1);
        assertEq(withdrawalQueue.getLastFinalizedRequestId(), requestId);

        // Check request status is now finalized
        status = withdrawalQueue.getWithdrawalStatus(requestId);
        assertTrue(status.isFinalized);
        assertFalse(status.isClaimed);
    }

    function test_Finalize_MultipleRequests() public {
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        // Verify all requests created
        assertEq(withdrawalQueue.getLastRequestId(), 3);
        assertEq(withdrawalQueue.getLastFinalizedRequestId(), 0);

        // Move time forward
        _warpAndMockOracleReport();

        // Finalize all requests
        vm.prank(finalizeRoleHolder);
        uint256 finalizedCount = withdrawalQueue.finalize(10, address(0)); // More than needed

        // Verify all finalized
        assertEq(finalizedCount, 3);
        assertEq(withdrawalQueue.getLastFinalizedRequestId(), 3);

        // Check each request status
        for (uint256 i = 1; i <= 3; i++) {
            WithdrawalQueue.WithdrawalRequestStatus memory status = withdrawalQueue.getWithdrawalStatus(i);
            assertTrue(status.isFinalized);
            assertFalse(status.isClaimed);
        }
    }

    function test_Finalize_PartialFinalization() public {
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        assertEq(withdrawalQueue.getLastRequestId(), 3);

        _warpAndMockOracleReport();

        vm.prank(finalizeRoleHolder);
        uint256 finalizedCount = withdrawalQueue.finalize(1, address(0));

        assertEq(finalizedCount, 1);
        assertEq(withdrawalQueue.getLastFinalizedRequestId(), 1);

        vm.prank(finalizeRoleHolder);
        uint256 remainingCount = withdrawalQueue.finalize(10, address(0));
        assertTrue(remainingCount > 0);
    }

    // Restrictions

    function test_Finalize_RevertMinDelayNotPassed() public {
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        // Don't advance time enough
        vm.warp(block.timestamp + MIN_WITHDRAWAL_DELAY_TIME - 1);

        // Should not finalize because min delay not passed
        vm.prank(finalizeRoleHolder);
        vm.expectRevert(WithdrawalQueue.NoRequestsToFinalize.selector);
        withdrawalQueue.finalize(1, address(0));
    }

    function test_Finalize_RequestAfterReport() public {
        // Set oracle timestamp to current time
        lazyOracle.mock__updateLatestReportTimestamp(block.timestamp);

        // Move time forward and create request after report
        vm.warp(block.timestamp + 1 hours);

        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        vm.warp(block.timestamp + MIN_WITHDRAWAL_DELAY_TIME + 1);

        // Should not finalize because request was created after last report
        vm.prank(finalizeRoleHolder);
        vm.expectRevert(WithdrawalQueue.NoRequestsToFinalize.selector);
        withdrawalQueue.finalize(1, address(0));
    }

    function test_Finalize_RevertOnlyFinalizeRole() public {
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        _warpAndMockOracleReport();

        // Try to finalize without proper role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, userAlice, withdrawalQueue.FINALIZE_ROLE()
            )
        );
        vm.prank(userAlice);
        withdrawalQueue.finalize(1, address(0));
    }

    function test_Finalize_ReturnsZeroWhenWithdrawableInsufficient() public {
        uint256 stvToRequest = 10 ** STV_DECIMALS;
        withdrawalQueue.requestWithdrawal(address(this), stvToRequest, 0);

        _warpAndMockOracleReport();

        address stakingVault = address(dashboard.VAULT());
        uint256 vaultBalance = stakingVault.balance;
        dashboard.mock_setLocked(vaultBalance);

        // Should not finalize because eth to withdraw is locked
        vm.prank(finalizeRoleHolder);
        vm.expectRevert(WithdrawalQueue.NoRequestsToFinalize.selector);
        withdrawalQueue.finalize(1, address(0));
    }

    function test_Finalize_PartialDueToWithdrawableLimit() public {
        uint256 stvRequest1 = 10 ** STV_DECIMALS;
        uint256 stvRequest2 = 2 * 10 ** STV_DECIMALS;

        withdrawalQueue.requestWithdrawal(address(this), stvRequest1, 0);
        withdrawalQueue.requestWithdrawal(address(this), stvRequest2, 0);

        _warpAndMockOracleReport();

        uint256 expectedEthFirst = pool.previewRedeem(stvRequest1);
        address stakingVault = address(dashboard.VAULT());
        uint256 vaultBalance = stakingVault.balance;
        dashboard.mock_setLocked(vaultBalance - expectedEthFirst);

        vm.prank(finalizeRoleHolder);
        uint256 finalizedCount = withdrawalQueue.finalize(10, address(0));

        assertEq(finalizedCount, 1);
        assertEq(withdrawalQueue.getLastFinalizedRequestId(), 1);
        assertTrue(withdrawalQueue.getWithdrawalStatus(1).isFinalized);
        assertFalse(withdrawalQueue.getWithdrawalStatus(2).isFinalized);
    }

    function test_Finalize_RebalanceBlockedByAvailableBalance() public {
        uint256 mintedStethShares = 10 ** ASSETS_DECIMALS;
        uint256 stvToRequest = 2 * 10 ** STV_DECIMALS;

        pool.mintStethShares(mintedStethShares);
        withdrawalQueue.requestWithdrawal(address(this), stvToRequest, mintedStethShares);

        _warpAndMockOracleReport();

        uint256 assetsPreview = pool.previewRedeem(stvToRequest);
        uint256 assetsToRebalance = pool.STETH().getPooledEthBySharesRoundUp(mintedStethShares);

        address stakingVault = address(dashboard.VAULT());
        vm.deal(stakingVault, assetsPreview);
        dashboard.mock_setLocked(assetsToRebalance + 1); // block by 1 wei

        // Should not finalize because eth to withdraw is locked
        vm.prank(finalizeRoleHolder);
        vm.expectRevert(WithdrawalQueue.NoRequestsToFinalize.selector);
        withdrawalQueue.finalize(1, address(0));
    }

    function test_Finalize_RebalanceWithBlockedButAvailableAssets() public {
        uint256 mintedStethShares = 10 ** ASSETS_DECIMALS;
        uint256 stvToRequest = 2 * 10 ** STV_DECIMALS;

        pool.mintStethShares(mintedStethShares);
        withdrawalQueue.requestWithdrawal(address(this), stvToRequest, mintedStethShares);

        _warpAndMockOracleReport();

        uint256 assetsPreview = pool.previewRedeem(stvToRequest);
        uint256 assetsToRebalance = pool.STETH().getPooledEthBySharesRoundUp(mintedStethShares);

        address stakingVault = address(dashboard.VAULT());
        vm.deal(stakingVault, assetsPreview);
        dashboard.mock_setLocked(assetsToRebalance);

        vm.prank(finalizeRoleHolder);
        assertEq(withdrawalQueue.finalize(1, address(0)), 1);
    }

    function test_Finalize_RebalancePartiallyDueToAvailableBalance() public {
        uint256 mintedStethShares = 10 ** ASSETS_DECIMALS;
        uint256 stvToRequest = 2 * 10 ** STV_DECIMALS;

        pool.mintStethShares(mintedStethShares);
        uint256 requestId1 = withdrawalQueue.requestWithdrawal(address(this), stvToRequest, mintedStethShares);

        pool.mintStethShares(mintedStethShares);
        uint256 requestId2 = withdrawalQueue.requestWithdrawal(address(this), stvToRequest, mintedStethShares);

        _warpAndMockOracleReport();

        uint256 assetsRequired = pool.previewRedeem(stvToRequest);
        address stakingVault = address(dashboard.VAULT());
        vm.deal(stakingVault, assetsRequired);
        dashboard.mock_setLocked(0);

        vm.prank(finalizeRoleHolder);
        uint256 finalizedCount = withdrawalQueue.finalize(10, address(0));

        assertEq(finalizedCount, 1);
        assertTrue(withdrawalQueue.getWithdrawalStatus(requestId1).isFinalized);
        assertFalse(withdrawalQueue.getWithdrawalStatus(requestId2).isFinalized);
    }

    // Pause & resume request finalization

    function test_Finalize_RevertWhenPaused() public {
        bytes32 finalizeFeatureId = withdrawalQueue.FINALIZE_FEATURE();
        vm.prank(finalizePauseRoleHolder);
        withdrawalQueue.pauseFinalization();

        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        vm.prank(finalizeRoleHolder);
        vm.expectRevert(abi.encodeWithSelector(FeaturePausable.FeaturePauseEnforced.selector, finalizeFeatureId));
        withdrawalQueue.finalize(1, finalizeRoleHolder);
    }

    function test_PauseFinalization_RevertWhenCallerUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                withdrawalQueue.FINALIZE_PAUSE_ROLE()
            )
        );
        withdrawalQueue.pauseFinalization();
    }

    function test_ResumeFinalization_RevertWhenCallerUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                withdrawalQueue.FINALIZE_RESUME_ROLE()
            )
        );
        withdrawalQueue.resumeFinalization();
    }

    function test_Resume_AllowsFinalizationAfterPause() public {
        vm.prank(finalizePauseRoleHolder);
        withdrawalQueue.pauseFinalization();

        vm.prank(finalizeResumeRoleHolder);
        withdrawalQueue.resumeFinalization();

        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        _warpAndMockOracleReport();

        vm.prank(finalizeRoleHolder);
        uint256 finalized = withdrawalQueue.finalize(1, finalizeRoleHolder);
        assertEq(finalized, 1);
    }

    // Edge Cases

    function test_Finalize_ZeroMaxRequests() public {
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        _warpAndMockOracleReport();

        vm.prank(finalizeRoleHolder);
        vm.expectRevert(WithdrawalQueue.NoRequestsToFinalize.selector);
        withdrawalQueue.finalize(0, address(0));
    }

    function test_Finalize_NoRequestsToFinalize() public {
        vm.prank(finalizeRoleHolder);
        vm.expectRevert(WithdrawalQueue.NoRequestsToFinalize.selector);
        withdrawalQueue.finalize(1, address(0));
    }

    function test_Finalize_AlreadyFullyFinalized() public {
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        _warpAndMockOracleReport();

        // First finalization
        vm.prank(finalizeRoleHolder);
        withdrawalQueue.finalize(1, address(0));

        // Try to finalize again
        vm.prank(finalizeRoleHolder);
        vm.expectRevert(WithdrawalQueue.NoRequestsToFinalize.selector);
        withdrawalQueue.finalize(1, address(0));
    }

    function test_Finalize_RevertWhenReportStale() public {
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        _warpAndMockOracleReport();

        dashboard.VAULT_HUB().mock_setReportFreshness(address(dashboard.VAULT()), false);

        vm.prank(finalizeRoleHolder);
        vm.expectRevert(WithdrawalQueue.VaultReportStale.selector);
        withdrawalQueue.finalize(1, address(0));
    }

    function test_Finalize_RevertWhenFinalizerCannotReceiveFee() public {
        uint256 coverage = 0.0001 ether;
        vm.prank(finalizeRoleHolder);
        withdrawalQueue.setFinalizationGasCostCoverage(coverage);

        RevertingFinalizer finalizer = new RevertingFinalizer(withdrawalQueue);
        bytes32 finalizeRole = withdrawalQueue.FINALIZE_ROLE();

        vm.prank(owner);
        withdrawalQueue.grantRole(finalizeRole, address(finalizer));

        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        assertEq(requestId, 1);

        _warpAndMockOracleReport();

        vm.expectRevert(WithdrawalQueue.CantSendValueRecipientMayHaveReverted.selector);
        finalizer.callFinalize(1);
    }

    function test_Finalize_RevertWhenWithdrawableInsufficientButAvailableEnough() public {
        uint256 stvToRequest = 10 ** STV_DECIMALS;
        uint256 expectedAssets = pool.previewRedeem(stvToRequest);
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), stvToRequest, 0);

        assertEq(requestId, 1);

        _warpAndMockOracleReport();
        dashboard.mock_setLocked(pool.totalAssets() - expectedAssets + 1);

        vm.prank(finalizeRoleHolder);
        vm.expectRevert(WithdrawalQueue.NoRequestsToFinalize.selector);
        withdrawalQueue.finalize(1, address(0));
    }

    // Checkpoint Tests

    function test_Finalize_CreatesCheckpoint() public {
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        // Verify no checkpoints initially
        assertEq(withdrawalQueue.getLastCheckpointIndex(), 0);

        _warpAndMockOracleReport();

        vm.prank(finalizeRoleHolder);
        withdrawalQueue.finalize(1, address(0));

        // Verify checkpoint was created
        assertEq(withdrawalQueue.getLastCheckpointIndex(), 1);
    }

    // Rewards & penalties

    function test_Finalize_RewardsDoNotAffectFinalizationRate() public {
        uint256 stvToRequest = 10 ** STV_DECIMALS;
        uint256 expectedEth = pool.previewRedeem(stvToRequest);
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), stvToRequest, 0);

        // Simulate rewards
        uint256 totalAssetsBefore = pool.totalAssets();
        dashboard.mock_simulateRewards(10 ether);
        uint256 totalAssetsAfter = pool.totalAssets();
        assertEq(totalAssetsAfter, totalAssetsBefore + 10 ether);

        // Finalize request
        _finalizeRequests(1);

        // Check finalized request has correct ETH amount unaffected by rewards
        assertEq(withdrawalQueue.getClaimableEther(requestId), expectedEth);
    }

    function test_Finalize_PenaltiesAffectFinalizationRate() public {
        uint256 stvToRequest = 10 ** STV_DECIMALS;
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), stvToRequest, 0);

        // Simulate penalties
        uint256 totalAssetsBefore = pool.totalAssets();
        dashboard.mock_simulateRewards(-10 ether);
        uint256 totalAssetsAfter = pool.totalAssets();
        assertEq(totalAssetsAfter, totalAssetsBefore - 10 ether);

        // Expected ETH should be lower due to penalties
        uint256 expectedEth = pool.previewRedeem(stvToRequest);

        // Finalize request
        _finalizeRequests(1);

        // Check finalized request has correct ETH amount unaffected by rewards
        assertEq(withdrawalQueue.getClaimableEther(requestId), expectedEth);
    }

    // Exceeding Minted StETH

    function test_Finalize_MultipleRequestsWithExceedingSteth() public {
        uint256 mintedStethShares = pool.totalMintingCapacitySharesOf(address(this)) / 3 * 3;
        pool.mintStethShares(mintedStethShares);

        // Initially no exceeding minted steth
        assertEq(pool.totalExceedingMintedStethShares(), 0);

        // Create multiple withdrawal requests with enough stv to cover liability
        uint256 stvPerRequest = pool.balanceOf(address(this)) / 3;
        withdrawalQueue.requestWithdrawal(address(this), stvPerRequest, mintedStethShares / 3);
        withdrawalQueue.requestWithdrawal(address(this), stvPerRequest, mintedStethShares / 3);
        withdrawalQueue.requestWithdrawal(address(this), stvPerRequest, mintedStethShares / 3);

        assertEq(withdrawalQueue.getLastRequestId(), 3);

        // Simulate vault rebalance to create exceeding minted steth
        uint256 liabilityShares = dashboard.liabilityShares();
        assertGt(liabilityShares, 0);
        dashboard.rebalanceVaultWithShares(liabilityShares / 2);

        // Exceeding minted steth should now be present
        assertGt(pool.totalExceedingMintedStethShares(), 0);

        // Finalize all requests
        _finalizeRequests(3);

        // Verify no unfinalized requests remain
        assertEq(withdrawalQueue.unfinalizedRequestsNumber(), 0);

        // Exceeding steth should be consumed during finalization
        assertEq(pool.totalExceedingMintedStethShares(), 0);
    }
}

contract RevertingFinalizer {
    WithdrawalQueue public immutable WITHDRAWAL_QUEUE;

    constructor(WithdrawalQueue _withdrawalQueue) {
        WITHDRAWAL_QUEUE = _withdrawalQueue;
    }

    function callFinalize(uint256 maxRequests) external {
        WITHDRAWAL_QUEUE.finalize(maxRequests, address(0));
    }

    receive() external payable {
        revert("cannot receive");
    }
}
