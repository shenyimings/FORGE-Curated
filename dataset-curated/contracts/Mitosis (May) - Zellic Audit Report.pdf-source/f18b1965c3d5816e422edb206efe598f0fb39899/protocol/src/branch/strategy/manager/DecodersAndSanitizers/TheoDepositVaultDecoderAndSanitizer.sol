// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseDecoderAndSanitizer } from './BaseDecoderAndSanitizer.sol';

contract TheoDepositVaultDecoderAndSanitizer is BaseDecoderAndSanitizer {
  function depositETH() external pure returns (bytes memory addressesFound) {
    return addressesFound;
  }

  function deposit(uint256) external pure returns (bytes memory addressesFound) {
    return addressesFound;
  }

  function depositFor(uint256, address creditor) external pure returns (bytes memory addressesFound) {
    addressesFound = abi.encodePacked(creditor);
  }

  function depositETHFor(address creditor) external pure returns (bytes memory addressesFound) {
    addressesFound = abi.encodePacked(creditor);
  }

  function privateDepositETH(bytes32[] memory) external pure returns (bytes memory addressesFound) {
    return addressesFound;
  }

  function privateDeposit(uint256, bytes32[] memory) external pure returns (bytes memory addressesFound) {
    return addressesFound;
  }

  function withdrawInstantly(uint256) external pure returns (bytes memory addressesFound) {
    return addressesFound;
  }

  function initiateWithdraw(uint256) external pure returns (bytes memory addressesFound) {
    return addressesFound;
  }

  function completeWithdraw() external pure returns (bytes memory addressesFound) {
    return addressesFound;
  }

  function redeem(uint256) external pure returns (bytes memory addressesFound) {
    return addressesFound;
  }

  function maxRedeem() external pure returns (bytes memory addressesFound) {
    return addressesFound;
  }
}
