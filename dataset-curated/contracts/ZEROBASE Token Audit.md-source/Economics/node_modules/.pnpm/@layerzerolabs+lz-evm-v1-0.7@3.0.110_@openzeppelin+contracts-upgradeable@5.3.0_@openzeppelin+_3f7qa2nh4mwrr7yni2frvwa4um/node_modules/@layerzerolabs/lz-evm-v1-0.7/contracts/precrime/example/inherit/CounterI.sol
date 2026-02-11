// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;
pragma abicoder v2;

import "./CounterPrecrime.sol";

contract CounterI is CounterPrecrime {
    // keep track of how many messages have been received from other chains
    uint public totalCount;
    mapping(uint32 => uint) public inboundCount;
    mapping(uint32 => uint) public outboundCount;

    event Send(uint16 dstChainId);
    event Receive(uint16 srcChainId);

    uint16 public chainId;

    constructor(uint16 _chainId) CounterPrecrime(_chainId) {
        chainId = _chainId;
    }

    function lzReceive(uint16 _srcChainId) public {
        inboundCount[_srcChainId]++;
        totalCount++;

        emit Receive(_srcChainId);
    }

    function increment(uint16 _dstChainId) external {
        outboundCount[_dstChainId]++;

        emit Send(_dstChainId);
    }

    function brokeIncrement(uint16 _dstChainId) external {
        emit Send(_dstChainId);
    }

    function brokeTotalCount() external {
        totalCount++;
    }

    function getInboundNonce(uint32 _chainId) public view returns (uint) {
        // in reality, this would be a call to the LayerZero endpoint
        return inboundCount[_chainId];
    }

    // ------------- precrime -----------------
    function _lzReceiveByPacket(Packet calldata _packet) internal virtual override {
        lzReceive(uint16(_packet.srcChainId));
    }

    function getCountState(uint16[] memory peers) public view virtual override returns (CountState memory) {
        ChainPathCount[] memory chainPathCounts = new ChainPathCount[](peers.length);
        for (uint i = 0; i < peers.length; i++) {
            uint16 peer = peers[i];
            chainPathCounts[i] = ChainPathCount({
                eid: peer,
                inboundCount: inboundCount[peer],
                outboundCount: outboundCount[peer]
            });
        }

        CountState memory countState = CountState({totalCount: totalCount, chainPathCounts: chainPathCounts});

        return countState;
    }

    function _getInboundNonce(Packet memory packet) internal view override returns (uint64) {
        // in reality, this would be a call to the LayerZero endpoint
        return uint64(inboundCount[packet.srcChainId]);
    }
}
