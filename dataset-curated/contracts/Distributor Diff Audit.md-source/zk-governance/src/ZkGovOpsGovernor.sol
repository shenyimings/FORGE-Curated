// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorPreventLateQuorum} from "@openzeppelin/contracts/governance/extensions/GovernorPreventLateQuorum.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorCountingFractional} from "src/lib/GovernorCountingFractional.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {GovernorSettableFixedQuorum} from "src/extensions/GovernorSettableFixedQuorum.sol";
import {GovernorGuardianVeto} from "src/extensions/GovernorGuardianVeto.sol";

/// @title ZkGovOpsGovernor
/// @author [ScopeLift](https://scopelift.co)
/// @notice A Governance contract used to manage decisions that aren't covered by the token or protocol governors.
contract ZkGovOpsGovernor is
  GovernorCountingFractional,
  GovernorSettings,
  GovernorVotes,
  GovernorTimelockControl,
  GovernorPreventLateQuorum,
  GovernorSettableFixedQuorum,
  GovernorGuardianVeto
{
  /// @param name The name used as the EIP712 signing domain.
  /// @param token The token used for voting on proposals.
  /// @param timelock The timelock used for managing proposals.
  /// @param initialVotingDelay The delay before voting on a proposal begins.
  /// @param initialVotingPeriod The period of time voting will take place.
  /// @param initialProposalThreshold The number of tokens needed to create a proposal.
  /// @param initialQuorum The number of total votes needed to pass a proposal.
  /// @param initialVoteExtension The time to extend the voting period if quorum is met near the end of voting.
  /// @param vetoGuardian An immutable address that can cancel proposals when it is in either a pending or active
  /// state.
  struct ConstructorParams {
    string name;
    IVotes token;
    TimelockController timelock;
    uint48 initialVotingDelay;
    uint32 initialVotingPeriod;
    uint256 initialProposalThreshold;
    uint224 initialQuorum;
    uint64 initialVoteExtension;
    address vetoGuardian;
  }

  constructor(ConstructorParams memory _params)
    Governor(_params.name)
    GovernorSettings(_params.initialVotingDelay, _params.initialVotingPeriod, _params.initialProposalThreshold)
    GovernorVotes(_params.token)
    GovernorTimelockControl(_params.timelock)
    GovernorPreventLateQuorum(_params.initialVoteExtension)
    GovernorSettableFixedQuorum(_params.initialQuorum)
    GovernorGuardianVeto(_params.vetoGuardian)
  {}

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
  ) public virtual override(Governor, IGovernor, GovernorGuardianVeto) returns (uint256) {
    return GovernorGuardianVeto.cancel(_targets, _values, _calldatas, _descriptionHash);
  }

  /// @inheritdoc GovernorCountingFractional
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function castVoteWithReasonAndParamsBySig(
    uint256 _proposalId,
    uint8 _support,
    string calldata _reason,
    bytes memory _params,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) public override(Governor, GovernorCountingFractional, IGovernor) returns (uint256) {
    return
      GovernorCountingFractional.castVoteWithReasonAndParamsBySig(_proposalId, _support, _reason, _params, _v, _r, _s);
  }

  /// @inheritdoc GovernorPreventLateQuorum
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function proposalDeadline(uint256 _proposalId)
    public
    view
    virtual
    override(Governor, IGovernor, GovernorPreventLateQuorum)
    returns (uint256)
  {
    return GovernorPreventLateQuorum.proposalDeadline(_proposalId);
  }

  /// @inheritdoc GovernorSettings
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function proposalThreshold() public view virtual override(Governor, GovernorSettings) returns (uint256) {
    return GovernorSettings.proposalThreshold();
  }

  /// @inheritdoc GovernorTimelockControl
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function state(uint256 _proposalId)
    public
    view
    virtual
    override(Governor, GovernorTimelockControl)
    returns (IGovernor.ProposalState)
  {
    return GovernorTimelockControl.state(_proposalId);
  }

  /// @inheritdoc GovernorTimelockControl
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function supportsInterface(bytes4 _interfaceId)
    public
    view
    virtual
    override(Governor, GovernorTimelockControl)
    returns (bool)
  {
    return GovernorTimelockControl.supportsInterface(_interfaceId);
  }

  /// @inheritdoc GovernorTimelockControl
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _cancel(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal virtual override(Governor, GovernorTimelockControl) returns (uint256) {
    return GovernorTimelockControl._cancel(_targets, _values, _calldatas, _descriptionHash);
  }

  /// @inheritdoc GovernorPreventLateQuorum
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _castVote(uint256 _proposalId, address _account, uint8 _support, string memory _reason, bytes memory _params)
    internal
    virtual
    override(Governor, GovernorPreventLateQuorum)
    returns (uint256)
  {
    return GovernorPreventLateQuorum._castVote(_proposalId, _account, _support, _reason, _params);
  }

  /// @inheritdoc GovernorTimelockControl
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _execute(
    uint256 _proposalId,
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal virtual override(Governor, GovernorTimelockControl) {
    return GovernorTimelockControl._execute(_proposalId, _targets, _values, _calldatas, _descriptionHash);
  }

  /// @inheritdoc GovernorTimelockControl
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _executor() internal view virtual override(Governor, GovernorTimelockControl) returns (address) {
    return GovernorTimelockControl._executor();
  }
}
