// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { SingleStrategyVault as Vault, IERC20, IController, IERC4626 } from "../../src/vault/SingleStrategyVault.sol";

abstract contract SingleStrategyVaultForkTest is Test {
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC4626 constant USDC_STRATEGY = IERC4626(0x074134A2784F4F66b6ceD6f68849382990Ff3215);

    Vault vault;

    address controller = makeAddr("controller");
    address manager = makeAddr("manager");
    address[4] users = [makeAddr("user1"), makeAddr("user2"), makeAddr("user3"), makeAddr("user4")];
    uint256 maxErrorDelta = 3;

    function setUp() public virtual {
        vm.createSelectFork("mainnet");

        vault = new Vault(USDC, IController(controller), USDC_STRATEGY, manager);

        vm.prank(manager);
        vault.setAutoAllocationThreshold(100e6); // 100 USDC

        for (uint256 i; i < users.length; ++i) {
            deal(address(USDC), users[i], 1_000_000e6); // 1,000,000 USDC
        }

        vm.mockCall(controller, abi.encodeWithSelector(IController.deposit.selector), abi.encode(1));
        vm.mockCall(controller, abi.encodeWithSelector(IController.withdraw.selector), abi.encode(1));
    }
}

contract SingleStrategyVault_Strategy_ForkTest is SingleStrategyVaultForkTest {
    function test_shouldAutoAllocate_whenAboveThreshold() public {
        uint256 depositAssets = 200e6; // 200 USDC

        vm.startPrank(users[0]);
        USDC.approve(address(vault), depositAssets);
        vault.deposit(depositAssets, users[0]);
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(vault)), 0);
        assertApproxEqAbs(vault.totalAssets(), depositAssets, maxErrorDelta); // strategy rounds down
    }

    function test_shouldNotAutoAllocate_whenBelowThreshold_whenMultipleDeposits() public {
        uint256 depositAssets1 = 50e6; // 50 USDC
        uint256 depositAssets2 = 30e6; // 30 USDC

        vm.startPrank(users[0]);
        USDC.approve(address(vault), depositAssets1);
        vault.deposit(depositAssets1, users[0]);
        vm.stopPrank();

        vm.startPrank(users[1]);
        USDC.approve(address(vault), depositAssets2);
        vault.deposit(depositAssets2, users[1]);
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(vault)), depositAssets1 + depositAssets2);
        assertEq(vault.totalAssets(), depositAssets1 + depositAssets2);
    }

    function test_shouldDeallocate_whenWithdraw_whenInsufficientUnallocatedAssets() public {
        uint256 allocatedDeposit = 500e6; // 500 USDC
        uint256 unallocatedDeposit = 40e6; // 40 USDC

        vm.startPrank(users[0]);
        USDC.approve(address(vault), allocatedDeposit);
        vault.deposit(allocatedDeposit, address(this));
        vm.stopPrank();

        vm.startPrank(users[1]);
        USDC.approve(address(vault), unallocatedDeposit);
        vault.deposit(unallocatedDeposit, address(this));
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(vault)), unallocatedDeposit);
        assertApproxEqAbs(vault.totalAssets(), allocatedDeposit + unallocatedDeposit, maxErrorDelta); // strategy rounds
            // down

        vm.expectCall(
            address(USDC_STRATEGY),
            abi.encodeWithSelector(
                IERC4626.withdraw.selector, allocatedDeposit - unallocatedDeposit, address(vault), address(vault)
            )
        );

        vm.prank(users[0]);
        vault.withdraw(allocatedDeposit, users[0], users[0]);

        assertEq(USDC.balanceOf(address(vault)), 0);
        assertApproxEqAbs(vault.totalAssets(), unallocatedDeposit, maxErrorDelta); // strategy rounds down
    }
}
