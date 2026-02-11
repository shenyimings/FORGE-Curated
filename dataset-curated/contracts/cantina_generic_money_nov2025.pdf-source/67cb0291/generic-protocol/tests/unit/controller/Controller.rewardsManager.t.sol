// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import { RewardsManager, IControlledVault, IERC20 } from "../../../src/controller/RewardsManager.sol";
import { ISwapper } from "../../../src/interfaces/ISwapper.sol";

import { ControllerTest } from "./Controller.t.sol";
import { ReentrancySpy } from "../../helper/ReentrancySpy.sol";

abstract contract Controller_RewardsManager_Test is ControllerTest {
    address manager = makeAddr("manager");
    bytes32 managerRole;
    address vault = makeAddr("vault");
    address rewardAsset = makeAddr("rewardAsset");
    uint256 rewards = 100 ether;
    address vaultAsset = makeAddr("vaultAsset");

    function setUp() public virtual override {
        super.setUp();

        managerRole = controller.REWARDS_MANAGER_ROLE();
        vm.prank(admin);
        controller.grantRole(managerRole, manager);

        controller.workaround_addVault(vault);
        vm.mockCall(vault, abi.encodeWithSelector(IControlledVault.asset.selector), abi.encode(vaultAsset));
        vm.mockCall(vault, abi.encodeWithSelector(IControlledVault.controllerWithdraw.selector), "");
        vm.mockCall(rewardAsset, abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(rewards));
        controller.workaround_setRewardAsset(rewardAsset, true);
    }
}

contract Controller_RewardsManager_SellRewards_Test is Controller_RewardsManager_Test {
    uint256 minAmountOut = 1;
    bytes swapperData = "some swapper data";
    uint256 swapAmount = 50 ether;

    function setUp() public virtual override {
        super.setUp();

        vm.mockCall(vault, abi.encodeWithSelector(IControlledVault.controllerDeposit.selector), "");
        vm.mockCall(address(swapper), abi.encodeWithSelector(ISwapper.swap.selector), abi.encode(swapAmount));
    }

    function testFuzz_shouldRevert_whenCallerNotManager(address caller) external {
        vm.assume(caller != manager);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        controller.sellRewards(vault, rewardAsset, minAmountOut, swapperData);
    }

    function test_shouldRevert_whenInvalidVault() external {
        vm.expectRevert(abi.encodeWithSelector(RewardsManager.Reward_InvalidVault.selector));
        vm.prank(manager);
        controller.sellRewards(makeAddr("invalidVault"), rewardAsset, minAmountOut, swapperData);
    }

    function testFuzz_shouldRevert_whenRewardAssetNotApproved(address _rewardAsset) external {
        vm.assume(_rewardAsset != rewardAsset);
        vm.assume(_rewardAsset != vaultAsset);

        vm.expectRevert(abi.encodeWithSelector(RewardsManager.Reward_NotRewardAsset.selector));
        vm.prank(manager);
        controller.sellRewards(vault, _rewardAsset, minAmountOut, swapperData);
    }

    function test_shouldRevert_whenSameAssets() external {
        controller.workaround_setRewardAsset(vaultAsset, true);

        vm.expectRevert(abi.encodeWithSelector(RewardsManager.Reward_SameAssets.selector));
        vm.prank(manager);
        controller.sellRewards(vault, vaultAsset, minAmountOut, swapperData);
    }

    function test_shouldRevert_whenZeroRewards() external {
        vm.mockCall(rewardAsset, abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(0));

        vm.expectRevert(abi.encodeWithSelector(RewardsManager.Reward_ZeroRewards.selector));
        vm.prank(manager);
        controller.sellRewards(vault, rewardAsset, minAmountOut, swapperData);
    }

    function test_shouldSellRewards() external {
        vm.expectCall(
            vault,
            abi.encodeWithSelector(IControlledVault.controllerWithdraw.selector, rewardAsset, rewards, address(swapper))
        );
        vm.expectCall(
            address(swapper),
            abi.encodeWithSelector(
                ISwapper.swap.selector, rewardAsset, rewards, vaultAsset, minAmountOut, vault, swapperData
            )
        );
        vm.expectCall(vault, abi.encodeWithSelector(IControlledVault.controllerDeposit.selector, swapAmount));

        vm.prank(manager);
        uint256 assets = controller.sellRewards(vault, rewardAsset, minAmountOut, swapperData);
        assertEq(assets, swapAmount);
    }

    function testFuzz_shouldRevert_whenSlippageTooHigh(uint256 _minAmountOut) external {
        vm.assume(_minAmountOut > swapAmount);

        vm.expectRevert(abi.encodeWithSelector(RewardsManager.Reward_SlippageTooHigh.selector));
        vm.prank(manager);
        controller.sellRewards(vault, rewardAsset, _minAmountOut, swapperData);
    }

    function test_shouldEmit_RewardsSold() external {
        vm.expectEmit();
        emit RewardsManager.RewardsSold(vault, rewardAsset, rewards, swapAmount);

        vm.prank(manager);
        controller.sellRewards(vault, rewardAsset, minAmountOut, swapperData);
    }

    function test_shouldRevert_whenReentrant() external {
        ReentrancySpy spy = new ReentrancySpy();

        vm.mockFunction(vault, address(spy), abi.encodeWithSelector(ReentrancySpy.reenter.selector));
        vm.mockFunction(vault, address(spy), abi.encodeWithSelector(IControlledVault.controllerWithdraw.selector));
        ReentrancySpy(vault)
            .reenter(
                address(controller),
                abi.encodeWithSelector(
                    RewardsManager.sellRewards.selector, vault, rewardAsset, minAmountOut, swapperData
                )
            );

        vm.expectRevert(ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector);
        vm.prank(manager);
        controller.sellRewards(vault, rewardAsset, minAmountOut, swapperData);
    }
}

