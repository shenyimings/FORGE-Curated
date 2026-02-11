// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Sickle } from "contracts/Sickle.sol";

interface IFeesLib {
    event FeeCharged(
        address strategy, bytes4 feeDescriptor, uint256 amount, address token
    );
    event TransactionCostCharged(address recipient, uint256 amount);

    function chargeFee(
        address strategy,
        bytes4 feeDescriptor,
        address feeToken,
        uint256 feeBasis
    ) external payable returns (uint256 remainder);

    function chargeFees(
        address strategy,
        bytes4 feeDescriptor,
        address[] memory feeTokens
    ) external payable;

    function getBalance(
        Sickle sickle,
        address token
    ) external view returns (uint256);
}
