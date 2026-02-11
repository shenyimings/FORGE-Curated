// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {RateChangeQueue} from "../src/RateChangeQueue.sol";

contract RateChangeQueueTest is Test {
    using RateChangeQueue for RateChangeQueue.Queue;

    struct TestQueueContainer {
        RateChangeQueue.Queue queue;
    }

    TestQueueContainer private queueContainer;

    function queue() internal view returns (RateChangeQueue.Queue storage) {
        return queueContainer.queue;
    }

    function createEmptyQueue() internal {
        // Clear any existing data
        RateChangeQueue.Queue storage q = queue();
        while (!q.isEmpty()) {
            q.dequeue();
        }
    }

    function createSingleItemQueue(uint256 rate, uint256 untilEpoch)
        internal
        returns (RateChangeQueue.RateChange memory)
    {
        createEmptyQueue();
        RateChangeQueue.enqueue(queue(), rate, untilEpoch);
        assertEq(RateChangeQueue.size(queue()), 1);
        return RateChangeQueue.RateChange(rate, untilEpoch);
    }

    function createMultiItemQueue(uint256[] memory rates, uint256[] memory untilEpochs)
        internal
        returns (RateChangeQueue.RateChange[] memory)
    {
        require(rates.length == untilEpochs.length, "Input arrays must have same length");

        createEmptyQueue();

        RateChangeQueue.RateChange[] memory items = new RateChangeQueue.RateChange[](rates.length);

        for (uint256 i = 0; i < rates.length; i++) {
            RateChangeQueue.enqueue(queue(), rates[i], untilEpochs[i]);
            items[i] = RateChangeQueue.RateChange(rates[i], untilEpochs[i]);
        }

        assertEq(RateChangeQueue.size(queue()), rates.length);
        return items;
    }

    function createQueueWithAdvancedIndices(uint256 cycles) internal {
        createEmptyQueue();

        // Create cycles of filling and emptying
        for (uint256 i = 0; i < cycles; i++) {
            // Fill with 3 items
            RateChangeQueue.enqueue(queue(), 100 + i, 5 + i);
            RateChangeQueue.enqueue(queue(), 200 + i, 6 + i);
            RateChangeQueue.enqueue(queue(), 300 + i, 7 + i);

            // Empty
            RateChangeQueue.dequeue(queue());
            RateChangeQueue.dequeue(queue());
            RateChangeQueue.dequeue(queue());
        }

        // Queue should be empty now but with advanced indices
        assertTrue(RateChangeQueue.isEmpty(queue()));
    }

    function assertRateChangeEq(
        RateChangeQueue.RateChange memory actual,
        RateChangeQueue.RateChange memory expected,
        string memory message
    ) internal pure {
        assertEq(actual.rate, expected.rate, string.concat(message, " - rate mismatch"));
        assertEq(actual.untilEpoch, expected.untilEpoch, string.concat(message, " - untilEpoch mismatch"));
    }

    function testBasicQueueOperations() public {
        createEmptyQueue();

        RateChangeQueue.enqueue(queue(), 100, 5);
        assertEq(RateChangeQueue.size(queue()), 1);
        RateChangeQueue.enqueue(queue(), 200, 10);
        RateChangeQueue.enqueue(queue(), 300, 15);
        assertEq(RateChangeQueue.size(queue()), 3);

        // Verify peek (head) and peekTail operations
        RateChangeQueue.RateChange memory head = RateChangeQueue.peek(queue());
        assertRateChangeEq(head, RateChangeQueue.RateChange(100, 5), "Head should match first enqueued item");

        RateChangeQueue.RateChange memory tail = RateChangeQueue.peekTail(queue());
        assertRateChangeEq(tail, RateChangeQueue.RateChange(300, 15), "Tail should match last enqueued item");

        // Size should remain unchanged after peek operations
        assertEq(RateChangeQueue.size(queue()), 3);

        // Dequeue and verify FIFO order
        RateChangeQueue.RateChange memory first = RateChangeQueue.dequeue(queue());
        assertRateChangeEq(first, RateChangeQueue.RateChange(100, 5), "First dequeued item mismatch");
        assertEq(RateChangeQueue.size(queue()), 2);

        RateChangeQueue.RateChange memory second = RateChangeQueue.dequeue(queue());
        assertRateChangeEq(second, RateChangeQueue.RateChange(200, 10), "Second dequeued item mismatch");
        assertEq(RateChangeQueue.size(queue()), 1);

        RateChangeQueue.RateChange memory third = RateChangeQueue.dequeue(queue());
        assertRateChangeEq(third, RateChangeQueue.RateChange(300, 15), "Third dequeued item mismatch");

        // Queue should now be empty
        assertTrue(RateChangeQueue.isEmpty(queue()));
        assertEq(RateChangeQueue.size(queue()), 0);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testEmptyQueueDequeue() public {
        createEmptyQueue();

        // Test dequeue on empty queue
        vm.expectRevert("Queue is empty");
        RateChangeQueue.dequeue(queue());
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testEmptyQueuePeek() public {
        createEmptyQueue();

        // Test peek on empty queue
        vm.expectRevert("Queue is empty");
        RateChangeQueue.peek(queue());
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testEmptyQueuePeekTail() public {
        createEmptyQueue();

        // Test peekTail on empty queue
        vm.expectRevert("Queue is empty");
        RateChangeQueue.peekTail(queue());
    }

    function testBoundaryValues() public {
        // Test with zero values
        RateChangeQueue.RateChange memory zeroItem = createSingleItemQueue(0, 0);
        RateChangeQueue.RateChange memory peekedZero = RateChangeQueue.peek(queue());
        assertRateChangeEq(peekedZero, zeroItem, "Zero values not stored correctly");
        RateChangeQueue.dequeue(queue());

        // Test with max uint values
        uint256 maxUint = type(uint256).max;
        RateChangeQueue.RateChange memory maxItem = createSingleItemQueue(maxUint, maxUint);
        RateChangeQueue.RateChange memory peekedMax = RateChangeQueue.peek(queue());
        assertRateChangeEq(peekedMax, maxItem, "Max values not stored correctly");
    }

    function testQueueReusability() public {
        // Test emptying and reusing a queue
        createSingleItemQueue(100, 5);
        RateChangeQueue.dequeue(queue());
        assertTrue(RateChangeQueue.isEmpty(queue()));

        // Reuse after emptying
        RateChangeQueue.enqueue(queue(), 200, 10);
        assertEq(RateChangeQueue.size(queue()), 1);

        RateChangeQueue.RateChange memory peeked = RateChangeQueue.peek(queue());
        assertRateChangeEq(peeked, RateChangeQueue.RateChange(200, 10), "Queue reuse failed");

        // Test with advanced indices
        RateChangeQueue.dequeue(queue());
        createQueueWithAdvancedIndices(10);

        // Verify queue still functions correctly after index cycling
        RateChangeQueue.enqueue(queue(), 999, 999);
        assertEq(RateChangeQueue.size(queue()), 1);

        peeked = RateChangeQueue.peek(queue());
        assertRateChangeEq(peeked, RateChangeQueue.RateChange(999, 999), "Queue with advanced indices failed");
    }

    function testMixedOperations() public {
        createEmptyQueue();

        // Series of mixed enqueue/dequeue operations
        RateChangeQueue.enqueue(queue(), 100, 5);
        RateChangeQueue.enqueue(queue(), 200, 10);

        RateChangeQueue.RateChange memory first = RateChangeQueue.dequeue(queue());
        assertRateChangeEq(first, RateChangeQueue.RateChange(100, 5), "First dequeue failed");

        RateChangeQueue.enqueue(queue(), 300, 15);
        RateChangeQueue.enqueue(queue(), 400, 20);

        assertEq(RateChangeQueue.size(queue()), 3, "Queue size incorrect after mixed operations");

        // Verify peek at both ends
        RateChangeQueue.RateChange memory head = RateChangeQueue.peek(queue());
        assertRateChangeEq(head, RateChangeQueue.RateChange(200, 10), "Head incorrect after mixed operations");

        RateChangeQueue.RateChange memory tail = RateChangeQueue.peekTail(queue());
        assertRateChangeEq(tail, RateChangeQueue.RateChange(400, 20), "Tail incorrect after mixed operations");

        // Empty the queue
        RateChangeQueue.dequeue(queue());
        RateChangeQueue.dequeue(queue());
        RateChangeQueue.dequeue(queue());

        assertTrue(RateChangeQueue.isEmpty(queue()), "Queue should be empty after all dequeues");
    }
}
