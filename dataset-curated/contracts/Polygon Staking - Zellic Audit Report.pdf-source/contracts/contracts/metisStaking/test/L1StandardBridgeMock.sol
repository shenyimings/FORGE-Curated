// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title L1 Standard Bridge Mock
 * @dev Mocks contract for testing
 */
contract L1StandardBridgeMock {
    using SafeERC20 for IERC20;

    struct LastTransfer {
        uint256 chainid;
        address _l1Token;
        address l2Token;
        address to;
        uint256 amount;
        uint32 l2Gas;
        bytes data;
    }

    LastTransfer public lastTransfer;

    IERC20 public token;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function depositERC20ToByChainId(
        uint256 _chainid,
        address _l1Token,
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _l2Gas,
        bytes calldata _data
    ) external payable {
        token.safeTransferFrom(msg.sender, address(this), _amount);
        lastTransfer = LastTransfer(_chainid, _l1Token, _l2Token, _to, _amount, _l2Gas, _data);
    }
}
