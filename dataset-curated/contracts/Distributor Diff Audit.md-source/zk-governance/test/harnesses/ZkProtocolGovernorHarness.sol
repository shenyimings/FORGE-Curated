// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ZkProtocolGovernor} from "src/ZkProtocolGovernor.sol";

contract ZkProtocolGovernorHarness is ZkProtocolGovernor {
  constructor(
    string memory _name,
    IVotes _token,
    TimelockController _timelock,
    uint48 _initialVotingDelay,
    uint32 _initialVotingPeriod,
    uint256 _initialProposalThreshold,
    uint224 _initialQuorum,
    uint64 _initialVoteExtension
  )
    ZkProtocolGovernor(
      _name,
      _token,
      _timelock,
      _initialVotingDelay,
      _initialVotingPeriod,
      _initialProposalThreshold,
      _initialQuorum,
      _initialVoteExtension
    )
  {}

  function exposed_setQuorum(uint224 _quorum) external {
    _setQuorum(_quorum);
  }
}
