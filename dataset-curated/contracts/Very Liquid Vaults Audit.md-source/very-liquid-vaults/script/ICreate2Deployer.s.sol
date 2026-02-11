// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ICreate2Deployer {
  function deploy(uint256 value, bytes32 salt, bytes memory code) external;
  function computeAddress(bytes32 salt, bytes32 codeHash) external view returns (address);
}
