// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import {
    SingleStrategyVault as Vault,
    IERC20,
    IController,
    IERC4626
} from "../../../src/vault/SingleStrategyVault.sol";

import { SingleStrategyVaultHarness as VaultHarness } from "../../harness/SingleStrategyVaultHarness.sol";

abstract contract SingleStrategyVaultTest is Test {
    VaultHarness vault;

    address asset = makeAddr("asset");
    address controller = makeAddr("controller");
    address strategy = makeAddr("strategy");
    address manager = makeAddr("manager");

    uint256 assets = 420e18;
    uint256 shares = 2 * assets;

    function setUp() public virtual {
        vm.mockCall(asset, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
        vm.mockCall(asset, abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(0));
        vm.mockCall(strategy, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(address(asset)));

        vault = new VaultHarness(IERC20(asset), IController(controller), IERC4626(strategy), manager);
    }
}

contract SingleStrategyVault_Constructor_Test is SingleStrategyVaultTest {
    function test_shouldSetInitialValues() public view {
        assertEq(address(vault.asset()), asset);
        assertEq(address(vault.controller()), controller);
        assertEq(address(vault.strategy()), strategy);
        assertEq(address(vault.manager()), manager);
        assertEq(vault.autoAllocationThreshold(), 0);
    }

    function test_shouldRevert_whenZeroStrategy() public {
        vm.expectRevert(Vault.ZeroStrategy.selector);
        new VaultHarness(IERC20(asset), IController(controller), IERC4626(address(0)), manager);
    }

    function test_shouldRevert_whenStrategyAssetMismatch() public {
        vm.mockCall(strategy, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(makeAddr("diffAsset")));

        vm.expectRevert(Vault.MismatchedAsset.selector);
        new VaultHarness(IERC20(asset), IController(controller), IERC4626(strategy), manager);
    }

    function test_shouldApproveStrategy() public {
        vm.expectCall(asset, abi.encodeWithSelector(IERC20.approve.selector, strategy, type(uint256).max));

        new VaultHarness(IERC20(asset), IController(controller), IERC4626(strategy), manager);
    }
}

contract SingleStrategyVault_Allocate_Test is SingleStrategyVaultTest {
    function setUp() public override {
        super.setUp();

        vm.mockCall(strategy, abi.encodeWithSelector(IERC4626.deposit.selector), abi.encode(shares));
    }

    function test_shouldRevert_whenCallerNotManager() public {
        vm.prank(makeAddr("notManager"));
        vm.expectRevert(Vault.CallerNotManager.selector);
        vault.allocate(assets);
    }

    function test_shouldCallStrategyDeposit() public {
        vm.expectCall(strategy, abi.encodeWithSelector(IERC4626.deposit.selector, assets, address(vault)));

        vm.prank(manager);
        vault.allocate(assets);
    }

    function test_shouldEmit_Allocate() public {
        vm.expectEmit();
        emit Vault.Allocate(strategy, assets);

        vm.prank(manager);
        vault.allocate(assets);
    }

    function test_shouldReturnShares() public {
        vm.prank(manager);
        assertEq(vault.allocate(assets), shares);
    }
}

contract SingleStrategyVault_Deallocate_Test is SingleStrategyVaultTest {
    function setUp() public override {
        super.setUp();

        vm.mockCall(strategy, abi.encodeWithSelector(IERC4626.withdraw.selector), abi.encode(shares));
    }

    function test_shouldRevert_whenCallerNotManager() public {
        vm.prank(makeAddr("notManager"));
        vm.expectRevert(Vault.CallerNotManager.selector);
        vault.deallocate(assets);
    }

    function test_shouldCallStrategyWithdraw() public {
        vm.expectCall(strategy, abi.encodeWithSelector(IERC4626.withdraw.selector, assets, address(vault)));

        vm.prank(manager);
        vault.deallocate(assets);
    }

    function test_shouldEmit_Deallocate() public {
        vm.expectEmit();
        emit Vault.Deallocate(strategy, assets);

        vm.prank(manager);
        vault.deallocate(assets);
    }

    function test_shouldReturnShares() public {
        vm.prank(manager);
        assertEq(vault.deallocate(assets), shares);
    }
}

contract SingleStrategyVault_SetAutoAllocationThreshold_Test is SingleStrategyVaultTest {
    function test_shouldRevert_whenCallerNotManager() public {
        vm.prank(makeAddr("notManager"));
        vm.expectRevert(Vault.CallerNotManager.selector);
        vault.setAutoAllocationThreshold(1);
    }

    function test_shouldSetThreshold(uint256 threshold) public {
        vm.prank(manager);
        vault.setAutoAllocationThreshold(threshold);

        assertEq(vault.autoAllocationThreshold(), threshold);
    }

    function test_shouldEmit_SetAutoAllocationThreshold(uint256 threshold) public {
        vm.expectEmit();
        emit Vault.SetAutoAllocationThreshold(threshold);

        vm.prank(manager);
        vault.setAutoAllocationThreshold(threshold);
    }
}

contract SingleStrategyVault_AdditionalOwnedAssets_Test is SingleStrategyVaultTest {
    function testFuzz_shouldReturnAllocatedAssets(uint256 allocatedAssets) public {
        vm.mockCall(strategy, abi.encodeWithSelector(IERC20.balanceOf.selector, address(vault)), abi.encode(shares));
        vm.mockCall(
            strategy, abi.encodeWithSelector(IERC4626.convertToAssets.selector, shares), abi.encode(allocatedAssets)
        );

        assertEq(vault.exposed_additionalOwnedAssets(), allocatedAssets);
    }
}

contract SingleStrategyVault_AdditionalAvailableAssets_Test is SingleStrategyVaultTest {
    function testFuzz_shouldReturnAvailableAssets(uint256 availableAssets) public {
        vm.mockCall(
            strategy, abi.encodeWithSelector(IERC4626.maxWithdraw.selector, address(vault)), abi.encode(availableAssets)
        );

        assertEq(vault.exposed_additionalAvailableAssets(), availableAssets);
    }
}

contract SingleStrategyVault_BeforeWithdraw_Test is SingleStrategyVaultTest {
    function testFuzz_shouldDeallocateFromStrategy_whenInsufficientUnallocated(
        uint256 withdrawAssets,
        uint256 unallocatedAssets
    )
        public
    {
        vm.assume(withdrawAssets > unallocatedAssets);
        uint256 deallocateAssets = withdrawAssets - unallocatedAssets;

        vm.mockCall(
            asset, abi.encodeWithSelector(IERC20.balanceOf.selector, address(vault)), abi.encode(unallocatedAssets)
        );
        vm.mockCall(strategy, abi.encodeWithSelector(IERC4626.withdraw.selector), abi.encode(shares));

        vm.expectCall(
            strategy,
            abi.encodeWithSelector(IERC4626.withdraw.selector, deallocateAssets, address(vault), address(vault))
        );

        vault.exposed_beforeWithdraw(withdrawAssets);
    }

    function testFuzz_shouldNotDeallocateFromStrategy_whenSufficientUnallocated(
        uint256 withdrawAssets,
        uint256 unallocatedAssets
    )
        public
    {
        vm.assume(unallocatedAssets >= withdrawAssets);

        vm.mockCall(
            asset, abi.encodeWithSelector(IERC20.balanceOf.selector, address(vault)), abi.encode(unallocatedAssets)
        );

        // expect no call
        vm.expectCall(strategy, abi.encodeWithSelector(IERC4626.withdraw.selector), 0);

        vault.exposed_beforeWithdraw(withdrawAssets);
    }
}

contract SingleStrategyVault_AfterDeposit_Test is SingleStrategyVaultTest {
    uint256 threshold = 10e18;

    function setUp() public override {
        super.setUp();

        vm.prank(manager);
        vault.setAutoAllocationThreshold(threshold);
    }

    function testFuzz_shouldAllocateToStrategy_whenAboveThreshold(uint256 depositAssets) public {
        vm.assume(depositAssets >= threshold);

        vm.mockCall(strategy, abi.encodeWithSelector(IERC4626.deposit.selector), abi.encode(shares));

        vm.expectCall(strategy, abi.encodeWithSelector(IERC4626.deposit.selector, depositAssets, address(vault)));

        vault.exposed_afterDeposit(depositAssets);
    }

    function testFuzz_shouldNotAllocateToStrategy_whenBelowThreshold(uint256 depositAssets) public {
        vm.assume(depositAssets < threshold);

        // expect no call
        vm.expectCall(strategy, abi.encodeWithSelector(IERC4626.deposit.selector), 0);

        vault.exposed_afterDeposit(depositAssets);
    }
}
