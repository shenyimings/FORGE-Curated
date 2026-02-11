// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {GovernorSettableFixedQuorum} from "src/extensions/GovernorSettableFixedQuorum.sol";
import {ZkProtocolGovernorHarness} from "test/harnesses/ZkProtocolGovernorHarness.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";
import {ProposalBuilder} from "test/helpers/ProposalBuilder.sol";
import {ERC20VotesFake} from "test/fakes/ERC20VotesFake.sol";
import {TimelockControllerFake} from "test/fakes/TimelockControllerFake.sol";

contract GovernorSettableFixedQuorumTest is Test {
  uint48 constant INITIAL_VOTING_DELAY = 1 days;
  uint32 constant INITIAL_VOTING_PERIOD = 7 days;
  uint256 constant INITIAL_PROPOSAL_THRESHOLD = 500_000e18;
  uint224 constant INITIAL_QUORUM = 1_000_000e18;
  uint64 constant INITIAL_VOTE_EXTENSION = 1 days;

  TimelockControllerFake timelock;
  ERC20VotesFake token;
  ZkProtocolGovernorHarness governor;

  function setUp() public {
    address initialOwner = makeAddr("Initial Owner");
    timelock = new TimelockControllerFake(initialOwner);
    token = new ERC20VotesFake();
    governor = new ZkProtocolGovernorHarness(
      "Example Gov",
      token,
      timelock,
      INITIAL_VOTING_DELAY,
      INITIAL_VOTING_PERIOD,
      INITIAL_PROPOSAL_THRESHOLD,
      INITIAL_QUORUM,
      INITIAL_VOTE_EXTENSION
    );

    vm.prank(initialOwner);
    timelock.grantRole(keccak256("PROPOSER_ROLE"), address(governor));

    vm.prank(initialOwner);
    timelock.grantRole(keccak256("EXECUTOR_ROLE"), address(governor));
  }
}

contract Quorum is GovernorSettableFixedQuorumTest {
  function testFuzz_SuccessfullyGetLatestQuorumCheckpoint(uint208 _quorum) public {
    governor.exposed_setQuorum(_quorum);
    uint256 quorum = governor.quorum(block.timestamp);
    assertEq(quorum, _quorum);
  }
}

contract SetQuorum is GovernorSettableFixedQuorumTest, ProposalTest {
  function testFuzz_CorrectlySetQuorumCheckpoint(uint224 _quorum) public {
    address delegate = makeAddr("delegate");
    token.mint(delegate, governor.proposalThreshold());
    token.mint(delegate, governor.quorum(block.timestamp));

    vm.prank(delegate);
    token.delegate(delegate);

    vm.warp(block.timestamp + 1);
    address[] memory delegates = new address[](1);
    delegates[0] = delegate;
    _setGovernor(governor);
    _setDelegates(delegates);
    ProposalBuilder builder = new ProposalBuilder();
    builder.push(address(governor), 0, abi.encodeWithSignature("setQuorum(uint224)", _quorum));
    _queueAndVoteAndExecuteProposal(builder.targets(), builder.values(), builder.calldatas(), "Description", 1);
    assertEq(governor.quorum(block.timestamp), _quorum);
  }

  function testFuzz_CorrectlyEmitQuorumUpdatedEvent(uint224 _quorum) public {
    address delegate = makeAddr("delegate");
    token.mint(delegate, governor.proposalThreshold());
    token.mint(delegate, governor.quorum(block.timestamp));

    vm.prank(delegate);
    token.delegate(delegate);

    vm.warp(block.timestamp + 1);
    address[] memory delegates = new address[](1);
    delegates[0] = delegate;
    _setGovernor(governor);
    _setDelegates(delegates);
    ProposalBuilder builder = new ProposalBuilder();
    builder.push(address(governor), 0, abi.encodeWithSignature("setQuorum(uint224)", _quorum));
    address[] memory targets = builder.targets();
    uint256[] memory values = builder.values();
    bytes[] memory calldatas = builder.calldatas();
    string memory description = "Description";

    uint256 proposalId = _propose(targets, values, calldatas, description);
    _jumpToActiveProposal(proposalId);

    _delegatesVote(proposalId, 1);
    _jumpPastVoteComplete(proposalId);

    governor.queue(targets, values, calldatas, keccak256(bytes(description)));

    _jumpPastProposalEta(proposalId);

    vm.expectEmit();
    emit GovernorSettableFixedQuorum.QuorumUpdated(INITIAL_QUORUM, _quorum);
    governor.execute(targets, values, calldatas, keccak256(bytes(description)));
  }

  function testFuzz_RevertIf_CallerIsNotAuthorized(uint208 _quorum, address _caller) public {
    vm.assume(_caller != address(timelock));
    vm.prank(_caller);
    vm.expectRevert(bytes("Governor: onlyGovernance"));
    governor.setQuorum(_quorum);
  }
}
