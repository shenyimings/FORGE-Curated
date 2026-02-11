// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SetupWithdrawalQueue} from "./SetupWithdrawalQueue.sol";
import {Test} from "forge-std/Test.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";

contract ClaimingTest is Test, SetupWithdrawalQueue {
    function setUp() public override {
        super.setUp();

        // Deposit initial ETH to pool for withdrawals
        pool.depositETH{value: 100_000 ether}(address(this), address(0));
    }

    // Basic Claiming

    function test_ClaimWithdrawal_SuccessfulClaim() public {
        // Create and finalize a request
        uint256 requestId = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        // Check initial state
        assertTrue(withdrawalQueue.getWithdrawalStatus(requestId).isFinalized);
        assertFalse(withdrawalQueue.getWithdrawalStatus(requestId).isClaimed);

        // Record initial ETH balance
        uint256 initialBalance = address(this).balance;
        uint256 claimableAmount = withdrawalQueue.getClaimableEther(requestId);
        assertTrue(claimableAmount > 0);

        // Claim the withdrawal
        withdrawalQueue.claimWithdrawal(address(this), requestId);

        // Verify claim succeeded
        assertTrue(withdrawalQueue.getWithdrawalStatus(requestId).isClaimed);
        assertEq(withdrawalQueue.getClaimableEther(requestId), 0);
        assertEq(address(this).balance, initialBalance + claimableAmount);
    }

    function test_ClaimWithdrawal_ClaimToRecipient() public {
        // Create and finalize a request
        uint256 requestId = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        // Claim to different recipient
        uint256 initialRecipientBalance = userAlice.balance;
        uint256 claimableAmount = withdrawalQueue.getClaimableEther(requestId);

        withdrawalQueue.claimWithdrawal(userAlice, requestId);

        // Verify ETH went to recipient
        assertEq(userAlice.balance, initialRecipientBalance + claimableAmount);
        assertTrue(withdrawalQueue.getWithdrawalStatus(requestId).isClaimed);
    }

    function test_ClaimWithdrawals_MultipleClaims() public {
        // Create and finalize multiple requests
        uint256 requestId1 = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);
        uint256 requestId2 = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);
        uint256 requestId3 = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        // Get hints for batch claiming
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = requestId1;
        requestIds[1] = requestId2;
        requestIds[2] = requestId3;

        uint256[] memory hints =
            withdrawalQueue.findCheckpointHintBatch(requestIds, 1, withdrawalQueue.getLastCheckpointIndex());

        // Record initial balance and claimable amounts
        uint256 initialBalance = address(this).balance;
        uint256 totalClaimable = 0;
        uint256[] memory expected = new uint256[](requestIds.length);
        for (uint256 i = 0; i < requestIds.length; i++) {
            expected[i] = withdrawalQueue.getClaimableEther(requestIds[i]);
            totalClaimable += expected[i];
        }

        // Batch claim
        uint256[] memory claimed = withdrawalQueue.claimWithdrawalBatch(address(this), requestIds, hints);

        // Verify all claims and returned amounts
        for (uint256 i = 0; i < requestIds.length; i++) {
            assertTrue(withdrawalQueue.getWithdrawalStatus(requestIds[i]).isClaimed);
            assertEq(withdrawalQueue.getClaimableEther(requestIds[i]), 0);
            assertEq(claimed[i], expected[i]);
        }
        assertEq(address(this).balance, initialBalance + totalClaimable);
    }

    // Error Cases

    function test_ClaimWithdrawals_RevertArraysLengthMismatch() public {
        uint256 requestId = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        uint256[] memory hints = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.ArraysLengthMismatch.selector, 1, 0));
        withdrawalQueue.claimWithdrawalBatch(address(this), requestIds, hints);
    }

    function test_ClaimWithdrawal_RevertNotFinalized() public {
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        // Try to claim before finalization
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.RequestNotFoundOrNotFinalized.selector, requestId));
        withdrawalQueue.claimWithdrawal(address(this), requestId);
    }

    function test_ClaimWithdrawal_RevertAlreadyClaimed() public {
        // Create and finalize a request
        uint256 requestId = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        // Claim once
        withdrawalQueue.claimWithdrawal(address(this), requestId);

        // Try to claim again
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.RequestAlreadyClaimed.selector, requestId));
        withdrawalQueue.claimWithdrawal(address(this), requestId);
    }

    function test_ClaimWithdrawal_RevertWrongOwner() public {
        // Create and finalize a request
        uint256 requestId = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        // Try to claim from different address
        vm.prank(userAlice);
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.NotOwner.selector, userAlice, address(this)));
        withdrawalQueue.claimWithdrawal(userAlice, requestId);
    }

    function test_ClaimWithdrawal_RevertInvalidRequestId() public {
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.InvalidRequestId.selector, 999));
        withdrawalQueue.claimWithdrawal(address(this), 999);
    }

    function test_ClaimWithdrawal_RevertRecipientReverts() public {
        uint256 requestId = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);
        RevertingReceiver revertingRecipient = new RevertingReceiver();

        vm.expectRevert(WithdrawalQueue.CantSendValueRecipientMayHaveReverted.selector);
        withdrawalQueue.claimWithdrawal(address(revertingRecipient), requestId);
    }

    // Edge Cases

    function test_ClaimWithdrawal_RevertsIfReceiverIsZeroAddress() public {
        uint256 requestId = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.ZeroAddress.selector));
        withdrawalQueue.claimWithdrawal(address(0), requestId);
    }

    function test_ClaimWithdrawal_PartiallyFinalizedQueue() public {
        // Create 3 requests but finalize only 2
        uint256 requestId1 = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        uint256 requestId2 = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        uint256 requestId3 = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        _finalizeRequests(2); // Only finalize first 2

        // Can claim first 2
        withdrawalQueue.claimWithdrawal(address(this), requestId1);
        withdrawalQueue.claimWithdrawal(address(this), requestId2);

        // Cannot claim the third
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.RequestNotFoundOrNotFinalized.selector, requestId3));
        withdrawalQueue.claimWithdrawal(address(this), requestId3);
    }

    function test_ClaimWithdrawal_ClaimableEtherCalculation() public {
        uint256 requestedStv = 10 ** STV_DECIMALS;
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), requestedStv, 0);

        // Before finalization - should be 0
        assertEq(withdrawalQueue.getClaimableEther(requestId), 0);

        _finalizeRequests(1);

        // After finalization - should be equal to previewRedeem (if stvRate didn't change)
        uint256 claimableAmount = withdrawalQueue.getClaimableEther(requestId);
        assertEq(claimableAmount, pool.previewRedeem(requestedStv));

        // After claiming - should be 0 again
        withdrawalQueue.claimWithdrawal(address(this), requestId);
        assertEq(withdrawalQueue.getClaimableEther(requestId), 0);
    }

    function test_ClaimWithdrawals_DefaultRecipientToMsgSender() public {
        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);
        requestIds[1] = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        uint256[] memory hints =
            withdrawalQueue.findCheckpointHintBatch(requestIds, 1, withdrawalQueue.getLastCheckpointIndex());

        uint256 initialBalance = address(this).balance;
        uint256 totalClaimable;
        for (uint256 i = 0; i < requestIds.length; ++i) {
            totalClaimable += withdrawalQueue.getClaimableEther(requestIds[i]);
        }

        withdrawalQueue.claimWithdrawalBatch(address(this), requestIds, hints);

        assertEq(address(this).balance, initialBalance + totalClaimable);
    }

    function test_ClaimWithdrawals_RevertWithZeroHint() public {
        uint256 requestId = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        uint256[] memory hints = new uint256[](1);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.InvalidHint.selector, 0));
        withdrawalQueue.claimWithdrawalBatch(address(this), requestIds, hints);
    }

    function test_ClaimWithdrawals_RevertWithOutOfRangeHint() public {
        uint256 requestId = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        uint256[] memory hints = new uint256[](1);
        hints[0] = withdrawalQueue.getLastCheckpointIndex() + 1;

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.InvalidHint.selector, hints[0]));
        withdrawalQueue.claimWithdrawalBatch(address(this), requestIds, hints);
    }

    function test_ClaimWithdrawals_RevertWithPreviousCheckpointHint() public {
        uint256 requestId1 = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);
        uint256 requestId2 = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = requestId1;
        requestIds[1] = requestId2;

        uint256[] memory correctHints =
            withdrawalQueue.findCheckpointHintBatch(requestIds, 1, withdrawalQueue.getLastCheckpointIndex());
        assertEq(correctHints[0], 1);
        assertEq(correctHints[1], 2);

        uint256[] memory wrongHints = new uint256[](2);
        wrongHints[0] = correctHints[0];
        wrongHints[1] = correctHints[0];

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.InvalidHint.selector, wrongHints[1]));
        withdrawalQueue.claimWithdrawalBatch(address(this), requestIds, wrongHints);
    }

    function test_GetClaimableEther_ReturnsZeroForUnknownRequest() public {
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.InvalidRequestId.selector, 999));
        withdrawalQueue.getClaimableEther(999);
    }

    function test_GetClaimableEtherBatch_RevertArraysLengthMismatch() public {
        uint256 requestId = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        uint256[] memory hints = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.ArraysLengthMismatch.selector, 1, 0));
        withdrawalQueue.getClaimableEtherBatch(requestIds, hints);
    }

    // Receive ETH for claiming tests
    receive() external payable {}
}

contract RevertingReceiver {
    receive() external payable {
        revert("Cannot receive");
    }
}
