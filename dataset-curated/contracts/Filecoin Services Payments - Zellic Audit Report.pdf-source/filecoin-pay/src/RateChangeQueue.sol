// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.27;

library RateChangeQueue {
    struct RateChange {
        // The payment rate to apply
        uint256 rate;
        // The epoch up to and including which this rate will be used to settle a rail
        uint256 untilEpoch;
    }

    struct Queue {
        uint256 head;
        RateChange[] changes;
    }

    function enqueue(Queue storage queue, uint256 rate, uint256 untilEpoch) internal {
        queue.changes.push(RateChange(rate, untilEpoch));
    }

    function dequeue(Queue storage queue) internal returns (RateChange memory) {
        RateChange[] storage c = queue.changes;
        require(queue.head < c.length, "Queue is empty");
        RateChange memory change = c[queue.head];
        delete c[queue.head];

        if (isEmpty(queue)) {
            queue.head = 0;
            // The array is already empty, waste no time zeroing it.
            assembly {
                sstore(c.slot, 0)
            }
        } else {
            queue.head++;
        }

        return change;
    }

    function peek(Queue storage queue) internal view returns (RateChange memory) {
        require(queue.head < queue.changes.length, "Queue is empty");
        return queue.changes[queue.head];
    }

    function peekTail(Queue storage queue) internal view returns (RateChange memory) {
        require(queue.head < queue.changes.length, "Queue is empty");
        return queue.changes[queue.changes.length - 1];
    }

    function isEmpty(Queue storage queue) internal view returns (bool) {
        return queue.head == queue.changes.length;
    }

    function size(Queue storage queue) internal view returns (uint256) {
        return queue.changes.length - queue.head;
    }
}
