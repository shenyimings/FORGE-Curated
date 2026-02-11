// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ITransferLib {
    error ArrayLengthMismatch();
    error TokenInRequired();
    error AmountInRequired();
    error TwoTokenMaximum();
    error SameTokenIn();
    error TokenOutRequired();

    function transferTokenToUser(
        address token
    ) external payable;

    function transferTokensToUser(
        address[] memory tokens
    ) external payable;

    function transferTokenFromUser(
        address tokenIn,
        uint256 amountIn,
        address strategy,
        bytes4 feeSelector
    ) external payable;

    function transferTokensFromUser(
        address[] memory tokensIn,
        uint256[] memory amountsIn,
        address strategy,
        bytes4 feeSelector
    ) external payable;
}
