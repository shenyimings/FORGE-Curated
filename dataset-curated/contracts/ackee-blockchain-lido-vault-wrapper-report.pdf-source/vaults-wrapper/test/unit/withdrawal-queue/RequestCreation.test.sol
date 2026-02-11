// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupWithdrawalQueue} from "./SetupWithdrawalQueue.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {FeaturePausable} from "src/utils/FeaturePausable.sol";

contract RequestCreationTest is Test, SetupWithdrawalQueue {
    function setUp() public override {
        super.setUp();

        vm.prank(userAlice);
        pool.depositETH{value: 100 ether}(userAlice, address(0));

        vm.prank(userBob);
        pool.depositETH{value: 100 ether}(userBob, address(0));

        // from test contract
        pool.depositETH{value: 100_000 ether}(address(this), address(0));
    }

    // Initial State Tests

    function test_InitialState_NoRequests() public view {
        assertEq(withdrawalQueue.getLastRequestId(), 0);
        assertEq(withdrawalQueue.getLastFinalizedRequestId(), 0);
        assertEq(withdrawalQueue.unfinalizedRequestsNumber(), 0);
        assertEq(withdrawalQueue.unfinalizedAssets(), 0);
        assertEq(withdrawalQueue.unfinalizedStv(), 0);
    }

    function test_InitialState_CorrectRoles() public view {
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.FINALIZE_ROLE(), finalizeRoleHolder));
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.WITHDRAWALS_PAUSE_ROLE(), withdrawalsPauseRoleHolder));
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.WITHDRAWALS_RESUME_ROLE(), withdrawalsResumeRoleHolder));
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.FINALIZE_PAUSE_ROLE(), finalizePauseRoleHolder));
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.FINALIZE_RESUME_ROLE(), finalizeResumeRoleHolder));
    }

    function test_InitialState_NotPaused() public view {
        assertFalse(withdrawalQueue.isFeaturePaused(withdrawalQueue.WITHDRAWALS_FEATURE()));
        assertFalse(withdrawalQueue.isFeaturePaused(withdrawalQueue.FINALIZE_FEATURE()));
    }

    // Single Request Tests

    function test_RequestWithdrawal_SingleRequest() public {
        uint256 stvToRequest = 10 ** STV_DECIMALS;
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), stvToRequest, 0);

        assertEq(requestId, 1);
        assertEq(withdrawalQueue.getLastRequestId(), 1);
        assertEq(withdrawalQueue.unfinalizedRequestsNumber(), 1);
        assertEq(withdrawalQueue.unfinalizedStv(), stvToRequest);

        // Check request details
        WithdrawalQueue.WithdrawalRequestStatus memory status = withdrawalQueue.getWithdrawalStatus(requestId);
        assertEq(status.amountOfStv, stvToRequest);
        assertEq(status.amountOfAssets, 1 ether); // 1 STV = 1 ETH at initial rate
        assertEq(status.amountOfStethShares, 0);
        assertEq(status.owner, address(this));
        assertEq(status.timestamp, block.timestamp);
        assertFalse(status.isFinalized);
        assertFalse(status.isClaimed);
    }

    function test_RequestWithdrawal_EmitsCorrectEvent() public {
        uint256 expectedAssets = pool.previewRedeem(10 ** STV_DECIMALS);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalQueue.WithdrawalRequested(1, address(this), 10 ** STV_DECIMALS, 0, expectedAssets);

        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
    }

    function test_RequestWithdrawal_WithStethShares() public {
        uint256 mintedStethShares = 10 ** ASSETS_DECIMALS;
        uint256 stvToRequest = 2 * 10 ** STV_DECIMALS;
        pool.mintStethShares(mintedStethShares);
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), stvToRequest, mintedStethShares);

        WithdrawalQueue.WithdrawalRequestStatus memory status = withdrawalQueue.getWithdrawalStatus(requestId);
        assertEq(status.amountOfStv, stvToRequest);
        assertEq(status.amountOfStethShares, mintedStethShares);
        assertEq(status.owner, address(this));
    }

    function test_RequestWithdrawal_UpdatesCumulativeValues() public {
        vm.prank(userAlice);
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        vm.prank(userBob);
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS * 2, 0);

        assertEq(withdrawalQueue.unfinalizedStv(), 10 ** STV_DECIMALS * 3);
        assertEq(withdrawalQueue.getLastRequestId(), 2);

        // Check individual request amounts
        WithdrawalQueue.WithdrawalRequestStatus memory status1 = withdrawalQueue.getWithdrawalStatus(1);
        WithdrawalQueue.WithdrawalRequestStatus memory status2 = withdrawalQueue.getWithdrawalStatus(2);

        assertEq(status1.amountOfStv, 10 ** STV_DECIMALS);
        assertEq(status2.amountOfStv, 10 ** STV_DECIMALS * 2);
    }

    function test_RequestWithdrawal_AddToUserRequests() public {
        uint256 requestId1 = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        uint256 requestId2 = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        uint256[] memory requests = withdrawalQueue.withdrawalRequestsOf(address(this));
        assertEq(requests.length, 2);
        assertEq(requests[0], requestId1);
        assertEq(requests[1], requestId2);

        // Bob should have no requests
        uint256[] memory bobRequests = withdrawalQueue.withdrawalRequestsOf(userBob);
        assertEq(bobRequests.length, 0);
    }

    // Multiple requests tests

    function test_RequestWithdrawals_MultipleInSingleCall() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10 ** STV_DECIMALS;
        amounts[1] = 10 ** STV_DECIMALS * 2;
        amounts[2] = 10 ** STV_DECIMALS;

        uint256[] memory stethShares = new uint256[](3);

        uint256[] memory requestIds = withdrawalQueue.requestWithdrawalBatch(address(this), amounts, stethShares);

        assertEq(requestIds.length, 3);
        assertEq(requestIds[0], 1);
        assertEq(requestIds[1], 2);
        assertEq(requestIds[2], 3);
        assertEq(withdrawalQueue.getLastRequestId(), 3);

        // Check individual amounts
        WithdrawalQueue.WithdrawalRequestStatus memory status1 = withdrawalQueue.getWithdrawalStatus(1);
        WithdrawalQueue.WithdrawalRequestStatus memory status2 = withdrawalQueue.getWithdrawalStatus(2);
        WithdrawalQueue.WithdrawalRequestStatus memory status3 = withdrawalQueue.getWithdrawalStatus(3);

        assertEq(status1.amountOfStv, amounts[0]);
        assertEq(status2.amountOfStv, amounts[1]);
        assertEq(status3.amountOfStv, amounts[2]);
    }

    function test_RequestWithdrawals_DifferentUsers() public {
        vm.prank(userAlice);
        withdrawalQueue.requestWithdrawal(userAlice, 10 ** STV_DECIMALS, 0);

        vm.prank(userBob);
        withdrawalQueue.requestWithdrawal(userBob, 2 * 10 ** STV_DECIMALS, 0);

        vm.prank(userAlice);
        withdrawalQueue.requestWithdrawal(userAlice, 10 ** STV_DECIMALS, 0);

        uint256[] memory aliceRequests = withdrawalQueue.withdrawalRequestsOf(userAlice);
        uint256[] memory bobRequests = withdrawalQueue.withdrawalRequestsOf(userBob);

        assertEq(aliceRequests.length, 2);
        assertEq(bobRequests.length, 1);
        assertEq(aliceRequests[0], 1);
        assertEq(aliceRequests[1], 3);
        assertEq(bobRequests[0], 2);
    }

    // Validation tests

    function test_RequestWithdrawals_RevertOnArrayLengthMismatch() public {
        uint256[] memory stvAmounts = new uint256[](2);
        stvAmounts[0] = 10 ** STV_DECIMALS;
        stvAmounts[1] = 2 * 10 ** STV_DECIMALS;

        uint256[] memory stethShares = new uint256[](1);
        stethShares[0] = 10 ** ASSETS_DECIMALS;

        vm.prank(address(pool));
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.ArraysLengthMismatch.selector, 2, 1));
        withdrawalQueue.requestWithdrawalBatch(address(this), stvAmounts, stethShares);
    }

    function test_RequestWithdrawal_RevertOnTooSmallValue() public {
        uint256 tinyStvAmount = pool.previewWithdraw(withdrawalQueue.MIN_WITHDRAWAL_VALUE()) - 1;
        uint256 expectedAssets = pool.previewRedeem(tinyStvAmount);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.RequestValueTooSmall.selector, expectedAssets));
        withdrawalQueue.requestWithdrawal(address(this), tinyStvAmount, 0);
    }

    function test_RequestWithdrawal_RevertOnTooSmallValueWithRebalance() public {
        uint256 minStvAmount = pool.previewWithdraw(withdrawalQueue.MIN_WITHDRAWAL_VALUE());
        uint256 minMintedShares = 1;
        uint256 expectedAssets = pool.previewRedeem(minStvAmount) - steth.getPooledEthBySharesRoundUp(minMintedShares);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.RequestValueTooSmall.selector, expectedAssets));
        withdrawalQueue.requestWithdrawal(address(this), minStvAmount, minMintedShares);
    }

    function test_RequestWithdrawal_RevertOnTooLargeAmount() public {
        uint256 extraAssetsWei = 10 ** (STV_DECIMALS - ASSETS_DECIMALS);
        uint256 hugeStvAmount = pool.previewWithdraw(withdrawalQueue.MAX_WITHDRAWAL_ASSETS()) + extraAssetsWei;
        uint256 expectedAssets = pool.previewRedeem(hugeStvAmount);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.RequestAssetsTooLarge.selector, expectedAssets));
        withdrawalQueue.requestWithdrawal(address(this), hugeStvAmount, 0);
    }

    // Pause & resume withdrawal requests submission

    function test_RequestWithdrawal_RevertWhenPaused() public {
        bytes32 withdrawalsFeatureId = withdrawalQueue.WITHDRAWALS_FEATURE();
        vm.prank(withdrawalsPauseRoleHolder);
        withdrawalQueue.pauseWithdrawals();

        vm.expectRevert(abi.encodeWithSelector(FeaturePausable.FeaturePauseEnforced.selector, withdrawalsFeatureId));
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
    }

    function test_PauseWithdrawals_RevertWhenCallerUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                withdrawalQueue.WITHDRAWALS_PAUSE_ROLE()
            )
        );
        withdrawalQueue.pauseWithdrawals();
    }

    function test_ResumeWithdrawals_RevertWhenCallerUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                withdrawalQueue.WITHDRAWALS_RESUME_ROLE()
            )
        );
        withdrawalQueue.resumeWithdrawals();
    }

    function test_Resume_AllowsRequestsAfterPause() public {
        vm.prank(withdrawalsPauseRoleHolder);
        withdrawalQueue.pauseWithdrawals();

        vm.prank(withdrawalsResumeRoleHolder);
        withdrawalQueue.resumeWithdrawals();

        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        assertEq(requestId, 1);
    }

    // Edge cases

    function test_RequestWithdrawal_ReversOnZeroRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.ZeroAddress.selector));
        withdrawalQueue.requestWithdrawal(address(0), 10 ** STV_DECIMALS, 0);
    }

    function test_RequestWithdrawalBatch_ReversOnZeroRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.ZeroAddress.selector));
        withdrawalQueue.requestWithdrawalBatch(address(0), new uint256[](1), new uint256[](1));
    }

    function test_RequestWithdrawal_ExactMinAmount() public {
        // Calculate STV amount needed for MAX_WITHDRAWAL_ASSETS
        uint256 minAmount = withdrawalQueue.MAX_WITHDRAWAL_ASSETS();
        uint256 stvAmount = pool.previewWithdraw(minAmount);

        // This should succeed
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), stvAmount, 0);
        assertEq(requestId, 1);
    }

    function test_RequestWithdrawal_ExactMaxAmount() public {
        // Calculate STV amount needed for MAX_WITHDRAWAL_ASSETS
        uint256 maxAmount = withdrawalQueue.MAX_WITHDRAWAL_ASSETS();
        uint256 stvAmount = pool.previewWithdraw(maxAmount);

        // This should succeed
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), stvAmount, 0);
        assertEq(requestId, 1);
    }

    function test_WithdrawalRequestsLengthOf_RemovesEntriesAfterClaim() public {
        uint256 requestId1 = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        uint256 requestId2 = withdrawalQueue.requestWithdrawal(address(this), 2 * 10 ** STV_DECIMALS, 0);

        assertEq(withdrawalQueue.withdrawalRequestsLengthOf(address(this)), 2);

        _finalizeRequests(2);

        withdrawalQueue.claimWithdrawal(address(this), requestId1);
        withdrawalQueue.claimWithdrawal(address(this), requestId2);

        assertEq(withdrawalQueue.withdrawalRequestsLengthOf(address(this)), 0);
        assertEq(withdrawalQueue.withdrawalRequestsOf(address(this)).length, 0);
    }

    function test_withdrawalRequestsOf_PaginationReturnsSlice() public {
        uint256 requestId1 = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        uint256 requestId2 = withdrawalQueue.requestWithdrawal(address(this), 2 * 10 ** STV_DECIMALS, 0);
        uint256 requestId3 = withdrawalQueue.requestWithdrawal(address(this), 3 * 10 ** STV_DECIMALS, 0);

        uint256[] memory page = withdrawalQueue.withdrawalRequestsInRangeOf(address(this), 1, 3);

        assertEq(page.length, 2);
        assertEq(page[0], requestId2);
        assertEq(page[1], requestId3);

        // make sure the full list preserves insertion order
        uint256[] memory fullList = withdrawalQueue.withdrawalRequestsOf(address(this));
        assertEq(fullList[0], requestId1);
        assertEq(fullList[1], requestId2);
        assertEq(fullList[2], requestId3);
    }

    function test_UnfinalizedStats_TrackAssetsAndStv() public {
        uint256 stvAmount1 = 10 ** STV_DECIMALS;
        uint256 stvAmount2 = 3 * 10 ** STV_DECIMALS;

        uint256 expectedAssets1 = pool.previewRedeem(stvAmount1);
        uint256 expectedAssets2 = pool.previewRedeem(stvAmount2);

        withdrawalQueue.requestWithdrawal(address(this), stvAmount1, 0);
        withdrawalQueue.requestWithdrawal(address(this), stvAmount2, 0);

        assertEq(withdrawalQueue.unfinalizedStv(), stvAmount1 + stvAmount2);
        assertEq(withdrawalQueue.unfinalizedAssets(), expectedAssets1 + expectedAssets2);

        _finalizeRequests(2);

        assertEq(withdrawalQueue.unfinalizedStv(), 0);
        assertEq(withdrawalQueue.unfinalizedAssets(), 0);
    }

    function test_UnfinalizedStats_TrackStethShares() public {
        uint256 stvAmount = 2 * 10 ** STV_DECIMALS;
        uint256 mintedShares = 10 ** ASSETS_DECIMALS;

        pool.mintStethShares(mintedShares);
        withdrawalQueue.requestWithdrawal(address(this), stvAmount, mintedShares);

        assertEq(withdrawalQueue.unfinalizedStethShares(), mintedShares);

        _finalizeRequests(1);

        assertEq(withdrawalQueue.unfinalizedStethShares(), 0);
    }

    // Receive function to accept ETH refunds
    receive() external payable {}
}
