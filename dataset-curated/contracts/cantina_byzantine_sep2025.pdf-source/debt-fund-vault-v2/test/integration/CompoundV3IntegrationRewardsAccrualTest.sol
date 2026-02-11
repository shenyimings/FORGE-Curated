// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 [Byzantine Finance]
// The implementation of this contract was inspired by Morpho Vault V2, developed by the Morpho Association in 2025.
pragma solidity ^0.8.0;

import "./CompoundV3IntegrationTest.sol";

contract CompoundV3IntegrationRewardsAccrualTest is CompoundV3IntegrationTest {
    uint256 internal initialDeposit = 1e12;

    function setUp() public virtual override {
        super.setUp();

        vault.deposit(initialDeposit, address(this));

        vm.prank(allocator);
        vault.allocate(address(compoundAdapter), hex"", initialDeposit);

        assertApproxEqAbs(vault.allocation(compoundAdapter.adapterId()), initialDeposit, 1 wei);
    }

    /// forge-config: default.isolate = true
    function testCompoundRewardsAccrual(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, 365 days);

        CometRewardsInterface.RewardOwed memory rewardOwed =
            cometRewards.getRewardOwed(address(comet), address(compoundAdapter));

        uint256 rewardsBefore = rewardOwed.owed;
        skip(elapsed);
        uint256 rewardsAfter = cometRewards.getRewardOwed(address(comet), address(compoundAdapter)).owed;

        assertGe(rewardsAfter, rewardsBefore);
    }
}
