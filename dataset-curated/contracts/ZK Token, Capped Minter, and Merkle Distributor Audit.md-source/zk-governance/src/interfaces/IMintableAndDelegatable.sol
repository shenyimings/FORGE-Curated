// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMintable} from "src/interfaces/IMintable.sol";

interface IMintableAndDelegatable is IMintable {
  function DOMAIN_SEPARATOR() external view returns (bytes32);
  function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external;
  function delegates(address account) external view returns (address);
}
