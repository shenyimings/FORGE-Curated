// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;
pragma abicoder v2;

import "./CounterV.sol";

contract CounterView {
    struct CountState {
        uint totalCount;
        ChainPathCount[] chainPathCounts;
    }

    struct ChainPathCount {
        uint16 eid;
        uint inboundCount;
        uint outboundCount;
    }

    CounterV public counter;

    constructor(address _counter) {
        counter = CounterV(_counter);
    }

    function lzReceive(CountState memory countState, uint16 _srcChainId) public pure returns (CountState memory) {
        // do receive logic
        for (uint i = 0; i < countState.chainPathCounts.length; i++) {
            ChainPathCount memory chainPathCount = countState.chainPathCounts[i];
            if (chainPathCount.eid == _srcChainId) {
                countState.totalCount++;
                chainPathCount.inboundCount++;
                countState.chainPathCounts[i] = chainPathCount;
                break;
            }
        }
        return countState;
    }

    /**
     * @notice Get the count states for a list of peers
     * @param peers - the list of remote chainId to get counts for
     * @return counts - the CountState with the total count and the chain path counts
     */
    function getCountState(uint16[] calldata peers) public view returns (CountState memory) {
        ChainPathCount[] memory chainPathCounts = new ChainPathCount[](peers.length);

        for (uint i = 0; i < peers.length; i++) {
            uint16 peer = peers[i];
            chainPathCounts[i] = ChainPathCount({
                eid: peer,
                inboundCount: counter.inboundCount(peer),
                outboundCount: counter.outboundCount(peer)
            });
        }

        CountState memory countState = CountState({totalCount: counter.totalCount(), chainPathCounts: chainPathCounts});

        return countState;
    }
}
