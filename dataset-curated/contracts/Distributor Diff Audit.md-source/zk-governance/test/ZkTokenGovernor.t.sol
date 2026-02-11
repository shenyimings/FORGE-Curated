// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Test, console2} from "forge-std/Test.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";

import {ZkTokenGovernor} from "src/ZkTokenGovernor.sol";
import {ZkTokenGovernorHarness} from "test/harnesses/ZkTokenGovernorHarness.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";
import {ProposalBuilder} from "test/helpers/ProposalBuilder.sol";
import {ERC20VotesFake} from "test/fakes/ERC20VotesFake.sol";
import {TimelockControllerFake} from "test/fakes/TimelockControllerFake.sol";

contract ZkTokenGovernorTest is Test {
  uint48 constant INITIAL_VOTING_DELAY = 1 days;
  uint32 constant INITIAL_VOTING_PERIOD = 7 days;
  uint256 constant INITIAL_PROPOSAL_THRESHOLD = 500_000e18;
  uint224 constant INITIAL_QUORUM = 1_000_000e18;
  uint64 constant INITIAL_VOTE_EXTENSION = 1 days;
  string constant DESCRIPTION = "Description";
  address initialOwner;
  address vetoGuardian;
  address proposeGuardian;

  TimelockControllerFake timelock;
  ERC20VotesFake token;
  ZkTokenGovernorHarness governor;

  function setUp() public {
    initialOwner = makeAddr("Initial Owner");
    vetoGuardian = makeAddr("Veto Guardian");
    proposeGuardian = makeAddr("Propose Guardian");
    timelock = new TimelockControllerFake(initialOwner);
    token = new ERC20VotesFake();
    ZkTokenGovernor.ConstructorParams memory params = ZkTokenGovernor.ConstructorParams({
      name: "Example Gov",
      token: token,
      timelock: timelock,
      initialVotingDelay: INITIAL_VOTING_DELAY,
      initialVotingPeriod: INITIAL_VOTING_PERIOD,
      initialProposalThreshold: INITIAL_PROPOSAL_THRESHOLD,
      initialQuorum: INITIAL_QUORUM,
      initialVoteExtension: INITIAL_VOTE_EXTENSION,
      vetoGuardian: vetoGuardian,
      proposeGuardian: proposeGuardian,
      isProposeGuarded: false
    });
    governor = new ZkTokenGovernorHarness(params);

    vm.prank(initialOwner);
    timelock.grantRole(keccak256("PROPOSER_ROLE"), address(governor));

    vm.prank(initialOwner);
    timelock.grantRole(keccak256("EXECUTOR_ROLE"), address(governor));
  }

  function _mintAndDelegate(address _caller, uint256 _mintAmount) public {
    token.mint(_caller, _mintAmount);
    vm.prank(_caller);
    token.delegate(_caller);

    vm.warp(block.timestamp + 1);
  }
}