contract Controller_RewardsManager_ClaimRewards_Test is Controller_RewardsManager_Test {
    function testFuzz_shouldRevert_whenCallerNotManager(address caller) external {
        vm.assume(caller != manager);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        controller.claimRewards(vault, rewardAsset);
    }

    function test_shouldRevert_whenInvalidVault() external {
        vm.expectRevert(abi.encodeWithSelector(RewardsManager.Reward_InvalidVault.selector));
        vm.prank(manager);
        controller.claimRewards(makeAddr("invalidVault"), rewardAsset);
    }

    function testFuzz_shouldRevert_whenRewardAssetNotApproved(address _rewardAsset) external {
        vm.assume(_rewardAsset != rewardAsset);
        vm.assume(_rewardAsset != vaultAsset);

        vm.expectRevert(abi.encodeWithSelector(RewardsManager.Reward_NotRewardAsset.selector));
        vm.prank(manager);
        controller.claimRewards(vault, _rewardAsset);
    }

    function test_shouldRevert_whenSameAssets() external {
        controller.workaround_setRewardAsset(vaultAsset, true);

        vm.expectRevert(abi.encodeWithSelector(RewardsManager.Reward_SameAssets.selector));
        vm.prank(manager);
        controller.claimRewards(vault, vaultAsset);
    }

    function test_shouldRevert_whenZeroRewards() external {
        vm.mockCall(rewardAsset, abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(0));

        vm.expectRevert(abi.encodeWithSelector(RewardsManager.Reward_ZeroRewards.selector));
        vm.prank(manager);
        controller.claimRewards(vault, rewardAsset);
    }

    function test_shouldClaimRewards() external {
        vm.expectCall(
            vault,
            abi.encodeWithSelector(IControlledVault.controllerWithdraw.selector, rewardAsset, rewards, rewardsCollector)
        );

        vm.prank(manager);
        uint256 claimedRewards = controller.claimRewards(vault, rewardAsset);
        assertEq(claimedRewards, rewards);
    }

    function test_shouldEmit_RewardsClaimed() external {
        vm.expectEmit();
        emit RewardsManager.RewardsClaimed(vault, rewardAsset, rewardsCollector, rewards);

        vm.prank(manager);
        controller.claimRewards(vault, rewardAsset);
    }

    function test_shouldRevert_whenReentrant() external {
        ReentrancySpy spy = new ReentrancySpy();

        vm.mockFunction(vault, address(spy), abi.encodeWithSelector(ReentrancySpy.reenter.selector));
        vm.mockFunction(vault, address(spy), abi.encodeWithSelector(IControlledVault.controllerWithdraw.selector));
        ReentrancySpy(vault)
            .reenter(
                address(controller), abi.encodeWithSelector(RewardsManager.claimRewards.selector, vault, rewardAsset)
            );

        vm.expectRevert(ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector);
        vm.prank(manager);
        controller.claimRewards(vault, rewardAsset);
    }
}
