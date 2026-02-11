// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouter} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouter.sol";

interface ITokenPool {
    function token() external view returns (address);

    function releaseOrMint(address _receiver, uint256 _amount) external;
}

/**
 * @title CCIP OffRamp Mock
 * @notice Mocks CCIP offramp contract for testing
 */
contract CCIPOffRampMock {
    uint16 private constant GAS_FOR_CALL_EXACT_CHECK = 5_000;

    IRouter public router;
    mapping(address => ITokenPool) public tokenPools;

    constructor(address _router, address[] memory _tokens, address[] memory _tokenPools) {
        router = IRouter(_router);
        for (uint256 i = 0; i < _tokens.length; ++i) {
            tokenPools[_tokens[i]] = ITokenPool(_tokenPools[i]);
        }
    }

    function executeSingleMessage(
        bytes32 _messageId,
        uint64 _sourceChainSelector,
        bytes calldata _data,
        address _receiver,
        Client.EVMTokenAmount[] calldata _tokenAmounts
    ) external returns (bool) {
        for (uint256 i = 0; i < _tokenAmounts.length; ++i) {
            tokenPools[_tokenAmounts[i].token].releaseOrMint(_receiver, _tokenAmounts[i].amount);
        }

        (bool success, , ) = router.routeMessage(
            Client.Any2EVMMessage(
                _messageId,
                _sourceChainSelector,
                abi.encode(msg.sender),
                _data,
                _tokenAmounts
            ),
            GAS_FOR_CALL_EXACT_CHECK,
            10000000,
            _receiver
        );
        return success;
    }

    function setTokenPool(address _token, address _pool) external {
        tokenPools[_token] = ITokenPool(_pool);
    }
}
