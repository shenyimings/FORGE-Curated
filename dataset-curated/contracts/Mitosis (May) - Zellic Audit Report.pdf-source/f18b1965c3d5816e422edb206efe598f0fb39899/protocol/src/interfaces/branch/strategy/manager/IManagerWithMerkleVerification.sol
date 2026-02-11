// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IManagerWithMerkleVerification {
  event ManageRootUpdated(
    address indexed strategyExecutor, address indexed strategist, bytes32 oldRoot, bytes32 newRoot
  );
  event StrategyExecutorExecuted(address indexed strategyExecutor, uint256 callsMade);

  error IManagerWithMerkleVerification__InvalidManageProofLength();
  error IManagerWithMerkleVerification__InvalidTargetDataLength();
  error IManagerWithMerkleVerification__InvalidValuesLength();
  error IManagerWithMerkleVerification__InvalidDecodersAndSanitizersLength();

  error IManagerWithMerkleVerification__FailedToVerifyManageProof(address target, bytes targetData, uint256 value);

  function manageRoot(address strategyExecutor, address strategist) external view returns (bytes32);
  function setManageRoot(address strategyExecutor, address strategist, bytes32 _manageRoot) external;
  function manageVaultWithMerkleVerification(
    address strategyExecutor,
    bytes32[][] calldata manageProofs,
    address[] calldata decodersAndSanitizers,
    address[] calldata targets,
    bytes[] calldata targetData,
    uint256[] calldata values
  ) external;
}
