// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { AutoCompoundBase } from "./AutoCompoundBase.t.sol";
import { AddressGaugeVoter as GaugeVoter } from "@voting/AddressGaugeVoter.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

contract AutoCompoundVoteTest is AutoCompoundBase {
    function testRevert_IfNoPermission() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(acStrategy),
                address(1),
                acStrategy.AUTOCOMPOUND_STRATEGY_VOTE_ROLE()
            )
        );
        vm.prank(address(1));
        acStrategy.vote(new GaugeVoter.GaugeVote[](0));
    }

    // AcStrategy gets delegated to itself and votes.
    function test_DelegatesItselfAndVotes_WithoutCompounding() public {
        // Strategy delegates to itself
        acStrategy.delegate(address(acStrategy));

        // Verify self-delegation
        address actualDelegatee = ivotesAdapter.delegates(address(acStrategy));
        assertEq(actualDelegatee, address(acStrategy));

        // Strategy can now vote directly
        GaugeVoter.GaugeVote[] memory votes = _createGaugeVotes();
        acStrategy.vote(votes);

        // Verify votes were cast
        uint256 gaugeAVotes = voter.votes(address(acStrategy), gaugeA);
        uint256 gaugeBVotes = voter.votes(address(acStrategy), gaugeB);

        assertNotEq(gaugeAVotes, 0);
        assertNotEq(gaugeBVotes, 0);
    }

    function test_VoteDirectlyAfterCompounding() public {
        // Strategy delegates to itself
        acStrategy.delegate(address(acStrategy));

        // Initial vote
        GaugeVoter.GaugeVote[] memory votes = _createGaugeVotes();
        acStrategy.vote(votes);

        uint256 gaugeAVotesBefore = voter.votes(address(acStrategy), gaugeA);
        uint256 gaugeBVotesBefore = voter.votes(address(acStrategy), gaugeB);

        // Compound to increase voting power
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(acStrategy), tokens, amounts);
        Action[] memory actions =
            swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), address(swapper));

        acStrategy.claimAndCompound(tokens, amounts, proofs, actions);

        // Vote again with increased voting power
        acStrategy.vote(votes);

        // Voting power increased due to compounding
        assertGt(voter.votes(address(acStrategy), gaugeA), gaugeAVotesBefore);
        assertGt(voter.votes(address(acStrategy), gaugeB), gaugeBVotesBefore);
    }

    // User gets delegated and votes on gauge voter directly.
    function test_DelegatesOtherAndVotes() public {
        // Set up delegatee EOA
        address delegatee = address(0xDEAD);
        acStrategy.delegate(delegatee);

        // Verify delegation
        address actualDelegatee = ivotesAdapter.delegates(address(acStrategy));
        assertEq(actualDelegatee, delegatee);

        // Now the delegatee can vote directly on the voter with strategy's voting power
        GaugeVoter.GaugeVote[] memory votes = _createGaugeVotes();

        vm.prank(delegatee);
        voter.vote(votes);

        uint256 gaugeAVotesBefore = voter.votes(delegatee, gaugeA);
        uint256 gaugeBVotesBefore = voter.votes(delegatee, gaugeB);

        assertNotEq(gaugeAVotesBefore, 0);
        assertNotEq(gaugeBVotesBefore, 0);

        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(acStrategy), tokens, amounts);
        Action[] memory actions =
            swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), address(swapper));

        acStrategy.claimAndCompound(tokens, amounts, proofs, actions);

        // After compounding, delegatee can vote again with increased voting power
        vm.prank(delegatee);
        voter.vote(votes);

        // Voting power increased due to compounding
        assertGt(voter.votes(delegatee, gaugeA), gaugeAVotesBefore);
        assertGt(voter.votes(delegatee, gaugeB), gaugeBVotesBefore);
    }
}
