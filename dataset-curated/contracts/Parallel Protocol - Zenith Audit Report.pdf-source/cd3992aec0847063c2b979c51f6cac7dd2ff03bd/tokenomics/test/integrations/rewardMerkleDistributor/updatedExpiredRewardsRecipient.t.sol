// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract RewardMerkleDistributor_UpdateExpiredRewardsRecipient_Integrations_Test is Integrations_Test {
    address newExpiredRewardsRecipient = makeAddr("newExpiredRewardsRecipient");

    function test_RewardMerkleDistributor_UpdateExpiredRewardsRecipient() external {
        vm.startPrank(users.admin.addr);
        vm.expectEmit(true, true, true, true);
        emit RewardMerkleDistributor.ExpiredRewardsRecipientUpdated(newExpiredRewardsRecipient);
        rewardMerkleDistributor.updateExpiredRewardsRecipient(newExpiredRewardsRecipient);
        assertEq(rewardMerkleDistributor.expiredRewardsRecipient(), newExpiredRewardsRecipient);
    }

    function test_RewardMerkleDistributor_UpdateExpiredRewardsRecipient_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        rewardMerkleDistributor.updateExpiredRewardsRecipient(users.hacker.addr);
    }

    function test_RewardMerkleDistributor_UpdateExpiredRewardsRecipient_RevertWhen_IsZeroAddress() external {
        vm.startPrank(users.admin.addr);
        vm.expectRevert(RewardMerkleDistributor.AddressZero.selector);
        rewardMerkleDistributor.updateExpiredRewardsRecipient(address(0));
    }
}
