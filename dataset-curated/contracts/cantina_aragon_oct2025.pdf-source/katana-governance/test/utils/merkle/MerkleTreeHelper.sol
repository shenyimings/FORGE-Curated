// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CommonBase } from "forge-std/Base.sol";

import { Distributor as MerklDistributor, MerkleTree as MerkleTreeStruct } from "@merkl/Distributor.sol";

import { MerkleTree } from "./MerkleTree.sol";
import { MockERC20 } from "@mocks/MockERC20.sol";

contract MerkleTreeHelper is CommonBase {
    MerklDistributor public merklDistributor;
    address internal swapper;
    address internal swapperRouter;
    address internal governor;

    bytes32[] public leaves;
    MerkleTree public merkleTree;

    constructor(address _merklDistributor, address _governor, address _swapper, address _swapperRouter) {
        merklDistributor = MerklDistributor(_merklDistributor);
        swapper = _swapper;
        swapperRouter = _swapperRouter;
        governor = _governor;

        merkleTree = new MerkleTree();
    }

    function buildMerkleTree(
        address user,
        address[] memory tokens,
        uint256[] memory amounts
    )
        external
        returns (bytes32[][] memory proofs, bytes32 root)
    {
        // Clear previous leaves
        delete leaves;

        proofs = new bytes32[][](tokens.length);

        // Build leaves
        for (uint256 i = 0; i < tokens.length; i++) {
            leaves.push(keccak256(abi.encode(user, tokens[i], amounts[i])));

            vm.prank(user);
            merklDistributor.setClaimRecipient(swapper, tokens[i]);

            vm.prank(swapper);
            MockERC20(tokens[i]).approve(swapperRouter, type(uint192).max);

            MockERC20(tokens[i]).mint(address(merklDistributor), amounts[i]);
        }

        // Update merkle root
        root = merkleTree.getRoot(leaves);

        vm.prank(governor);
        merklDistributor.updateTree(MerkleTreeStruct({ merkleRoot: root, ipfsHash: bytes32(0) }));

        vm.warp(merklDistributor.endOfDisputePeriod() + 1);

        // Generate proofs
        for (uint256 i = 0; i < tokens.length; i++) {
            proofs[i] = merkleTree.getProof(leaves, i);
        }
    }
}
