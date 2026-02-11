// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IL1StandardBridge {
    function depositERC20ToByChainId(
        uint256 _chainid,
        address _l1Token,
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _l2Gas,
        bytes calldata _data
    ) external payable;
}
