// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ZkProtocolGovernor} from "src/ZkProtocolGovernor.sol";

contract ZkProtocolGovernorTest is Test {}

contract Constructor is ZkProtocolGovernorTest {
  function testFuzz_CorrectlySetContructor(
    string memory _name,
    address _token,
    address payable _timelock,
    uint48 _votingDelay,
    uint32 _votingPeriod,
    uint256 _proposalThreshold,
    uint224 _initialQuorum,
    uint64 _voteExtension
  ) public {
    vm.assume(_votingPeriod != 0);
    ZkProtocolGovernor governor = new ZkProtocolGovernor(
      _name,
      IVotes(_token),
      TimelockController(_timelock),
      _votingDelay,
      _votingPeriod,
      _proposalThreshold,
      _initialQuorum,
      _voteExtension
    );

    assertEq(governor.name(), _name);
    assertEq(address(governor.token()), _token);
    assertEq(address(governor.timelock()), _timelock);
    assertEq(governor.votingDelay(), _votingDelay);
    assertEq(governor.votingPeriod(), _votingPeriod);
    assertEq(governor.proposalThreshold(), _proposalThreshold);
    assertEq(governor.quorum(block.timestamp), _initialQuorum);
    assertEq(governor.lateQuorumVoteExtension(), _voteExtension);
  }
}
