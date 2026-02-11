// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILendingConnector {
    function mint(
        address target,
        uint256 amount,
        bytes memory extraData
    ) external payable;

    function redeem(
        address target,
        uint256 amount,
        bytes memory extraData
    ) external;

    function redeemUnderlying(
        address target,
        uint256 amount,
        bytes memory extraData
    ) external;

    function borrow(
        address target,
        uint256 amount,
        bytes memory extraData
    ) external payable;

    function repay(
        address target,
        uint256 amount,
        bytes memory extraData
    ) external payable;

    function repayFor(
        address target,
        address borrower,
        uint256 amount,
        bytes memory extraData
    ) external payable;
}
