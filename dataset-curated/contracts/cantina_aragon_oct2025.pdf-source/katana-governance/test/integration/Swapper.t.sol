// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../Base.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { Errors } from "@merkl/utils/Errors.sol";
import { ISwapper } from "src/interfaces/ISwapper.sol";
import { MockERC20 } from "@mocks/MockERC20.sol";

contract SwapperTest is Base {
    address[] internal tokens;
    uint256[] internal amounts;

    function setUp() public override {
        super.setUp();

        tokens.push(tokenA);
        tokens.push(tokenB);

        amounts.push(50e18);
        amounts.push(15e18);
    }

    function testRevert_IfAutoCompoundConfigInvalid() public {
        vm.expectRevert(ISwapper.PctTooBig.selector);
        swapper.claimAndSwap(
            ISwapper.Claim(new address[](0), new uint256[](0), new bytes32[][](0)), new Action[](0), 101
        );
    }

    function testRevert_IfInvalidProof() public {
        uint256[] memory newAmounts = amounts;
        newAmounts[1] = 17e18; // change amount.

        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, newAmounts);

        vm.expectRevert(Errors.InvalidProof.selector);
        vm.prank(alice, alice);
        swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), new Action[](0), 0);
    }

    function testRevert_IfAliceClaimsWithBobsProof() public {
        // Generate proof for bob
        (bytes32[][] memory bobProofs,) = merkleTreeHelper.buildMerkleTree(bob, tokens, amounts);

        // Alice tries to claim using Bob's proof
        vm.expectRevert(Errors.InvalidProof.selector);
        vm.prank(alice, alice);
        swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, bobProofs), new Action[](0), 0);
    }

    function testRevert_IfAtLeastOneActionFails() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, amounts);

        Action[] memory actions = new Action[](1);
        actions[0].to = address(this);
        actions[0].data = "0x11111111";

        ISwapper.Claim memory claim = ISwapper.Claim(tokens, amounts, proofs);

        vm.expectRevert();
        vm.prank(alice, alice);
        swapper.claimAndSwap(claim, actions, 0);
    }

    // both tokens are swapped into kat but autocompound is false, hence all kat tokens go to the user.
    function test_MultipleTokensSwappedAndAutoCompoundIsFalse() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, amounts);
        Action[] memory actions = swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), alice);

        assertEq(escrowToken.balanceOf(alice), 0);
        vm.prank(alice, alice);
        swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), actions, 0);

        assertEq(escrowToken.balanceOf(alice), 130e18);
    }

    // both tokens are swapped into kat and autocompound is true, hence
    // creates lock with some portion to locked and rest goes to user.
    function test_MultipleTokensSwappedAndCompoundIsEnabled() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, amounts);
        Action[] memory actions =
            swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), address(swapper));

        uint256 pct = 10;
        uint256 lockAmount = (pct * 130e18) / 100;

        assertEq(escrowToken.balanceOf(alice), 0);
        vm.prank(alice, alice);
        vm.expectEmit();
        emit ISwapper.ClaimAndSwapped(alice, tokens, amounts, pct, ISwapper.Locked(2, lockAmount));
        (uint256 diff, uint256 tokenId) = swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), actions, pct);

        assertEq(diff, 130e18);
        assertEq(escrow.locked(tokenId).amount, lockAmount);
        assertEq(escrowToken.balanceOf(alice), 130e18 - lockAmount);
    }

    // // Only single token is swapped into kat and compound is enabled,
    // // hence some portion goes to newly created lock, rest goes to user.
    function test_SingleTokenSwappedAndCompoundIsEnabled() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, amounts);

        address[] memory outTokens = new address[](2);
        address[] memory recipients = new address[](2);
        outTokens[0] = address(escrowToken);
        outTokens[1] = address(tokenC);
        recipients[0] = address(swapper);
        recipients[1] = alice;

        Action[] memory actions = swapActionsBuilder.buildSwapActions(tokens, amounts, outTokens, recipients);

        assertEq(escrowToken.balanceOf(alice), 0);

        uint256 pct = 10;
        uint256 lockAmount = (pct * 100e18) / 100;

        vm.prank(alice, alice);
        vm.expectEmit();
        emit ISwapper.ClaimAndSwapped(alice, tokens, amounts, pct, ISwapper.Locked(2, lockAmount));
        (uint256 diff, uint256 tokenId) = swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), actions, pct);

        assertEq(diff, 100e18);
        assertEq(escrow.locked(tokenId).amount, lockAmount);
        assertEq(escrowToken.balanceOf(alice), 100e18 - lockAmount);
    }

    // no tokens are swapped into kat, hence no kat increase on user.
    function test_NoTokenIsSwappedIntoKat() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(alice, tokens, amounts);
        Action[] memory actions = swapActionsBuilder.buildSwapActions(tokens, amounts, tokenC, alice);

        uint256 aliceBalanceBeforeOnTokenC = MockERC20(tokenC).balanceOf(alice);

        assertEq(escrowToken.balanceOf(alice), 0);
        vm.prank(alice, alice);
        vm.expectEmit();
        emit ISwapper.ClaimAndSwapped(alice, tokens, amounts, 10, ISwapper.Locked(0, 0));
        (uint256 diff,) = swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), actions, 10);

        assertEq(escrowToken.balanceOf(alice), 0);
        assertEq(diff, 0);
        assertGt(MockERC20(tokenC).balanceOf(alice), aliceBalanceBeforeOnTokenC);
    }
}