contract ProposalThreshold is ZkTokenGovernorTest, ProposalTest {
  function _buildProposal() internal returns (ProposalBuilder) {
    vm.warp(block.timestamp + 1);
    _setGovernor(governor);
    ProposalBuilder builder = new ProposalBuilder();
    builder.push(address(governor), 0, abi.encodeWithSignature("setIsProposeGuarded(bool)", true));
    return builder;
  }

  function test_ToggledOffAndGuardianIsCalling() public {
    governor.exposed_setIsGuardianPropose(false);
    ProposalBuilder builder = _buildProposal();

    vm.startPrank(proposeGuardian);
    uint256 proposalId = governor.propose(builder.targets(), builder.values(), builder.calldatas(), DESCRIPTION);
    vm.stopPrank();

    assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));
  }

  function test_ToggledOnAndGuardianIsCalling() public {
    governor.exposed_setIsGuardianPropose(true);
    ProposalBuilder builder = _buildProposal();

    vm.startPrank(proposeGuardian);
    uint256 proposalId = governor.propose(builder.targets(), builder.values(), builder.calldatas(), DESCRIPTION);
    vm.stopPrank();

    assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));
  }

  function testFuzz_RevertIf_ToggledOnAndGuardianIsNotCalling(address _caller) public {
    vm.assume(_caller != address(0));
    vm.assume(_caller != proposeGuardian);
    governor.exposed_setIsGuardianPropose(true);
    ProposalBuilder builder = _buildProposal();

    _mintAndDelegate(_caller, INITIAL_PROPOSAL_THRESHOLD);
    vm.startPrank(_caller);
    address[] memory targets = builder.targets();
    uint256[] memory values = builder.values();
    bytes[] memory calldatas = builder.calldatas();

    vm.expectRevert("Governor: proposer votes below proposal threshold");
    governor.propose(targets, values, calldatas, DESCRIPTION);
    vm.stopPrank();
  }

  function testFuzz_ToggledOffAndGuardianIsNotCalling(address _caller) public {
    vm.assume(_caller != address(0));
    governor.exposed_setIsGuardianPropose(false);
    ProposalBuilder builder = _buildProposal();

    _mintAndDelegate(_caller, INITIAL_PROPOSAL_THRESHOLD);
    vm.startPrank(_caller);
    address[] memory targets = builder.targets();
    uint256[] memory values = builder.values();
    bytes[] memory calldatas = builder.calldatas();
    uint256 proposalId = governor.propose(targets, values, calldatas, DESCRIPTION);
    vm.stopPrank();

    IGovernor.ProposalState pendingState = governor.state(proposalId);
    assertEq(uint8(pendingState), uint8(IGovernor.ProposalState.Pending));
  }

  function testFuzz_RevertIf_ToggledOffAndCallerIsBelowTheThreshold(address _caller) public {
    vm.assume(_caller != address(0));
    vm.assume(_caller != proposeGuardian);
    governor.exposed_setIsGuardianPropose(false);
    ProposalBuilder builder = _buildProposal();

    _mintAndDelegate(_caller, INITIAL_PROPOSAL_THRESHOLD - 1);
    vm.startPrank(_caller);
    address[] memory targets = builder.targets();
    uint256[] memory values = builder.values();
    bytes[] memory calldatas = builder.calldatas();
    vm.expectRevert("Governor: proposer votes below proposal threshold");
    governor.propose(targets, values, calldatas, DESCRIPTION);
    vm.stopPrank();
  }
}

contract SetIsProposeGuarded is ZkTokenGovernorTest, ProposalTest {
  function _buildProposal(bool isProposeGuarded) internal returns (ProposalBuilder) {
    vm.warp(block.timestamp + 1);
    _setGovernor(governor);
    ProposalBuilder builder = new ProposalBuilder();
    builder.push(address(governor), 0, abi.encodeWithSignature("setIsProposeGuarded(bool)", isProposeGuarded));
    return builder;
  }

  function testFuzz_GovernanceCanUpdateWhetherTheProposeIsGuarded(bool _isGuarded) public {
    ProposalBuilder builder = _buildProposal(_isGuarded);

    address[] memory targets = builder.targets();
    uint256[] memory values = builder.values();
    bytes[] memory calldatas = builder.calldatas();
    _mintAndDelegate(proposeGuardian, governor.quorum(block.timestamp) + 1);
    _setDelegates(proposeGuardian);
    _setGovernor(governor);
    _queueAndVoteAndExecuteProposal(targets, values, calldatas, DESCRIPTION, 1);

    assertEq(governor.isProposeGuarded(), _isGuarded);
  }

  function testFuzz_GovernanceCanUpdateWhetherTheProposeIsGuardedAndIsProposeGuardedToggledIsEmitted(
    bool _oldIsGuarded,
    bool _newIsGuarded
  ) public {
    ProposalBuilder builder = _buildProposal(_newIsGuarded);

    governor.exposed_setIsGuardianPropose(_oldIsGuarded);
    address[] memory targets = builder.targets();
    uint256[] memory values = builder.values();
    bytes[] memory calldatas = builder.calldatas();
    _mintAndDelegate(proposeGuardian, governor.quorum(block.timestamp) + 1);
    _setDelegates(proposeGuardian);
    _setGovernor(governor);
    uint256 _proposalId = _propose(targets, values, calldatas, DESCRIPTION);
    _jumpToActiveProposal(_proposalId);

    _delegatesVote(_proposalId, 1);
    _jumpPastVoteComplete(_proposalId);

    governor.queue(targets, values, calldatas, keccak256(bytes(DESCRIPTION)));

    _jumpPastProposalEta(_proposalId);
    vm.expectEmit();
    emit ZkTokenGovernor.IsProposeGuardedToggled(_oldIsGuarded, _newIsGuarded);
    governor.execute(targets, values, calldatas, keccak256(bytes(DESCRIPTION)));

    assertEq(governor.isProposeGuarded(), _newIsGuarded);
  }

  function testFuzz_RevertIf_CallerCannotUpdateIsGuardian(address _caller, bool isGuarded) public {
    vm.assume(_caller != address(timelock));
    vm.startPrank(_caller);
    vm.expectRevert("Governor: onlyGovernance");
    governor.setIsProposeGuarded(isGuarded);
    vm.stopPrank();
  }
}
