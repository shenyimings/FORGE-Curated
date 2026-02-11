// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { ConfigManager } from "../../../src/controller/ConfigManager.sol";

import { ControllerTest } from "./Controller.t.sol";

abstract contract Controller_ConfigManager_Test is ControllerTest {
    address manager = makeAddr("manager");
    bytes32 managerRole;

    function setUp() public virtual override {
        super.setUp();

        managerRole = controller.CONFIG_MANAGER_ROLE();
        vm.prank(admin);
        controller.grantRole(managerRole, manager);
    }
}

contract Controller_ConfigManager_SetRewardsCollector_Test is Controller_ConfigManager_Test {
    function testFuzz_shouldRevert_whenCallerNotConfigManager(address caller) public {
        vm.assume(caller != manager);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        controller.setRewardsCollector(rewardsCollector);
    }

    function test_shouldRevert_whenRewardsCollectorZeroAddress() public {
        vm.expectRevert(ConfigManager.Config_RewardsCollectorZeroAddress.selector);
        vm.prank(manager);
        controller.setRewardsCollector(address(0));
    }

    function testFuzz_shouldSetRewardsCollector(address newRewardsCollector) public {
        vm.assume(newRewardsCollector != address(0));

        vm.prank(manager);
        controller.setRewardsCollector(newRewardsCollector);

        assertEq(controller.rewardsCollector(), newRewardsCollector);
    }

    function test_shouldEmit_RewardsCollectorUpdated() public {
        address rewardsCollector1 = makeAddr("rewardsCollector1");

        vm.expectEmit();
        emit ConfigManager.RewardsCollectorUpdated(rewardsCollector, rewardsCollector1);

        vm.prank(manager);
        controller.setRewardsCollector(rewardsCollector1);

        address rewardsCollector2 = makeAddr("rewardsCollector2");

        vm.expectEmit();
        emit ConfigManager.RewardsCollectorUpdated(rewardsCollector1, rewardsCollector2);

        vm.prank(manager);
        controller.setRewardsCollector(rewardsCollector2);
    }
}

contract Controller_ConfigManager_SetRewardAsset_Test is Controller_ConfigManager_Test {
    address rewardAsset = makeAddr("rewardAsset");

    function testFuzz_shouldRevert_whenCallerNotConfigManager(address caller) public {
        vm.assume(caller != manager);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        controller.setRewardAsset(rewardAsset, true);
    }

    function test_shouldRevert_whenRewardAssetZeroAddress() public {
        vm.expectRevert(ConfigManager.Config_RewardAssetZeroAddress.selector);
        vm.prank(manager);
        controller.setRewardAsset(address(0), true);
    }

    function testFuzz_shouldSetRewardAsset(address newRewardAsset) public {
        vm.assume(newRewardAsset != address(0));

        vm.prank(manager);
        controller.setRewardAsset(newRewardAsset, true);
        assertEq(controller.isRewardAsset(newRewardAsset), true);

        vm.prank(manager);
        controller.setRewardAsset(newRewardAsset, false);
        assertEq(controller.isRewardAsset(newRewardAsset), false);
    }

    function test_shouldEmit_RewardAssetUpdated() public {
        vm.expectEmit();
        emit ConfigManager.RewardAssetUpdated(rewardAsset, true);

        vm.prank(manager);
        controller.setRewardAsset(rewardAsset, true);

        vm.expectEmit();
        emit ConfigManager.RewardAssetUpdated(rewardAsset, false);

        vm.prank(manager);
        controller.setRewardAsset(rewardAsset, false);
    }
}

contract Controller_ConfigManager_SetSafetyBufferYieldDeduction_Test is Controller_ConfigManager_Test {
    function testFuzz_shouldRevert_whenCallerNotManager(address caller) external {
        vm.assume(caller != manager);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        controller.setSafetyBufferYieldDeduction(0);
    }

    function testFuzz_shouldUpdateSafetyBufferYieldDeduction(uint256 buffer) external {
        vm.prank(manager);
        controller.setSafetyBufferYieldDeduction(buffer);

        assertEq(controller.safetyBufferYieldDeduction(), buffer);
    }

    function test_shouldEmit_SafetyBufferYieldDeductionUpdated() external {
        uint256 oldBuffer = 10e18;
        uint256 newBuffer = 9e18;
        controller.workaround_setSafetyBufferYieldDeduction(oldBuffer);

        vm.expectEmit();
        emit ConfigManager.SafetyBufferYieldDeductionUpdated(oldBuffer, newBuffer);

        vm.prank(manager);
        controller.setSafetyBufferYieldDeduction(newBuffer);
    }
}

contract Controller_ConfigManager_SetMaxProtocolRebalanceSlippage_Test is Controller_ConfigManager_Test {
    function testFuzz_shouldRevert_whenCallerNotManager(address caller) external {
        vm.assume(caller != manager);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        controller.setMaxProtocolRebalanceSlippage(0);
    }

    function testFuzz_shouldRevert_whenInvalidMaxSlippage(uint256 maxSlippage) external {
        maxSlippage = bound(maxSlippage, controller.MAX_BPS() + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(ConfigManager.Config_InvalidMaxSlippage.selector));
        vm.prank(manager);
        controller.setMaxProtocolRebalanceSlippage(maxSlippage);
    }

    function testFuzz_shouldUpdateMaxProtocolRebalanceSlippage(uint256 maxSlippage) external {
        maxSlippage = bound(maxSlippage, 0, controller.MAX_BPS());

        vm.prank(manager);
        controller.setMaxProtocolRebalanceSlippage(maxSlippage);

        assertEq(controller.maxProtocolRebalanceSlippage(), maxSlippage);
    }

    function test_shouldEmit_MaxProtocolRebalanceSlippageUpdated() external {
        uint256 oldMaxSlippage = 200; // 2%
        uint256 newMaxSlippage = 150; // 1.5%
        controller.workaround_setMaxProtocolRebalanceSlippage(oldMaxSlippage);

        vm.expectEmit();
        emit ConfigManager.MaxProtocolRebalanceSlippageUpdated(oldMaxSlippage, newMaxSlippage);

        vm.prank(manager);
        controller.setMaxProtocolRebalanceSlippage(newMaxSlippage);
    }
}
