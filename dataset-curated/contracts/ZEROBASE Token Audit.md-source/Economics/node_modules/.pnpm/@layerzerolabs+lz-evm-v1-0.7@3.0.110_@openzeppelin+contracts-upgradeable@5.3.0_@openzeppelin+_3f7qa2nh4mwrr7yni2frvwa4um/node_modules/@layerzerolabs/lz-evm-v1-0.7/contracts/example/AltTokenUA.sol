// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ILayerZeroEndpoint.sol";
import "../interfaces/ILayerZeroReceiver.sol";

// An example UA running on Shrapnel using ERC20 as payment token
// To demonstrate how feeToken payment needs to be atomic with layerzero send
contract AltTokenUA is ILayerZeroReceiver {
    ILayerZeroEndpoint public endpoint;
    IERC20 public feeToken;
    address public feeHandler;

    constructor(address _endpoint, address _feeToken, address _feeHandler) {
        endpoint = ILayerZeroEndpoint(_endpoint);
        feeToken = IERC20(_feeToken);
        feeHandler = _feeHandler;
    }

    function send(
        uint16 _dstChainId,
        address _dstAddress,
        bytes memory _payload,
        bytes memory _adapterParams,
        uint _fee
    ) public payable {
        feeToken.transferFrom(msg.sender, feeHandler, _fee);

        bytes memory path = abi.encodePacked(_dstAddress, address(this));
        endpoint.send(_dstChainId, path, _payload, msg.sender, address(0), _adapterParams);
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes memory _fromAddress,
        uint64 /*_nonce*/,
        bytes memory _payload
    ) external virtual override {
        //do nothing
    }
}
