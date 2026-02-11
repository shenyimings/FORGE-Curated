// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// solhint-disable one-contract-per-file
// solhint-disable gas-custom-errors

import {ILayerZeroEndpointV2} from "../interfaces/layerzero/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "../interfaces/layerzero/ILayerZeroReceiver.sol";

contract MockLayerZeroEndpoint {
    uint256 public constant FEE = 0.001 ether;
    bool public dispatched;
    mapping(address => address) public delegates;

    function send(
        ILayerZeroEndpointV2.MessagingParams calldata params,
        address refundAddress
    ) external payable returns (ILayerZeroEndpointV2.MessagingReceipt memory) {
        if (msg.value < FEE) revert("Insufficient fee");
        dispatched = true;

        // Refund excess
        if (msg.value > FEE) {
            (bool success, ) = refundAddress.call{value: msg.value - FEE}("");
            if (!success) revert("Refund failed");
        }

        return
            ILayerZeroEndpointV2.MessagingReceipt({
                guid: keccak256(abi.encode(params, block.timestamp)),
                nonce: 1,
                fee: ILayerZeroEndpointV2.MessagingFee({
                    nativeFee: FEE,
                    lzTokenFee: 0
                })
            });
    }

    function quote(
        ILayerZeroEndpointV2.MessagingParams calldata /* params */,
        address /* sender */
    ) external pure returns (ILayerZeroEndpointV2.MessagingFee memory) {
        return
            ILayerZeroEndpointV2.MessagingFee({nativeFee: FEE, lzTokenFee: 0});
    }

    function setDelegate(address delegate) external {
        delegates[msg.sender] = delegate;
    }
}

contract TestLayerZeroEndpoint is MockLayerZeroEndpoint {
    address public receiver;

    function setReceiver(address _receiver) external {
        receiver = _receiver;
    }

    function simulateReceive(
        uint32 srcEid,
        bytes32 sender,
        bytes calldata message
    ) external {
        ILayerZeroReceiver(receiver).lzReceive(
            ILayerZeroReceiver.Origin({
                srcEid: srcEid,
                sender: sender,
                nonce: 1
            }),
            bytes32(0),
            message,
            address(0),
            ""
        );
    }
}
