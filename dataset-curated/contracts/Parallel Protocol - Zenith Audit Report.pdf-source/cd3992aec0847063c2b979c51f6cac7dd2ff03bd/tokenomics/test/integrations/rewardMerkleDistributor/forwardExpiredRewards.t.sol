// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Merkle } from "@murky/Merkle.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "test/Integrations.t.sol";

contract RewardMerkleDistributor_ForwardExpiredRewards_Integrations_Test is Integrations_Test {
    uint256 internal firstRewardsAmount = 1e18;
    uint256 internal totalFirstRewardsAmount = firstRewardsAmount * 2;
    uint256 internal secondRewardsAmount = 2e18;
    uint256 internal totalSecondRewardsAmount = secondRewardsAmount * 2;

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

        par.mint(address(rewardMerkleDistributor), INITIAL_BALANCE);

        vm.startPrank(users.admin.addr);
        /// @dev Leaves are added in the order of the merkle tree's firstEpochLeaves.
        /// @dev alice reward is at index 0, bob reward is at index 1.
        firstEpochLeaves.push(
            keccak256(bytes.concat(keccak256(abi.encode(firstEpochId, users.alice.addr, firstRewardsAmount))))
        );
        firstEpochLeaves.push(
            keccak256(bytes.concat(keccak256(abi.encode(firstEpochId, users.bob.addr, firstRewardsAmount))))
        );
        firstEpochRoot = firstEpochMerkleTree.getRoot(firstEpochLeaves);

        firstEpochMerkleDrop = RewardMerkleDistributor.MerkleDrop({
            root: firstEpochRoot,
            totalAmount: totalFirstRewardsAmount,
            startTime: uint64(block.timestamp),
            expiryTime: uint64(block.timestamp) + uint64(rewardMerkleDistributor.EPOCH_LENGTH() * 6)
        });
        rewardMerkleDistributor.updateMerkleDrop(firstEpochId, firstEpochMerkleDrop);

        /// @dev Leaves are added in the order of the merkle tree's secondEpochLeaves.
        /// @dev alice reward is at index 0, bob reward is at index 1.
        secondEpochLeaves.push(
            keccak256(bytes.concat(keccak256(abi.encode(secondEpochId, users.alice.addr, secondRewardsAmount))))
        );
        secondEpochLeaves.push(
            keccak256(bytes.concat(keccak256(abi.encode(secondEpochId, users.bob.addr, secondRewardsAmount))))
        );
        secondEpochRoot = secondEpochMerkleTree.getRoot(secondEpochLeaves);
        secondEpochMerkleDrop = RewardMerkleDistributor.MerkleDrop({
            root: secondEpochRoot,
            totalAmount: totalSecondRewardsAmount,
            startTime: uint64(block.timestamp) + uint64(rewardMerkleDistributor.EPOCH_LENGTH()),
            expiryTime: uint64(block.timestamp) + uint64(rewardMerkleDistributor.EPOCH_LENGTH() * 7)
        });
        rewardMerkleDistributor.updateMerkleDrop(secondEpochId, secondEpochMerkleDrop);
    }

    function test_RewardMerkleDistributor_ForwardExpiredRewards_AllRewardsFromOneEpoch() external {
        vm.startPrank(users.admin.addr);
        uint256 expiredRewardsRecipientBalanceBefore = par.balanceOf(users.daoTreasury.addr);

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = firstEpochId;

        vm.warp(firstEpochMerkleDrop.expiryTime + 1);

        uint256 totalExpiredRewards = rewardMerkleDistributor.getExpiredEpochRewards(epochIds);
        assertEq(totalExpiredRewards, totalFirstRewardsAmount);

        vm.expectEmit(true, true, true, true);
        emit RewardMerkleDistributor.ExpiredRewardsForwarded(firstEpochId, totalFirstRewardsAmount);
        rewardMerkleDistributor.forwardExpiredRewards(epochIds);

        assertEq(par.balanceOf(users.daoTreasury.addr), expiredRewardsRecipientBalanceBefore + totalFirstRewardsAmount);
        assertEq(par.balanceOf(address(rewardMerkleDistributor)), INITIAL_BALANCE - totalFirstRewardsAmount);
        assertEq(rewardMerkleDistributor.totalClaimedPerEpoch(firstEpochId), totalFirstRewardsAmount);
        assertEq(rewardMerkleDistributor.totalClaimed(), totalFirstRewardsAmount);
    }

    function test_RewardMerkleDistributor_ForwardExpiredRewards_SeveralsEpoch() external {
        vm.startPrank(users.admin.addr);
        uint256 expiredRewardsRecipientBalanceBefore = par.balanceOf(users.daoTreasury.addr);
        uint256 expectedTotalExpiredRewards = totalFirstRewardsAmount + totalSecondRewardsAmount;
        uint64[] memory epochIds = new uint64[](2);
        epochIds[0] = firstEpochId;
        epochIds[1] = secondEpochId;
        vm.warp(secondEpochMerkleDrop.expiryTime + 1);

        uint256 totalExpiredRewards = rewardMerkleDistributor.getExpiredEpochRewards(epochIds);
        assertEq(totalExpiredRewards, expectedTotalExpiredRewards);

        rewardMerkleDistributor.forwardExpiredRewards(epochIds);

        assertEq(
            par.balanceOf(users.daoTreasury.addr), expiredRewardsRecipientBalanceBefore + expectedTotalExpiredRewards
        );
        assertEq(par.balanceOf(address(rewardMerkleDistributor)), INITIAL_BALANCE - expectedTotalExpiredRewards);
        assertEq(rewardMerkleDistributor.totalClaimedPerEpoch(firstEpochId), totalFirstRewardsAmount);
        assertEq(rewardMerkleDistributor.totalClaimedPerEpoch(secondEpochId), totalSecondRewardsAmount);
        assertEq(rewardMerkleDistributor.totalClaimed(), expectedTotalExpiredRewards);
    }

    modifier aliceClaimedFirstEpochRewards() {
        vm.startPrank(users.alice.addr);
        bytes32[] memory proof = firstEpochMerkleTree.getProof(firstEpochLeaves, 0);

        RewardMerkleDistributor.ClaimCallData[] memory claimsData = new RewardMerkleDistributor.ClaimCallData[](1);
        claimsData[0] = RewardMerkleDistributor.ClaimCallData({
            epochId: firstEpochId,
            account: users.alice.addr,
            amount: firstRewardsAmount,
            merkleProof: proof
        });

        rewardMerkleDistributor.claims(claimsData);
        _;
    }

    function test_RewardMerkleDistributor_ForwardExpiredRewards_RewardsLeftFromOneEpoch()
        external
        aliceClaimedFirstEpochRewards
    {
        vm.startPrank(users.admin.addr);
        uint256 expiredRewardsRecipientBalanceBefore = par.balanceOf(users.daoTreasury.addr);

        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = firstEpochId;

        vm.warp(firstEpochMerkleDrop.expiryTime + 1);

        uint256 totalExpiredRewards = rewardMerkleDistributor.getExpiredEpochRewards(epochIds);
        assertEq(totalExpiredRewards, firstRewardsAmount);

        vm.expectEmit(true, true, true, true);
        emit RewardMerkleDistributor.ExpiredRewardsForwarded(firstEpochId, firstRewardsAmount);
        rewardMerkleDistributor.forwardExpiredRewards(epochIds);

        assertEq(par.balanceOf(users.daoTreasury.addr), expiredRewardsRecipientBalanceBefore + firstRewardsAmount);
        assertEq(par.balanceOf(address(rewardMerkleDistributor)), INITIAL_BALANCE - totalFirstRewardsAmount);
        assertEq(rewardMerkleDistributor.totalClaimedPerEpoch(firstEpochId), totalFirstRewardsAmount);
        assertEq(rewardMerkleDistributor.totalClaimed(), totalFirstRewardsAmount);
    }

    function test_RewardMerkleDistributor_ForwardExpiredRewards_RevertWhen_EpochIsNotExpired() external {
        vm.startPrank(users.admin.addr);
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = firstEpochId;
        vm.expectRevert(RewardMerkleDistributor.EpochNotExpired.selector);
        rewardMerkleDistributor.forwardExpiredRewards(epochIds);
    }

    function test_RewardMerkleDistributor_ForwardExpiredRewards_RevertWhen_EpochIsNotExpired_SeveralEpochs()
        external
    {
        vm.startPrank(users.admin.addr);
        uint64[] memory epochIds = new uint64[](2);
        epochIds[0] = firstEpochId;
        epochIds[1] = secondEpochId;
        vm.warp(firstEpochMerkleDrop.expiryTime + 1);

        vm.expectRevert(RewardMerkleDistributor.EpochNotExpired.selector);
        rewardMerkleDistributor.forwardExpiredRewards(epochIds);
    }

    function test_RewardMerkleDistributor_ForwardExpiredRewards_RevertWhen_EmptyEpochIds() external {
        vm.startPrank(users.admin.addr);
        uint64[] memory epochIds = new uint64[](0);
        vm.expectRevert(RewardMerkleDistributor.EmptyArray.selector);
        rewardMerkleDistributor.forwardExpiredRewards(epochIds);
    }
}
