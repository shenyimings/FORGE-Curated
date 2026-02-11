// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";

abstract contract GovernorGuardianVeto is Governor {
  /// @notice An immutable address which can cancel proposals while they are pending or active.
  address public immutable VETO_GUARDIAN;

  /// @notice An immutable address which can cancel proposals while they are pending or active.
  error UncancelableProposalState();

  /// @notice Thrown if an address tries to perform an action for which it is not authorized.
  error Unauthorized();

  /// @param _vetoGuardian The address to set as the immutable `VETO_GUARDIAN`.
  constructor(address _vetoGuardian) {
    VETO_GUARDIAN = _vetoGuardian;
  }

  /// @notice This function will cancel a proposal, and can only be called by the guardian while the proposal is either
  /// pending or active.
  /// @param _targets A list of contracts to call when a proposal is executed.
  /// @param _values A list of values to send when calling each target.
  /// @param _calldatas A list of calldatas to use when calling the targets.
  /// @param _descriptionHash A hash of the proposal description.
  function cancel(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) public virtual override returns (uint256) {
    if (msg.sender != VETO_GUARDIAN) {
      revert Unauthorized();
    }
    uint256 proposalId = hashProposal(_targets, _values, _calldatas, _descriptionHash);

    ProposalState proposalState = state(proposalId);

    if (proposalState != ProposalState.Active && proposalState != ProposalState.Pending) {
      revert UncancelableProposalState();
    }
    return _cancel(_targets, _values, _calldatas, _descriptionHash);
  }
}
