// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SetupWithdrawalQueue} from "./SetupWithdrawalQueue.sol";
import {Test} from "forge-std/Test.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";

contract CheckpointsTest is Test, SetupWithdrawalQueue {
    function setUp() public override {
        super.setUp();

        // Deposit initial ETH to pool for withdrawals
        pool.depositETH{value: 1000 ether}(address(this), address(0));
    }

    // Basic Checkpoint Operations

    function test_Checkpoints_InitialState() public view {
        // Initially no checkpoints
        assertEq(withdrawalQueue.getLastCheckpointIndex(), 0);
    }

    function test_Checkpoints_CreatedOnFinalization() public {
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        // No checkpoints before finalization
        assertEq(withdrawalQueue.getLastCheckpointIndex(), 0);

        _finalizeRequests(1);

        // Checkpoint created after finalization
        assertEq(withdrawalQueue.getLastCheckpointIndex(), 1);
    }

    function test_Checkpoints_MultipleFinalizationsCreateMultipleCheckpoints() public {
        // Create 3 separate requests
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        // Finalize first request
        _finalizeRequests(1);
        assertEq(withdrawalQueue.getLastCheckpointIndex(), 1);

        // Finalize second request
        _finalizeRequests(1);
        assertEq(withdrawalQueue.getLastCheckpointIndex(), 2);

        // Finalize third request
        _finalizeRequests(1);
        assertEq(withdrawalQueue.getLastCheckpointIndex(), 3);
    }

    function test_Checkpoints_BatchFinalizationCreatesSingleCheckpoint() public {
        // Create 3 separate requests
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        // Batch finalize all requests
        _finalizeRequests(3);

        // Only one checkpoint created for batch
        assertEq(withdrawalQueue.getLastCheckpointIndex(), 1);
    }

    // FindCheckpointHints Function

    function test_CheckpointHints_SingleRequest() public {
        uint256 requestId = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;

        uint256[] memory hints =
            withdrawalQueue.findCheckpointHintBatch(requestIds, 1, withdrawalQueue.getLastCheckpointIndex());

        assertEq(hints.length, 1);
        assertEq(hints[0], 1); // Should point to first checkpoint
    }

    function test_CheckpointHints_MultipleRequests() public {
        // Create and finalize 3 requests separately
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);
        requestIds[1] = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);
        requestIds[2] = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        uint256[] memory hints =
            withdrawalQueue.findCheckpointHintBatch(requestIds, 1, withdrawalQueue.getLastCheckpointIndex());

        assertEq(hints.length, 3);
        assertEq(hints[0], 1); // First request → first checkpoint
        assertEq(hints[1], 2); // Second request → second checkpoint
        assertEq(hints[2], 3); // Third request → third checkpoint
    }

    function test_CheckpointHints_NotFinalizedRequest() public {
        _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        // Create a second request but do not finalize
        uint256 requestId2 = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId2; // Second request not finalized

        uint256[] memory hints =
            withdrawalQueue.findCheckpointHintBatch(requestIds, 1, withdrawalQueue.getLastCheckpointIndex());

        // Should return NOT_FOUND (0) for unfinalized request
        assertEq(hints[0], 0);
    }

    function test_CheckpointHints_BatchDoesNotRevertOnNotFinalizedRequests() public {
        _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        uint256 requestId1 = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        uint256 requestId2 = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = requestId1;
        requestIds[1] = requestId2;

        uint256[] memory hints =
            withdrawalQueue.findCheckpointHintBatch(requestIds, 1, withdrawalQueue.getLastCheckpointIndex());

        assertEq(hints[0], 0);
        assertEq(hints[1], 0);
    }

    function test_CheckpointHints_BatchDoesNotRevertWhenFirstOutsideRange() public {
        uint256 requestId1 = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);
        uint256 requestId2 = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        uint256 lastCheckpointIndex = withdrawalQueue.getLastCheckpointIndex();
        assertEq(lastCheckpointIndex, 2);

        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = requestId1;
        requestIds[1] = requestId2;

        uint256[] memory hints = withdrawalQueue.findCheckpointHintBatch(requestIds, 2, lastCheckpointIndex);

        assertEq(hints[0], 0);
        assertEq(hints[1], 2);
    }

    function test_CheckpointHints_InvalidRange() public {
        uint256 requestId = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;

        // Invalid range: start = 0 (should be >= 1)
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.InvalidRange.selector, 0, 1));
        withdrawalQueue.findCheckpointHintBatch(requestIds, 0, 1);

        // Invalid range: end > lastCheckpointIndex
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.InvalidRange.selector, 1, 999));
        withdrawalQueue.findCheckpointHintBatch(requestIds, 1, 999);
    }

    // Binary Search Logic Tests

    function test_CheckpointHints_BinarySearchMultipleCheckpoints() public {
        // Create 5 requests and finalize each to create separate checkpoints
        uint256[] memory requestIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            requestIds[i] = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);
        }

        // Test finding hints for middle requests (should use binary search)
        uint256[] memory searchIds = new uint256[](3);
        searchIds[0] = requestIds[1]; // Request 2
        searchIds[1] = requestIds[2]; // Request 3
        searchIds[2] = requestIds[3]; // Request 4

        uint256[] memory hints =
            withdrawalQueue.findCheckpointHintBatch(searchIds, 1, withdrawalQueue.getLastCheckpointIndex());

        assertEq(hints[0], 2); // Request 2 → Checkpoint 2
        assertEq(hints[1], 3); // Request 3 → Checkpoint 3
        assertEq(hints[2], 4); // Request 4 → Checkpoint 4
    }

    function test_CheckpointHints_EdgeCaseBoundaries() public {
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        requestIds[1] = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        requestIds[2] = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        _finalizeRequests(3); // All requests in one checkpoint

        uint256[] memory hints =
            withdrawalQueue.findCheckpointHintBatch(requestIds, 1, withdrawalQueue.getLastCheckpointIndex());

        // All requests should point to the same checkpoint
        assertEq(hints[0], 1);
        assertEq(hints[1], 1);
        assertEq(hints[2], 1);
    }

    function test_CheckpointHints_RevertWhenRequestIdsNotSorted() public {
        uint256 firstRequest = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);
        uint256 secondRequest = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);
        assertLt(firstRequest, secondRequest);

        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = secondRequest;
        requestIds[1] = firstRequest;

        uint256 lastCheckpointIndex = withdrawalQueue.getLastCheckpointIndex();

        vm.expectRevert(WithdrawalQueue.RequestIdsNotSorted.selector);
        withdrawalQueue.findCheckpointHintBatch(requestIds, 1, lastCheckpointIndex);
    }

    function test_CheckpointHints_ReturnsZeroWhenOutsideRange() public {
        uint256[] memory finalizedRequests = new uint256[](3);
        for (uint256 i = 0; i < finalizedRequests.length; ++i) {
            finalizedRequests[i] = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);
        }

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = finalizedRequests[0];

        uint256[] memory hints = withdrawalQueue.findCheckpointHintBatch(requestIds, 2, 2);

        assertEq(hints[0], 0);
    }

    function test_FindCheckpointHint_ReturnsZeroWhenStartGreaterThanEnd() public {
        uint256 requestId = _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        uint256 lastIndex = withdrawalQueue.getLastCheckpointIndex();
        assertEq(lastIndex, 1);

        uint256 hint = withdrawalQueue.findCheckpointHint(requestId, lastIndex + 1, lastIndex);
        assertEq(hint, 0);
    }

    function test_FindCheckpointHint_RevertOnRequestBeyondLastId() public {
        _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        uint256 invalidRequestId = withdrawalQueue.getLastRequestId() + 1;
        uint256 startCheckpointIndex = 1;
        uint256 endCheckpointIndex = withdrawalQueue.getLastCheckpointIndex();

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.InvalidRequestId.selector, invalidRequestId));
        withdrawalQueue.findCheckpointHint(invalidRequestId, startCheckpointIndex, endCheckpointIndex);
    }

    // Receive ETH for tests
    receive() external payable {}
}
