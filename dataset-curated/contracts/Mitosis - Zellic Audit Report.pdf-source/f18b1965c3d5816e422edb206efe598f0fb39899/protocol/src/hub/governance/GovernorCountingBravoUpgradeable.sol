// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (governance/extensions/GovernorCountingSimple.sol)

// Modified to support the Bravo style of quorum.
pragma solidity ^0.8.28;

import { GovernorUpgradeable } from '@ozu/governance/GovernorUpgradeable.sol';
import { Initializable } from '@ozu/proxy/utils/Initializable.sol';

import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';

/**
 * @dev Extension of {Governor} for Compound Bravo style of vote counting.
 * The difference with GovernorCountingSimpleUpgradeable is that only For votes are counted towards quorum.
 */
abstract contract GovernorCountingBravoUpgradeable is Initializable, GovernorUpgradeable {
  using ERC7201Utils for string;

  /**
   * @dev Supported vote types. Matches Governor Bravo ordering.
   */
  enum VoteType {
    Against,
    For,
    Abstain
  }

  struct ProposalVote {
    uint256 againstVotes;
    uint256 forVotes;
    uint256 abstainVotes;
    mapping(address voter => bool) hasVoted;
  }

  /// @custom:storage-location mitosis.storage.GovernorCountingBravo
  struct GovernorCountingBravoStorage {
    mapping(uint256 proposalId => ProposalVote) _proposalVotes;
  }

  string private constant _GovernorCountingBravoStorageNamespace = 'mitosis.storage.GovernorCountingBravo';
  bytes32 private immutable _GovernorCountingBravoStorageLocation = _GovernorCountingBravoStorageNamespace.storageSlot();

  function _getGovernorCountingBravoStorage() private view returns (GovernorCountingBravoStorage storage $) {
    bytes32 slot = _GovernorCountingBravoStorageLocation;
    assembly {
      $.slot := slot
    }
  }

  function __GovernorCountingBravo_init() internal onlyInitializing { }

  function __GovernorCountingBravo_init_unchained() internal onlyInitializing { }

  /**
   * @dev See {IGovernor-COUNTING_MODE}.
   */
  // solhint-disable-next-line func-name-mixedcase
  function COUNTING_MODE() public pure virtual override returns (string memory) {
    return 'support=bravo&quorum=bravo';
  }

  /**
   * @dev See {IGovernor-hasVoted}.
   */
  function hasVoted(uint256 proposalId, address account) public view virtual override returns (bool) {
    GovernorCountingBravoStorage storage $ = _getGovernorCountingBravoStorage();
    return $._proposalVotes[proposalId].hasVoted[account];
  }

  /**
   * @dev Accessor to the internal vote counts.
   */
  function proposalVotes(uint256 proposalId)
    public
    view
    virtual
    returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)
  {
    GovernorCountingBravoStorage storage $ = _getGovernorCountingBravoStorage();
    ProposalVote storage proposalVote = $._proposalVotes[proposalId];
    return (proposalVote.againstVotes, proposalVote.forVotes, proposalVote.abstainVotes);
  }

  /**
   * @dev See {Governor-_quorumReached}.
   */
  function _quorumReached(uint256 proposalId) internal view virtual override returns (bool) {
    GovernorCountingBravoStorage storage $ = _getGovernorCountingBravoStorage();
    ProposalVote storage proposalVote = $._proposalVotes[proposalId];

    return quorum(proposalSnapshot(proposalId)) <= proposalVote.forVotes;
  }

  /**
   * @dev See {Governor-_voteSucceeded}. In this module, the forVotes must be strictly over the againstVotes.
   */
  function _voteSucceeded(uint256 proposalId) internal view virtual override returns (bool) {
    GovernorCountingBravoStorage storage $ = _getGovernorCountingBravoStorage();
    ProposalVote storage proposalVote = $._proposalVotes[proposalId];

    return proposalVote.forVotes > proposalVote.againstVotes;
  }

  /**
   * @dev See {Governor-_countVote}. In this module, the support follows the `VoteType` enum (from Governor Bravo).
   */
  function _countVote(
    uint256 proposalId,
    address account,
    uint8 support,
    uint256 totalWeight,
    bytes memory // params
  ) internal virtual override returns (uint256) {
    GovernorCountingBravoStorage storage $ = _getGovernorCountingBravoStorage();
    ProposalVote storage proposalVote = $._proposalVotes[proposalId];

    if (proposalVote.hasVoted[account]) {
      revert GovernorAlreadyCastVote(account);
    }
    proposalVote.hasVoted[account] = true;

    if (support == uint8(VoteType.Against)) {
      proposalVote.againstVotes += totalWeight;
    } else if (support == uint8(VoteType.For)) {
      proposalVote.forVotes += totalWeight;
    } else if (support == uint8(VoteType.Abstain)) {
      proposalVote.abstainVotes += totalWeight;
    } else {
      revert GovernorInvalidVoteType();
    }

    return totalWeight;
  }
}
