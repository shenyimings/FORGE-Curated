// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract RewardMerkleDistributor_UpdateMerkleDrop_Integrations_Test is Integrations_Test {
    uint64 epochId = 1;
    RewardMerkleDistributor.MerkleDrop merkleDrop;
    uint256 totalRewards = INITIAL_BALANCE * 2;

    function setUp() public override {
        super.setUp();
        par.mint(address(rewardMerkleDistributor), totalRewards);
        merkleDrop = RewardMerkleDistributor.MerkleDrop({
            root: keccak256("root"),
            totalAmount: INITIAL_BALANCE,
            startTime: uint64(block.timestamp),
            expiryTime: uint64(block.timestamp) + uint64(rewardMerkleDistributor.EPOCH_LENGTH())
        });
    }

    function test_RewardMerkleDistributor_UpdateMerkleDrop() external {
        vm.startPrank(users.admin.addr);
        vm.expectEmit(true, true, true, true);
        emit RewardMerkleDistributor.MerkleDropUpdated(
            epochId, merkleDrop.root, merkleDrop.totalAmount, merkleDrop.startTime, merkleDrop.expiryTime
        );
        rewardMerkleDistributor.updateMerkleDrop(epochId, merkleDrop);
        (bytes32 root, uint256 totalAmount, uint64 startTime, uint64 expiryTime) =
            rewardMerkleDistributor.merkleDrops(epochId);

        assertEq(merkleDrop.root, root);
        assertEq(merkleDrop.totalAmount, totalAmount);
        assertEq(merkleDrop.startTime, startTime);
        assertEq(merkleDrop.expiryTime, expiryTime);
    }

    function test_RewardMerkleDistributor_UpdateMerkleDrop_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        rewardMerkleDistributor.updateMerkleDrop(epochId, merkleDrop);
    }

    function test_RewardMerkleDistributor_UpdateMerkleDrop_RevertWhen_DurationBelowEpochLength() external {
        vm.startPrank(users.admin.addr);
        merkleDrop.expiryTime = merkleDrop.expiryTime - 1;
        vm.expectRevert(abi.encodeWithSelector(RewardMerkleDistributor.EpochExpired.selector));
        rewardMerkleDistributor.updateMerkleDrop(epochId, merkleDrop);
    }
}
