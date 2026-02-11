// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import { RebalancingManager, IControlledVault, IERC20 } from "../../../src/controller/RebalancingManager.sol";
import { ISwapper } from "../../../src/interfaces/ISwapper.sol";

import { ControllerTest } from "./Controller.t.sol";
import { ReentrancySpy } from "../../helper/ReentrancySpy.sol";

abstract contract Controller_RebalancingManager_Test is ControllerTest {
    address manager = makeAddr("manager");
    bytes32 managerRole;

    function setUp() public virtual override {
        super.setUp();

        managerRole = controller.REBALANCING_MANAGER_ROLE();
        vm.prank(admin);
        controller.grantRole(managerRole, manager);
    }
}

contract Controller_RebalancingManager_Rebalance_Test is Controller_RebalancingManager_Test {
    address fromVault = makeAddr("fromVault");
    address toVault = makeAddr("toVault");
    address fromAsset = makeAddr("fromAsset");
    address toAsset = makeAddr("toAsset");
    address priceFeed = makeAddr("priceFeed");
    uint256 fromAmount = 1000e18;
    uint256 toAmount = 100e18;
    uint256 minToAmount = 10e18;
    bytes swapperData;

    function _mockVaultAsset(address vault, address asset) internal {
        vm.mockCall(vault, abi.encodeWithSelector(IControlledVault.asset.selector), abi.encode(asset));
    }

    function setUp() public virtual override {
        super.setUp();

        _mockVault(fromVault, fromAsset, 1000e18, priceFeed, 1e8, 8);
        _mockVault(toVault, toAsset, 1000e18, priceFeed, 1e8, 8);

        vm.mockCall(address(swapper), abi.encodeWithSelector(ISwapper.swap.selector), abi.encode(toAmount));
        vm.mockCall(fromAsset, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        vm.mockCall(toAsset, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(1800e18));
    }

    function testFuzz_shouldRevert_whenCallerNotManager(address caller) public {
        vm.assume(caller != manager);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        controller.rebalance(fromVault, fromAmount, toVault, minToAmount, swapperData);
    }

    function test_shouldRevert_whenFromVaultNotRegistered() public {
        vm.prank(manager);
        vm.expectRevert(RebalancingManager.Rebalance_InvalidVault.selector);
        controller.rebalance(makeAddr("invalidVault"), fromAmount, toVault, minToAmount, swapperData);
    }

    function test_shouldRevert_whenToVaultNotRegistered() public {
        vm.prank(manager);
        vm.expectRevert(RebalancingManager.Rebalance_InvalidVault.selector);
        controller.rebalance(fromVault, fromAmount, makeAddr("invalidVault"), minToAmount, swapperData);
    }

    function test_shouldRevert_whenFromAndToVaultAreSame() public {
        vm.prank(manager);
        vm.expectRevert(RebalancingManager.Rebalance_SameVault.selector);
        controller.rebalance(fromVault, fromAmount, fromVault, minToAmount, swapperData);
    }

    function test_shouldRevert_whenZeroFromAmount() public {
        vm.prank(manager);
        vm.expectRevert(RebalancingManager.Rebalance_ZeroFromAmount.selector);
        controller.rebalance(fromVault, 0, toVault, minToAmount, swapperData);
    }

    function testFuzz_shouldWithdraw_fromFromVault_whenSameAssets(uint256 _fromAmount) public {
        vm.assume(_fromAmount > 0);
        _mockVaultAsset(toVault, fromAsset);

        vm.expectCall(
            fromVault,
            abi.encodeWithSelector(IControlledVault.controllerWithdraw.selector, fromAsset, _fromAmount, toVault)
        );

        vm.prank(manager);
        controller.rebalance(fromVault, _fromAmount, toVault, minToAmount, swapperData);
    }

    function testFuzz_shouldWithdraw_fromFromVault_whenDiffAssets(uint256 _fromAmount) public {
        vm.assume(_fromAmount > 0);

        vm.expectCall(
            fromVault,
            abi.encodeWithSelector(
                IControlledVault.controllerWithdraw.selector, fromAsset, _fromAmount, address(swapper)
            )
        );

        vm.prank(manager);
        controller.rebalance(fromVault, _fromAmount, toVault, minToAmount, swapperData);
    }

    function test_shouldCallSwap_whenDiffAssets() public {
        swapperData = hex"deadbeef";

        vm.expectCall(
            address(swapper),
            abi.encodeWithSelector(
                ISwapper.swap.selector, fromAsset, fromAmount, toAsset, minToAmount, toVault, swapperData
            )
        );

        vm.prank(manager);
        controller.rebalance(fromVault, fromAmount, toVault, minToAmount, swapperData);
    }

    function test_shouldNotCallSwap_whenSameAssets() public {
        _mockVaultAsset(toVault, fromAsset);

        vm.expectCall(address(swapper), abi.encodeWithSelector(ISwapper.swap.selector), 0);

        vm.prank(manager);
        controller.rebalance(fromVault, fromAmount, toVault, minToAmount, swapperData);
    }

    function test_shouldRevert_whenToAmountLessThanMinToAmount() public {
        vm.mockCall(address(swapper), abi.encodeWithSelector(ISwapper.swap.selector), abi.encode(minToAmount - 1));

        vm.prank(manager);
        vm.expectRevert(RebalancingManager.Rebalance_SlippageTooHigh.selector);
        controller.rebalance(fromVault, fromAmount, toVault, minToAmount, swapperData);
    }

    function test_shouldDeposit_toToVault_whenDiffAssets() public {
        // swapper will return toAmount to toVault
        vm.expectCall(toVault, abi.encodeWithSelector(IControlledVault.controllerDeposit.selector, toAmount));

        vm.prank(manager);
        controller.rebalance(fromVault, fromAmount, toVault, minToAmount, swapperData);
    }

    function test_shouldDeposit_toToVault_whenSameAssets() public {
        _mockVaultAsset(toVault, fromAsset);

        // controller will withdraw fromAmount to toVault
        vm.expectCall(toVault, abi.encodeWithSelector(IControlledVault.controllerDeposit.selector, fromAmount));

        vm.prank(manager);
        controller.rebalance(fromVault, fromAmount, toVault, minToAmount, swapperData);
    }

    function test_shouldRevert_whenSlippageGreaterThanMax_whenDiffAssets() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encode(1000e18);
        data[1] = abi.encode(990e18); // 0.5%/10e18 slippage
        vm.mockCalls(fromVault, abi.encodeWithSelector(IControlledVault.totalNormalizedAssets.selector), data);

        controller.workaround_setMaxProtocolRebalanceSlippage(40); // 0.4%

        vm.expectRevert(RebalancingManager.Rebalance_SlippageTooHigh.selector);
        vm.prank(manager);
        controller.rebalance(fromVault, fromAmount, toVault, minToAmount, swapperData);
    }

    function test_shouldRevert_whenSlippageGreaterThanSafetyBuffer_whenDiffAssets() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encode(1000e18);
        data[1] = abi.encode(990e18); // 0.5%/10e18 slippage
        vm.mockCalls(fromVault, abi.encodeWithSelector(IControlledVault.totalNormalizedAssets.selector), data);

        controller.workaround_setMaxProtocolRebalanceSlippage(200); // 2%
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(1999e18)); // 1e18

        vm.expectRevert(RebalancingManager.Rebalance_SlippageTooHigh.selector);
        vm.prank(manager);
        controller.rebalance(fromVault, fromAmount, toVault, minToAmount, swapperData);
    }

    function test_shouldRevert_whenNoSafetyBufferAfterRebalance_whenDiffAssets() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encode(1000e18);
        data[1] = abi.encode(1000e18); // no slippage
        vm.mockCalls(fromVault, abi.encodeWithSelector(IControlledVault.totalNormalizedAssets.selector), data);

        controller.workaround_setMaxProtocolRebalanceSlippage(200); // 2%
        vm.mockCall(
            address(share),
            abi.encodeWithSelector(IERC20.totalSupply.selector),
            abi.encode(2000e18) // no safety buffer
        );

        vm.expectRevert(RebalancingManager.Rebalance_SlippageTooHigh.selector);
        vm.prank(manager);
        controller.rebalance(fromVault, fromAmount, toVault, minToAmount, swapperData);
    }

    function test_shouldNotRevert_whenSlippageGreaterThanSafetyBuffer_whenDiffAssets_whenSkippingSafetyBufferCheck()
        public
    {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encode(1000e18);
        data[1] = abi.encode(990e18); // 0.5%/10e18 slippage
        vm.mockCalls(fromVault, abi.encodeWithSelector(IControlledVault.totalNormalizedAssets.selector), data);

        controller.workaround_setSkipNextRebalanceSafetyBufferCheck(true);
        controller.workaround_setMaxProtocolRebalanceSlippage(200); // 2%
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(2010e18));

        vm.prank(manager);
        controller.rebalance(fromVault, fromAmount, toVault, minToAmount, swapperData);
    }

    function test_shouldDisableNextSlippageBufferCheck_afterSkippingItOnce() public {
        controller.workaround_setSkipNextRebalanceSafetyBufferCheck(true);

        assertTrue(controller.skipNextRebalanceSafetyBufferCheck());

        // First rebalance should pass
        vm.prank(manager);
        controller.rebalance(fromVault, fromAmount, toVault, minToAmount, swapperData);

        assertFalse(controller.skipNextRebalanceSafetyBufferCheck());
    }

    function test_shouldEmit_Rebalanced() public {
        vm.expectEmit();
        emit RebalancingManager.Rebalanced(fromVault, toVault, fromAmount, toAmount);

        vm.prank(manager);
        controller.rebalance(fromVault, fromAmount, toVault, minToAmount, swapperData);
    }

    function test_shouldRevert_whenReentrant() public {
        ReentrancySpy spy = new ReentrancySpy();

        vm.mockFunction(address(swapper), address(spy), abi.encodeWithSelector(ReentrancySpy.reenter.selector));
        vm.mockFunction(address(swapper), address(spy), abi.encodeWithSelector(ISwapper.swap.selector));
        ReentrancySpy(address(swapper))
            .reenter(
                address(controller),
                abi.encodeWithSelector(
                    RebalancingManager.rebalance.selector, fromVault, fromAmount, toVault, minToAmount, swapperData
                )
            );

        vm.expectRevert(ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector);
        vm.prank(manager);
        controller.rebalance(fromVault, fromAmount, toVault, minToAmount, swapperData);
    }
}
