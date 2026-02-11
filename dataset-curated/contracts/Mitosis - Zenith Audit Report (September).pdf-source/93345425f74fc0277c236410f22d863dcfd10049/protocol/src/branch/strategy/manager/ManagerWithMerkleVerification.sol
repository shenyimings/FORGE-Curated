// SPDX-License-Identifier: Apache-2.0
// Based on https://github.com/Se7en-Seas/boring-vault
pragma solidity ^0.8.28;

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { Address } from '@openzeppelin/contracts/utils/Address.sol';

import { MerkleProofLib } from '@solmate/utils/MerkleProofLib.sol';

import { IStrategyExecutor } from '../../../interfaces/branch/strategy/IStrategyExecutor.sol';
import { IManagerWithMerkleVerification } from
  '../../../interfaces/branch/strategy/manager/IManagerWithMerkleVerification.sol';
import { StdError } from '../../../lib/StdError.sol';
import { Versioned } from '../../../lib/Versioned.sol';
import { ManagerWithMerkleVerificationStorageV1 } from './ManagerWithMerkleVerificationStorageV1.sol';

contract ManagerWithMerkleVerification is
  IManagerWithMerkleVerification,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  ManagerWithMerkleVerificationStorageV1,
  Versioned
{
  using Address for address;

  constructor() {
    _disableInitializers();
  }

  function initialize(address owner_) public initializer {
    __Ownable2Step_init();
    __Ownable_init(owner_);
    __UUPSUpgradeable_init();
  }

  function manageRoot(address strategyExecutor, address strategist) external view returns (bytes32) {
    return _getStorageV1().manageRoot[strategyExecutor][strategist];
  }

  function setManageRoot(address strategyExecutor, address strategist, bytes32 _manageRoot) external onlyOwner {
    StorageV1 storage $ = _getStorageV1();
    bytes32 oldRoot = $.manageRoot[strategyExecutor][strategist];
    $.manageRoot[strategyExecutor][strategist] = _manageRoot;
    emit ManageRootUpdated(strategyExecutor, strategist, oldRoot, _manageRoot);
  }

  function manage(
    address strategyExecutor,
    bytes32[][] calldata manageProofs,
    address[] calldata decodersAndSanitizers,
    address[] calldata targets,
    bytes[] calldata targetData,
    uint256[] calldata values
  ) external {
    StorageV1 storage $ = _getStorageV1();

    uint256 targetsLength = targets.length;
    require(targetsLength == manageProofs.length, IManagerWithMerkleVerification__InvalidManageProofLength());
    require(targetsLength == targetData.length, IManagerWithMerkleVerification__InvalidTargetDataLength());
    require(targetsLength == values.length, IManagerWithMerkleVerification__InvalidValuesLength());
    require(
      targetsLength == decodersAndSanitizers.length,
      IManagerWithMerkleVerification__InvalidDecodersAndSanitizersLength()
    );

    bytes32 strategistManageRoot = $.manageRoot[strategyExecutor][_msgSender()];
    require(strategistManageRoot != 0, StdError.NotFound('manageProof'));

    for (uint256 i; i < targetsLength; ++i) {
      _verifyCallData(
        strategistManageRoot, manageProofs[i], decodersAndSanitizers[i], targets[i], values[i], targetData[i]
      );
      IStrategyExecutor(strategyExecutor).execute(targets[i], targetData[i], values[i]);
    }

    emit StrategyExecutorExecuted(strategyExecutor, targetsLength);
  }

  function _verifyCallData(
    bytes32 currentManageRoot,
    bytes32[] calldata manageProof,
    address decoderAndSanitizer,
    address target,
    uint256 value,
    bytes calldata targetData
  ) internal view {
    // Use address decoder to get addresses in call data.
    bytes memory packedArgumentAddresses = abi.decode(decoderAndSanitizer.functionStaticCall(targetData), (bytes));

    if (
      !_verifyManageProof(
        currentManageRoot, manageProof, target, decoderAndSanitizer, value, bytes4(targetData), packedArgumentAddresses
      )
    ) {
      revert IManagerWithMerkleVerification.IManagerWithMerkleVerification__FailedToVerifyManageProof(
        target, targetData, value
      );
    }
  }

  /**
   * @notice Helper function to verify a manageProof is valid.
   */
  function _verifyManageProof(
    bytes32 root,
    bytes32[] calldata proof,
    address target,
    address decoderAndSanitizer,
    uint256 value,
    bytes4 selector,
    bytes memory packedArgumentAddresses
  ) internal pure returns (bool) {
    bool valueNonZero = value > 0;
    bytes32 leaf =
      keccak256(abi.encodePacked(decoderAndSanitizer, target, valueNonZero, selector, packedArgumentAddresses));
    return MerkleProofLib.verify(proof, root, leaf);
  }

  function _authorizeUpgrade(address) internal override onlyOwner { }
}
