// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {SetupWithdrawalQueue} from "./SetupWithdrawalQueue.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Test} from "forge-std/Test.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";

contract ForceRebalanceTest is Test, SetupWithdrawalQueue {
    using SafeCast for uint256;

    address socializer;

    function setUp() public override {
        super.setUp();
        pool.depositETH{value: 100 ether}(address(this), address(0));

        socializer = makeAddr("socializer");

        bytes32 ROLE_SOCIALIZER = pool.LOSS_SOCIALIZER_ROLE();
        vm.prank(owner);
        pool.grantRole(ROLE_SOCIALIZER, socializer);
    }

    function _mintMaxStethShares(address _account) internal {
        uint256 capacity = pool.remainingMintingCapacitySharesOf(_account, 0);
        assertGt(capacity, 0, "expected positive minting capacity");

        vm.prank(_account);
        pool.mintStethShares(capacity);
    }

    function _simulateLoss(uint256 _loss) internal {
        dashboard.mock_simulateRewards(-_loss.toInt256());
    }

    function _calcLossToBreachThreshold(address _account) internal view returns (uint256 lossToBreachThreshold) {
        uint256 mintedSteth = steth.getPooledEthByShares(pool.mintedStethSharesOf(_account));
        uint256 assets = pool.assetsOf(_account);
        uint256 threshold = pool.poolForcedRebalanceThresholdBP();

        // liability / (assets - x) = (1 - threshold)
        // x = assets - liability / (1 - threshold)
        lossToBreachThreshold =
            assets - (mintedSteth * pool.TOTAL_BASIS_POINTS()) / (pool.TOTAL_BASIS_POINTS() - threshold);

        // scale loss to user's share of the pool
        lossToBreachThreshold = (lossToBreachThreshold * pool.totalAssets()) / assets;
    }

    function test_ForceRebalance_CannotRebalanceWithdrawalQueue() public {
        _mintMaxStethShares(address(this));
        withdrawalQueue.requestWithdrawal(
            address(this), pool.balanceOf(address(this)), pool.mintedStethSharesOf(address(this))
        );

        _simulateLoss(_calcLossToBreachThreshold(address(withdrawalQueue)));

        vm.prank(socializer);
        vm.expectRevert(StvStETHPool.CannotRebalanceWithdrawalQueue.selector);
        pool.forceRebalance(address(withdrawalQueue));
    }

    function test_ForceRebalanceAndSocializeLoss_CannotRebalanceWithdrawalQueue() public {
        // Enable loss socialization
        vm.prank(owner);
        pool.setMaxLossSocializationBP(100_00); // 100%

        _mintMaxStethShares(address(this));
        withdrawalQueue.requestWithdrawal(
            address(this), pool.balanceOf(address(this)), pool.mintedStethSharesOf(address(this))
        );

        _simulateLoss(pool.totalAssets() - 100 ether);

        vm.prank(socializer);
        vm.expectRevert(StvStETHPool.CannotRebalanceWithdrawalQueue.selector);
        pool.forceRebalanceAndSocializeLoss(address(withdrawalQueue));
    }
}
