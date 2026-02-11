// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;
pragma abicoder v2;

contract CounterV {
    // keep track of how many messages have been received from other chains
    uint public totalCount;
    mapping(uint32 => uint) public inboundCount;
    mapping(uint32 => uint) public outboundCount;

    event Send(uint16 dstChainId);
    event Receive(uint16 srcChainId);

    uint16 public chainId;

    constructor(uint16 _chainId) {
        chainId = _chainId;
    }

    function lzReceive(uint16 _srcChainId) external {
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

    function getInboundNonce(uint16 _chainId) public view returns (uint64) {
        // in reality, this would be a call to the LayerZero endpoint
        return uint64(inboundCount[_chainId]);
    }
}
