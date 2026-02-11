// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Merkle } from "@murky/Merkle.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "test/Integrations.t.sol";

contract RewardMerkleDistributor_Claim_Integrations_Test is Integrations_Test {
    uint256 internal firstClaimRewardsAmount = 1e18;
    uint256 internal secondClaimRewardsAmount = 2e18;
    uint256 internal epochRewards = INITIAL_BALANCE;
    uint256 internal totalRewards = epochRewards * 2;

    uint64 firstEpochId = 0;
    RewardMerkleDistributor.MerkleDrop firstEpochMerkleDrop;
    Merkle internal firstEpochMerkleTree;
    bytes32[] internal firstEpochLeaves;
    bytes32 internal firstEpochRoot;

    uint64 secondEpochId = 1;
    RewardMerkleDistributor.MerkleDrop secondEpochMerkleDrop;
    Merkle internal secondEpochMerkleTree;
    bytes32[] internal secondEpochLeaves;
    bytes32 internal secondEpochRoot;

    function setUp() public override {
        super.setUp();

        firstEpochMerkleTree = new Merkle();
        secondEpochMerkleTree = new Merkle();

        par.mint(address(rewardMerkleDistributor), totalRewards);

        vm.startPrank(users.admin.addr);
        /// @dev Leaves are added in the order of the merkle tree's firstEpochLeaves.
        /// @dev alice reward is at index 0, bob reward is at index 1.
        firstEpochLeaves.push(
            keccak256(bytes.concat(keccak256(abi.encode(firstEpochId, users.alice.addr, firstClaimRewardsAmount))))
        );
        firstEpochLeaves.push(
            keccak256(bytes.concat(keccak256(abi.encode(firstEpochId, users.bob.addr, firstClaimRewardsAmount))))
        );
        firstEpochRoot = firstEpochMerkleTree.getRoot(firstEpochLeaves);

        firstEpochMerkleDrop = RewardMerkleDistributor.MerkleDrop({
            root: firstEpochRoot,
            totalAmount: epochRewards,
            startTime: uint64(block.timestamp),
            expiryTime: uint64(block.timestamp) + uint64(rewardMerkleDistributor.EPOCH_LENGTH() * 6)
        });
        rewardMerkleDistributor.updateMerkleDrop(firstEpochId, firstEpochMerkleDrop);

        /// @dev Leaves are added in the order of the merkle tree's secondEpochLeaves.
        /// @dev alice reward is at index 0, bob reward is at index 1.
        secondEpochLeaves.push(
            keccak256(bytes.concat(keccak256(abi.encode(secondEpochId, users.alice.addr, secondClaimRewardsAmount))))
        );
        secondEpochLeaves.push(
            keccak256(bytes.concat(keccak256(abi.encode(secondEpochId, users.bob.addr, secondClaimRewardsAmount))))
        );
        secondEpochRoot = secondEpochMerkleTree.getRoot(secondEpochLeaves);
        secondEpochMerkleDrop = RewardMerkleDistributor.MerkleDrop({
            root: secondEpochRoot,
            totalAmount: epochRewards,
            startTime: uint64(block.timestamp) + uint64(rewardMerkleDistributor.EPOCH_LENGTH()),
            expiryTime: uint64(block.timestamp) + uint64(rewardMerkleDistributor.EPOCH_LENGTH() * 7)
        });
        rewardMerkleDistributor.updateMerkleDrop(secondEpochId, secondEpochMerkleDrop);
    }

    function test_RewardMerkleDistributor_Claim_OneEpoch() external {
        vm.startPrank(users.alice.addr);

        uint256 alicePARBalanceBefore = par.balanceOf(users.alice.addr);
        bytes32[] memory proof = firstEpochMerkleTree.getProof(firstEpochLeaves, 0);

        RewardMerkleDistributor.ClaimCallData[] memory claimsData = new RewardMerkleDistributor.ClaimCallData[](1);
        claimsData[0] = RewardMerkleDistributor.ClaimCallData({
            epochId: firstEpochId,
            account: users.alice.addr,
            amount: firstClaimRewardsAmount,
            merkleProof: proof
        });

        rewardMerkleDistributor.claims(claimsData);
        assertEq(par.balanceOf(users.alice.addr), alicePARBalanceBefore + firstClaimRewardsAmount);
        assertEq(par.balanceOf(address(rewardMerkleDistributor)), totalRewards - firstClaimRewardsAmount);
        assertEq(rewardMerkleDistributor.totalClaimedPerUser(users.alice.addr), firstClaimRewardsAmount);
        assertEq(rewardMerkleDistributor.totalClaimedPerEpoch(firstEpochId), firstClaimRewardsAmount);
        assertEq(rewardMerkleDistributor.totalClaimed(), firstClaimRewardsAmount);
    }

    function test_RewardMerkleDistributor_Claim_SeveralEpochs() external {
        vm.startPrank(users.alice.addr);
        uint256 expectedTotalClaimed = firstClaimRewardsAmount + secondClaimRewardsAmount;

        uint256 alicePARBalanceBefore = par.balanceOf(users.alice.addr);
        bytes32[] memory firstEpochProof = firstEpochMerkleTree.getProof(firstEpochLeaves, 0);
        bytes32[] memory secondEpochProof = secondEpochMerkleTree.getProof(secondEpochLeaves, 0);

        RewardMerkleDistributor.ClaimCallData[] memory claimsData = new RewardMerkleDistributor.ClaimCallData[](2);
        claimsData[0] = RewardMerkleDistributor.ClaimCallData({
            epochId: firstEpochId,
            account: users.alice.addr,
            amount: firstClaimRewardsAmount,
            merkleProof: firstEpochProof
        });
        claimsData[1] = RewardMerkleDistributor.ClaimCallData({
            epochId: secondEpochId,
            account: users.alice.addr,
            amount: secondClaimRewardsAmount,
            merkleProof: secondEpochProof
        });

        vm.warp(secondEpochMerkleDrop.startTime);

        rewardMerkleDistributor.claims(claimsData);
        assertEq(par.balanceOf(users.alice.addr), alicePARBalanceBefore + expectedTotalClaimed);
        assertEq(par.balanceOf(address(rewardMerkleDistributor)), totalRewards - expectedTotalClaimed);
        assertEq(rewardMerkleDistributor.totalClaimedPerUser(users.alice.addr), expectedTotalClaimed);
        assertEq(rewardMerkleDistributor.totalClaimedPerEpoch(firstEpochId), firstClaimRewardsAmount);
        assertEq(rewardMerkleDistributor.totalClaimedPerEpoch(secondEpochId), secondClaimRewardsAmount);
        assertEq(rewardMerkleDistributor.totalClaimed(), expectedTotalClaimed);
    }

    function test_RewardMerkleDistributor_Claim_RevertWhen_EpochExpired() external {
        vm.startPrank(users.alice.addr);
        bytes32[] memory proof = firstEpochMerkleTree.getProof(firstEpochLeaves, 0);

        RewardMerkleDistributor.ClaimCallData[] memory claimsData = new RewardMerkleDistributor.ClaimCallData[](1);
        claimsData[0] = RewardMerkleDistributor.ClaimCallData({
            epochId: firstEpochId,
            account: users.alice.addr,
            amount: firstClaimRewardsAmount,
            merkleProof: proof
        });
        vm.warp(firstEpochMerkleDrop.expiryTime + 1);
        vm.expectRevert(RewardMerkleDistributor.EpochExpired.selector);
        rewardMerkleDistributor.claims(claimsData);
    }

    function test_RewardMerkleDistributor_Claim_RevertWhen_EpochNotStarted() external {
        vm.startPrank(users.alice.addr);
        bytes32[] memory proof = secondEpochMerkleTree.getProof(secondEpochLeaves, 0);

        RewardMerkleDistributor.ClaimCallData[] memory claimsData = new RewardMerkleDistributor.ClaimCallData[](1);
        claimsData[0] = RewardMerkleDistributor.ClaimCallData({
            epochId: secondEpochId,
            account: users.alice.addr,
            amount: secondClaimRewardsAmount,
            merkleProof: proof
        });
        vm.expectRevert(RewardMerkleDistributor.NotStarted.selector);
        rewardMerkleDistributor.claims(claimsData);
    }

    function test_RewardMerkleDistributor_Claim_RevertWhen_EpochAlreadyClaimed() external {
        vm.startPrank(users.alice.addr);

        bytes32[] memory proof = firstEpochMerkleTree.getProof(firstEpochLeaves, 0);

        RewardMerkleDistributor.ClaimCallData[] memory claimsData = new RewardMerkleDistributor.ClaimCallData[](1);
        claimsData[0] = RewardMerkleDistributor.ClaimCallData({
            epochId: firstEpochId,
            account: users.alice.addr,
            amount: firstClaimRewardsAmount,
            merkleProof: proof
        });

        rewardMerkleDistributor.claims(claimsData);

        vm.expectRevert(RewardMerkleDistributor.AlreadyClaimed.selector);
        rewardMerkleDistributor.claims(claimsData);
    }

    function test_RewardMerkleDistributor_Claim_RevertWhen_ProofInvalid() external {
        vm.startPrank(users.alice.addr);

        bytes32[] memory proof = firstEpochMerkleTree.getProof(firstEpochLeaves, 0);

        RewardMerkleDistributor.ClaimCallData[] memory claimsData = new RewardMerkleDistributor.ClaimCallData[](1);
        claimsData[0] = RewardMerkleDistributor.ClaimCallData({
            epochId: firstEpochId,
            account: users.alice.addr,
            amount: firstClaimRewardsAmount * 100,
            merkleProof: proof
        });

        vm.expectRevert(RewardMerkleDistributor.ProofInvalid.selector);
        rewardMerkleDistributor.claims(claimsData);
    }

    modifier SetupTotalEpochRewardAmountClaimedExceedsEpochTotalAmount() {
        vm.startPrank(users.admin.addr);
        firstEpochMerkleDrop = RewardMerkleDistributor.MerkleDrop({
            root: firstEpochRoot,
            totalAmount: firstClaimRewardsAmount - 1,
            startTime: uint64(block.timestamp),
            expiryTime: uint64(block.timestamp) + uint64(rewardMerkleDistributor.EPOCH_LENGTH() * 6)
        });
        rewardMerkleDistributor.updateMerkleDrop(firstEpochId, firstEpochMerkleDrop);

        _;
    }

    function test_RewardMerkleDistributor_Claim_RevertWhen_TotalAmountExceedsEpochTotalAmount()
        external
        SetupTotalEpochRewardAmountClaimedExceedsEpochTotalAmount
    {
        vm.startPrank(users.alice.addr);

        bytes32[] memory proof = firstEpochMerkleTree.getProof(firstEpochLeaves, 0);

        RewardMerkleDistributor.ClaimCallData[] memory claimsData = new RewardMerkleDistributor.ClaimCallData[](1);
        claimsData[0] = RewardMerkleDistributor.ClaimCallData({
            epochId: firstEpochId,
            account: users.alice.addr,
            amount: firstClaimRewardsAmount,
            merkleProof: proof
        });

        vm.expectRevert(RewardMerkleDistributor.TotalEpochRewardsExceeded.selector);
        rewardMerkleDistributor.claims(claimsData);
    }
}
