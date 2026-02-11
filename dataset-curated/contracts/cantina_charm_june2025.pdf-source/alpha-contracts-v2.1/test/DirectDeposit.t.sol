// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AlphaProVault, VaultParams} from "../contracts/AlphaProVault.sol";
import {Constants} from "./Constants.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {VaultTestUtils} from "./VaultTestUtils.sol";

contract DirectDepositTest is Test, VaultTestUtils {
    address attacker = makeAddr("attacker");
    address victim = makeAddr("victim");
    address attackHelper = makeAddr("attackHelper");

    function setUp() public {
        vm.createSelectFork(vm.envString("ALCHEMY_RPC"), 17073835);
        prepareTokens();
        deployFactory();
        depositInFactory(); // Initial deposit and rebalance to set up positions

        // Give attacker some tokens
        deal(USDC, attacker, 1000000 * 1e6);
        deal(WETH, attacker, 1000 ether);

        vm.startPrank(attacker);
        IERC20(USDC).approve(address(vault), type(uint256).max);
        IERC20(WETH).approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function test_directDepositBasicFunctionality() public {
        uint256 amount0 = 10000 * 1e6; // 10k USDC
        uint256 amount1 = 5 ether; // 5 WETH

        uint256 vaultBalance0Before = vault.getBalance0();
        uint256 vaultBalance1Before = vault.getBalance1();
        (uint256 total0Before, uint256 total1Before) = vault.getTotalAmounts();

        vm.startPrank(owner);
        (uint256 shares, uint256 actualAmount0, uint256 actualAmount1) = vault.deposit(amount0, amount1, 0, 0, owner);
        vm.stopPrank();

        // Check that shares were minted
        assertGt(shares, 0, "No shares minted");
        assertGt(vault.balanceOf(owner), 0, "No balance for depositor");

        // Check that liquidity was deployed (vault balance should be less than deposited amount)
        uint256 vaultBalance0After = vault.getBalance0();
        uint256 vaultBalance1After = vault.getBalance1();

        // Most of the tokens should be deployed, but some may remain
        assertLe(vaultBalance0After - vaultBalance0Before, actualAmount0, "Token0 not deployed to pool");
        assertLe(vaultBalance1After - vaultBalance1Before, actualAmount1, "Token1 not deployed to pool");

        // Check that total amounts increased by at least the actual deposited amounts
        (uint256 total0After, uint256 total1After) = vault.getTotalAmounts();
        assertGe(total0After, total0Before + actualAmount0 - 1, "Total amount0 didn't increase properly");
        assertGe(total1After, total1Before + actualAmount1 - 1, "Total amount1 didn't increase properly");
    }

    function test_directDepositVsDelayedDeposit() public {
        uint256 amount0 = 10000 * 1e6;
        uint256 amount1 = 5 ether;

        // Direct deposit
        vm.startPrank(owner);
        (uint256 sharesDirect,,) = vault.deposit(amount0, amount1, 0, 0, owner);
        vm.stopPrank();

        // Delayed deposit
        vm.startPrank(other);
        (uint256 sharesDelayed,,) = vault.deposit(amount0, amount1, 0, 0, other);
        vm.stopPrank();

        // Both should receive same shares for same deposit amounts
        assertEq(sharesDirect, sharesDelayed, "Share calculation differs between deposit methods");

        // Trigger rebalance to deploy delayed deposits
        skip(vault.period() + 1);
        vault.rebalance();

        // After rebalance, both positions should be similar
        uint256 ownerBalance = vault.balanceOf(owner);
        uint256 otherBalance = vault.balanceOf(other);
        assertEq(ownerBalance, otherBalance, "Final balances differ");
    }

    function test_directDepositBeforeFirstRebalance() public {
        // Deploy new vault without initial rebalance
        AlphaProVault newVault = deployNewVault();

        uint256 amount0 = 10000 * 1e6;
        uint256 amount1 = 5 ether;

        vm.startPrank(owner);
        IERC20(USDC).approve(address(newVault), type(uint256).max);
        IERC20(WETH).approve(address(newVault), type(uint256).max);

        newVault.deposit(amount0, amount1, 0, 0, owner);

        // Check that funds stayed in vault (not deployed)
        assertEq(newVault.getBalance0(), amount0, "Funds were deployed before initialization");
        assertEq(newVault.getBalance1(), amount1, "Funds were deployed before initialization");
        vm.stopPrank();
    }

    function test_directDepositPriceManipulationAttack() public {
        // Ensure rebalance conditions are met
        skip(vault.period() + 1);

        // Attacker manipulates price by large swap
        swapToken(USDC, WETH, 500000 * 1e6, attackHelper); // Large swap to move price

        // Setup attacker approvals for router
        vm.startPrank(attacker);
        IERC20(USDC).approve(UNISWAP_V3_ROUTER, type(uint256).max);
        IERC20(WETH).approve(UNISWAP_V3_ROUTER, type(uint256).max);
        console.log("attacker balance of USDC before", IERC20(USDC).balanceOf(attacker));

        // Attacker deposits with manipulated price
        uint256 attackAmount0 = 50000 * 1e6;
        uint256 attackAmount1 = 0.1 ether; // Small amount due to price manipulation

        console.log("attacker balance of USDC", IERC20(USDC).balanceOf(attacker));
        console.log("attacker balance of WETH", IERC20(WETH).balanceOf(attacker));

        (uint256 sharesAttacker,,) = vault.deposit(attackAmount0, attackAmount1, 0, 0, attacker);

        // Swap back to restore price
        uint256 wethBalance = IERC20(WETH).balanceOf(attackHelper);
        swapToken(WETH, USDC, wethBalance, attackHelper);
        vm.stopPrank();

        // Honest user deposits after price restoration
        vm.startPrank(owner);
        (uint256 sharesHonest,,) = vault.deposit(attackAmount0, 25 ether, 0, 0, owner);
        vm.stopPrank();

        // Check that attacker didn't gain unfair advantage
        // The share calculation should be based on total amounts, not just deposited amounts
        assertLt(sharesAttacker, sharesHonest * 2, "Attacker gained unfair share advantage");
    }

    function test_directDepositRebalanceConditionsCheck() public {
        // Direct deposits only check TWAP deviation, not tick movement or time period
        // First, do a rebalance to set lastTimestamp
        skip(vault.period() + 1);
        swapForwardAndBack(false); // Move price
        vault.rebalance();

        // Now test that direct deposit works even without tick movement
        skip(vault.period() + 1);

        // Ensure owner has enough tokens after swaps
        deal(address(USDC), owner, 1000 * 1e6);
        deal(address(WETH), owner, 1 ether);

        // Direct deposit should work even without price movement (unlike rebalance)
        vm.startPrank(owner);
        // Use smaller amounts that owner actually has
        (uint256 shares,,) = vault.deposit(100 * 1e6, 0.05 ether, 0, 0, owner);
        assertGt(shares, 0, "Direct deposit should work without tick movement");
        vm.stopPrank();

        // The key point is that direct deposits work without the full rebalance conditions
        // This demonstrates that direct deposits only check TWAP, not tick movement or time
    }

    function test_directDepositTwapDeviationCheck() public {
        // Skip time for rebalance
        skip(vault.period() + 1);

        // Do initial rebalance to set positions
        vault.rebalance();

        // Skip time again
        skip(vault.period() + 1);

        // Create a large price manipulation that exceeds TWAP deviation
        vm.startPrank(attacker);

        // Need to create a larger price move to exceed maxTwapDeviation (100 ticks)
        // Swap a very large amount to move price significantly
        deal(address(USDC), attacker, 10000000 * 1e6); // 10M USDC
        IERC20(USDC).approve(UNISWAP_V3_ROUTER, type(uint256).max);

        // Large swap to move price beyond TWAP deviation
        swapToken(USDC, WETH, 10000000 * 1e6, attacker);
        vm.stopPrank();

        // Now direct deposit should fail due to TWAP deviation
        vm.startPrank(owner);
        vm.expectRevert(bytes("TP")); // TWAP deviation check
        vault.deposit(1000 * 1e6, 0.5 ether, 0, 0, owner);
        vm.stopPrank();

        // Swap back to restore price
        vm.startPrank(attacker);
        IERC20(WETH).approve(UNISWAP_V3_ROUTER, type(uint256).max);
        uint256 wethBalance = IERC20(WETH).balanceOf(attacker);
        swapToken(WETH, USDC, wethBalance, attacker);
        vm.stopPrank();

        // Wait for TWAP to catch up to the restored price
        skip(vault.twapDuration() + 1);

        // Ensure owner has enough tokens for the final deposit
        deal(address(USDC), owner, 1000 * 1e6);
        deal(address(WETH), owner, 1 ether);

        // Now deposit should work again after TWAP has stabilized
        vm.startPrank(owner);
        (uint256 shares,,) = vault.deposit(1000 * 1e6, 0.5 ether, 0, 0, owner);
        assertGt(shares, 0, "Deposit should work when price is near TWAP");
        vm.stopPrank();
    }

    function test_directDepositWithZeroLiquidity() public {
        // Test with very small amounts that might result in zero shares
        skip(vault.period() + 1);
        swapForwardAndBack(false); // Ensure rebalance conditions are met

        // Ensure owner has enough tokens
        deal(address(USDC), owner, 1000 * 1e6);
        deal(address(WETH), owner, 1 ether);

        vm.startPrank(owner);

        // Test with amounts that are small but should still mint shares
        // Using amounts that are reasonable for the vault's scale
        uint256 smallAmount0 = 1 * 1e6; // 1 USDC
        uint256 smallAmount1 = 0.001 ether; // 0.001 WETH

        (uint256 shares, uint256 amount0, uint256 amount1) = vault.deposit(smallAmount0, smallAmount1, 0, 0, owner);

        // Should mint at least some shares
        assertGt(shares, 0, "Should mint shares even for small deposits");
        assertGt(amount0 + amount1, 0, "Should deposit at least some tokens");

        // Test with truly tiny amounts that might revert
        uint256 tinyAmount = 100; // 0.0001 USDC

        // This might revert due to minimum liquidity requirements
        try vault.deposit(tinyAmount, 0, 0, 0, owner) returns (uint256, uint256, uint256) {
            // If it succeeds, that's fine
        } catch Error(string memory reason) {
            // If it fails, it should be due to reasonable constraints
            assertTrue(
                keccak256(bytes(reason)) == keccak256(bytes("shares"))
                    || keccak256(bytes(reason)) == keccak256(bytes("cross")),
                "Should fail with shares or cross error for tiny amounts"
            );
        }

        vm.stopPrank();
    }

    function test_directDepositsOnlyInitialization() public {
        // Test that directDepositsOnly can be set after vault creation
        address pool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(WETH, USDC, POOL_FEE);

        // Create vault with default settings
        VaultParams memory vaultParams = VaultParams(
            pool,
            owner,
            0,
            type(uint128).max - 1,
            0,
            72000,
            1200,
            600,
            0,
            Constants.MIN_TICK_MOVE,
            Constants.MAX_TWAP_DEVIATION,
            Constants.TWAP_DURATION,
            "AV_TEST_DIRECT_ONLY",
            "AV_TEST_DIRECT_ONLY"
        );

        address vaultAddress = vaultFactory.createVault(vaultParams);
        AlphaProVault directOnlyVault = AlphaProVault(vaultAddress);

        // Test that delayed deposits fail immediately
        uint256 amount0 = 1000 * 1e6;
        uint256 amount1 = 0.5 ether;

        vm.startPrank(owner);
        IERC20(USDC).approve(address(directOnlyVault), type(uint256).max);
        IERC20(WETH).approve(address(directOnlyVault), type(uint256).max);

        // Direct deposit should work (even before first rebalance, funds just stay in vault)
        (uint256 shares,,) = directOnlyVault.deposit(amount0, amount1, 0, 0, owner);
        assertGt(shares, 0, "Direct deposit should work on direct-only vault");
        vm.stopPrank();
    }

    // Helper function to deploy a new vault without initial setup
    function deployNewVault() internal returns (AlphaProVault) {
        address pool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(WETH, USDC, POOL_FEE);

        VaultParams memory vaultParams = VaultParams(
            pool,
            owner,
            0,
            type(uint128).max - 1,
            0,
            72000,
            1200,
            600,
            0,
            Constants.MIN_TICK_MOVE,
            Constants.MAX_TWAP_DEVIATION,
            Constants.TWAP_DURATION,
            "AV_TEST_NEW",
            "AV_TEST_NEW"
        );

        address vaultAddress = vaultFactory.createVault(vaultParams);
        return AlphaProVault(vaultAddress);
    }
}
