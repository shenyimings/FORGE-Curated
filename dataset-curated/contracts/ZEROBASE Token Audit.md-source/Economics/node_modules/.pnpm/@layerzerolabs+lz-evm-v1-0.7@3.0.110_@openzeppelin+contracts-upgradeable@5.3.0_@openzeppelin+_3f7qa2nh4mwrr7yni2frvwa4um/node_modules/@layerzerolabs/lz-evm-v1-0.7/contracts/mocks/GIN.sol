// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;
pragma abicoder v2;
import "../interfaces/ILayerZeroReceiver.sol";
import "../interfaces/ILayerZeroEndpoint.sol";

contract GIN is ILayerZeroReceiver {
    bool public messageComplete;
    ILayerZeroEndpoint public endpoint;

    event Message(bytes32 indexed message);

    constructor(address _endpoint) {
        endpoint = ILayerZeroEndpoint(_endpoint);
    }

    function lzReceive(uint16, bytes memory /*_fromAddress*/, uint64, bytes memory _payload) external override {
        require(msg.sender == address(endpoint));
        bytes32 message;
        assembly {
            message := mload(add(_payload, 32))
        }
        emit Message(message);
        messageComplete = true;
    }

    function sendFirstMessage(
        uint gasAmountForDst,
        uint16[] calldata chainIds,
        bytes[] calldata dstAddresses
    ) external payable {
        require(!messageComplete, "The first message of LayerZero has already been sent");
        uint16 version = 1;
        bytes memory _relayerParams = abi.encodePacked(version, gasAmountForDst);

        bytes32 message = "GIN";
        bytes memory messageString = bytes(abi.encodePacked(message));
        uint length = chainIds.length;
        uint fee = msg.value / length;
        for (uint i = 0; i < length; i++) {
            endpoint.send{value: fee}(
                chainIds[i],
                dstAddresses[i],
                messageString,
                msg.sender,
                address(0x0),
                _relayerParams
            );
        }
    }
}
