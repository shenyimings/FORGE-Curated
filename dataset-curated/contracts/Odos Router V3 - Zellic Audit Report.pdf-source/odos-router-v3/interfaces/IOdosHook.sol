// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IOdosHook {
  function executeOdosHook (
    bytes calldata hookData,
    uint256[] memory inputAmounts,
    address msgSender
  ) external;
}
