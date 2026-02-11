// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IGovernorTimelock} from "@openzeppelin/contracts/governance/extensions/IGovernorTimelock.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

abstract contract ProposalTest is Test {
  IGovernorTimelock private governor;

  address[] public delegates;

  enum VoteType {
    Against,
    For,
    Abstain
  }

  function _setGovernor(IGovernorTimelock _governor) internal {
    governor = _governor;
  }

  function _setDelegates(address[] memory _delegates) internal {
    delegates = _delegates;
  }

  function _setDelegates(address _delegate) internal {
    delegates.push(_delegate);
  }

  function _proposalSnapshot(uint256 _proposalId) internal view returns (uint256) {
    return governor.proposalSnapshot(_proposalId);
  }

  function _proposalDeadline(uint256 _proposalId) internal view returns (uint256) {
    return governor.proposalDeadline(_proposalId);
  }

  function _proposalEta(uint256 _proposal) internal view returns (uint256) {
    return governor.proposalEta(_proposal);
  }

  function _jumpToActiveProposal(uint256 _proposalId) internal {
    vm.warp(_proposalSnapshot(_proposalId) + 1);
  }

  function _jumpToVoteComplete(uint256 _proposalId) internal {
    vm.warp(_proposalDeadline(_proposalId));
  }

  function _jumpPastVoteComplete(uint256 _proposalId) internal {
    vm.warp(_proposalDeadline(_proposalId) + 1);
  }

  function _jumpPastProposalEta(uint256 _proposalId) internal {
    vm.warp(_proposalEta(_proposalId) + 1);
  }

  function _delegatesVote(uint256 _proposalId, uint8 _support) internal {
    console2.logUint(delegates.length);
    for (uint256 _index = 0; _index < delegates.length; _index++) {
      console2.logUint(_index);
      vm.prank(delegates[_index]);
      governor.castVote(_proposalId, _support);
    }
  }

  function _passProposal(uint256 _proposalId) internal {
    _jumpToActiveProposal(_proposalId);
    _delegatesVote(_proposalId, 1); // support
    _jumpPastVoteComplete(_proposalId);
  }

  function _propose(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    string memory _description
  ) internal returns (uint256) {
    vm.prank(delegates[0]);
    uint256 _proposalId = governor.propose(_targets, _values, _calldatas, _description);

    IGovernorTimelock.ProposalState _state = governor.state(_proposalId);
    assertEq(uint8(_state), uint8(IGovernor.ProposalState.Pending));
    return _proposalId;
  }

  function _queueAndVoteAndExecuteProposal(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    string memory _description,
    uint8 _voteType
  ) internal {
    uint256 _proposalId = _propose(_targets, _values, _calldatas, _description);
    _jumpToActiveProposal(_proposalId);

    _delegatesVote(_proposalId, _voteType);
    _jumpPastVoteComplete(_proposalId);

    if (_voteType == 0 || _voteType == 2) {
      return;
    }

    governor.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));

    _jumpPastProposalEta(_proposalId);
    governor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));
  }
}
