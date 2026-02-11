// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IL2StandardBridge {
    function withdrawMetisTo(
        address _to,
        uint256 _amount,
        uint32 _l1Gas,
        bytes calldata _data
    ) external payable;
}
