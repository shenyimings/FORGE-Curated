// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Base.t.sol";

contract RewardMerkleDistributor_Constructor_Integrations_Test is Base_Test {
    function setUp() public override {
        super.setUp();
        rewardMerkleDistributor = _deployRewardMerkleDistributor(
            address(accessManager), address(bridgeableTokenMock), users.daoTreasury.addr
        );
    }

    function test_RewardMerkleDistributor_Constructor() external view {
        assertEq(rewardMerkleDistributor.authority(), address(accessManager));
        assertEq(address(rewardMerkleDistributor.TOKEN()), address(bridgeableTokenMock));
        assertEq(rewardMerkleDistributor.expiredRewardsRecipient(), users.daoTreasury.addr);
    }

    function test_RewardMerkleDistributor_Constructor_RevertWhen_ExpiredRewardsRecipientIsZeroAddress() external {
        vm.expectRevert(RewardMerkleDistributor.AddressZero.selector);
        new RewardMerkleDistributor(users.admin.addr, address(par), address(0));
    }
}
