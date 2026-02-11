// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

/**
 * @title CCIP OnRamp Mock
 * @notice Mocks CCIP onramp contract for testing
 */
contract CCIPOnRampMock {
    struct RequestData {
        uint256 feeTokenAmount;
        address originalSender;
    }

    mapping(address => address) public tokenPools;
    address public linkToken;

    Client.EVM2AnyMessage private lastRequestMessage;
    RequestData private lastRequestData;

    constructor(address[] memory _tokens, address[] memory _tokenPools, address _linkToken) {
        for (uint256 i = 0; i < _tokens.length; ++i) {
            tokenPools[_tokens[i]] = _tokenPools[i];
        }
        linkToken = _linkToken;
    }

    function getLastRequestMessage() external view returns (Client.EVM2AnyMessage memory) {
        return lastRequestMessage;
    }

    function getLastRequestData() external view returns (RequestData memory) {
        return lastRequestData;
    }

    function getFee(
        uint64,
        Client.EVM2AnyMessage calldata _message
    ) external view returns (uint256) {
        return _message.feeToken == linkToken ? 2 ether : 3 ether;
    }

    function getPoolBySourceToken(uint64, address _token) public view returns (address) {
        return tokenPools[_token];
    }

    function forwardFromRouter(
        uint64,
        Client.EVM2AnyMessage calldata _message,
        uint256 _feeTokenAmount,
        address _originalSender
    ) external returns (bytes32) {
        lastRequestMessage = _message;
        lastRequestData = RequestData(_feeTokenAmount, _originalSender);
        return keccak256(abi.encode(block.timestamp));
    }

    function setTokenPool(address _token, address _pool) external {
        tokenPools[_token] = _pool;
    }
}
