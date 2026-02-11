// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IBridgeAdapter } from "../../src/coordinator/BaseBridgeCoordinator.sol";

contract MockBridgeAdapter is IBridgeAdapter {
    uint16 private immutable _bridgeType;
    address private immutable _coordinator;

    struct BridgeCallParams {
        uint256 chainId;
        bytes32 remoteAdapter;
        bytes message;
        address refundAddress;
        bytes bridgeParams;
    }

    BridgeCallParams public lastBridgeCall;
    bytes32 public messageId;

    constructor(uint16 bridgeType_, address coordinator_) {
        _bridgeType = bridgeType_;
        _coordinator = coordinator_;
    }

    function returnMessageId(bytes32 messageId_) external {
        messageId = messageId_;
    }

    function bridge(
        uint256 chainId,
        bytes32 remoteAdapter,
        bytes calldata message,
        address refundAddress,
        bytes calldata bridgeParams
    )
        external
        payable
        returns (bytes32)
    {
        require(msg.value == estimateBridgeFee(chainId, message, bridgeParams), "Incorrect fee sent");
        lastBridgeCall = BridgeCallParams({
            chainId: chainId,
            remoteAdapter: remoteAdapter,
            message: message,
            refundAddress: refundAddress,
            bridgeParams: bridgeParams
        });
        return messageId;
    }

    function estimateBridgeFee(uint256, bytes calldata, bytes calldata) public pure returns (uint256 nativeFee) {
        return 1 ether; // flat fee for testing
    }

    function bridgeType() external view returns (uint16) {
        return _bridgeType;
    }

    function bridgeCoordinator() external view returns (address) {
        return _coordinator;
    }
}
