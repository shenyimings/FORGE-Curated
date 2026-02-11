// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

interface IStrategyCallForwarder {
    function initialize(address _owner) external;
    function doCall(address _target, bytes calldata _data) external returns (bytes memory);
    function doCallWithValue(address _target, bytes calldata _data, uint256 _value) external returns (bytes memory);
    function sendValue(address payable _recipient, uint256 _amount) external;
    function safeTransferERC20(address _token, address _recipient, uint256 _amount) external;
}
