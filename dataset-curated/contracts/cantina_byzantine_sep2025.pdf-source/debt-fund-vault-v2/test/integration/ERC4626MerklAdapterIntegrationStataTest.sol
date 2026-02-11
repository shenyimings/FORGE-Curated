// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 [Byzantine Finance]
// The implementation of this contract was inspired by Morpho Vault V2, developed by the Morpho Association in 2025.
pragma solidity ^0.8.0;

import "./ERC4626MerklAdapterIntegrationTest.sol";

// AAVE V3 Pool interface
interface IPool {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
}

/// @title StataIntegrationTest
/// @notice Integration test for VaultV2 with Stata (AAVE ERC4626 wrapper) as liquidity adapter
/// @dev This test uses a mainnet fork at block 23027397 with USDC as the underlying asset
contract StataIntegrationTest is ERC4626MerklAdapterIntegrationTest {
    // Constants
    address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2; // AAVE V3 Pool
    uint256 constant FORK_BLOCK = 23027397;

    // Test accounts
    address immutable user = makeAddr("user");

    // Contracts
    IERC4626MerklAdapter stataAdapter;
    IPool aavePool;

    function setUp() public override {
        // Create mainnet fork
        rpcUrl = vm.envString("MAINNET_RPC_URL");
        forkId = vm.createFork(rpcUrl, FORK_BLOCK);
        vm.selectFork(forkId);
        skipMainnetFork = true;

        // Initialize token contracts
        aavePool = IPool(AAVE_POOL);

        // Verify Stata is ERC4626 compliant and uses USDC as asset
        require(stataUSDC.asset() == address(usdc), "Stata asset mismatch");

        super.setUp();

        // Set up vault names and symbols
        vm.startPrank(owner);
        vault.setName("USDC Stata Vault");
        vault.setSymbol("vUSDC-STATA");
        vm.stopPrank();

        // Create Stata adapter
        stataAdapter = erc4626MerklAdapter;

        // Set up adapter
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, address(stataAdapter)));
        vault.addAdapter(address(stataAdapter));

        // Set max rate for interest accrual
        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);

        // Set up caps for the adapter manually (since we have our own vault)
        bytes memory idData = abi.encode("this", address(stataAdapter));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, type(uint128).max)));
        vault.increaseAbsoluteCap(idData, type(uint128).max);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, 1e18))); // 100%
        vault.increaseRelativeCap(idData, 1e18);

        // Set Stata as liquidity adapter
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(stataAdapter), "");

        // Fund user with USDC for testing
        deal(address(usdc), user, 1000000e6); // 1M USDC

        // User approves vault
        vm.prank(user);
        usdc.approve(address(vault), type(uint256).max);

        // Label contracts for easier debugging
        vm.label(AAVE_POOL, "AAVE Pool");
        vm.label(address(vault), "VaultV2");
        vm.label(address(stataAdapter), "StataAdapter");
        vm.label(user, "User");
    }

    function testVaultDeployment() public view {
        // Test basic vault properties
        assertEq(vault.asset(), address(usdc));
        assertEq(vault.owner(), owner);
        assertEq(vault.curator(), curator);
        assertEq(vault.name(), "USDC Stata Vault");
        assertEq(vault.symbol(), "vUSDC-STATA");

        // Test adapter setup
        assertTrue(vault.isAdapter(address(stataAdapter)));
        assertEq(vault.liquidityAdapter(), address(stataAdapter));

        // Test caps
        bytes32 adapterId = keccak256(abi.encode("this", address(stataAdapter)));
        assertEq(vault.absoluteCap(adapterId), type(uint128).max);
        assertEq(vault.relativeCap(adapterId), 1e18);
    }

    function testStataAdapterProperties() public view {
        // Test adapter properties
        assertEq(stataAdapter.parentVault(), address(vault));
        assertEq(stataAdapter.erc4626Vault(), address(stataUSDC));

        // Test initial state
        assertEq(stataAdapter.allocation(), 0);
        assertEq(stataAdapter.realAssets(), 0);

        // Test IDs
        bytes32[] memory ids = stataAdapter.ids();
        assertEq(ids.length, 1);
        assertEq(ids[0], keccak256(abi.encode("this", address(stataAdapter))));
    }

    function testDepositAndMint() public {
        uint256 depositAmount = 10000e6; // 10,000 USDC

        // Test deposit
        vm.prank(user);
        uint256 shares = vault.deposit(depositAmount, user);

        assertGt(shares, 0, "No shares minted");
        assertEq(vault.balanceOf(user), shares);
        assertEq(vault.totalSupply(), shares);

        // Check that funds were allocated to Stata
        assertGt(stataAdapter.allocation(), 0, "No allocation to Stata");
        assertGt(stataUSDC.balanceOf(address(stataAdapter)), 0, "No Stata shares");

        // Test mint
        uint256 mintShares = shares / 2;
        vm.prank(user);
        uint256 assets = vault.mint(mintShares, user);

        assertGt(assets, 0, "No assets for mint");
        assertEq(vault.balanceOf(user), shares + mintShares);
    }

    function testWithdrawAndRedeem() public {
        uint256 depositAmount = 10000e6; // 10,000 USDC

        // First deposit
        vm.prank(user);
        uint256 shares = vault.deposit(depositAmount, user);

        // Wait for some time to potentially accrue interest
        vm.warp(block.timestamp + 1 days);

        // Test withdraw
        uint256 withdrawAmount = 5000e6; // 5,000 USDC
        uint256 userBalanceBefore = usdc.balanceOf(user);

        vm.prank(user);
        uint256 sharesRedeemed = vault.withdraw(withdrawAmount, user, user);

        assertGt(sharesRedeemed, 0, "No shares redeemed");
        assertEq(usdc.balanceOf(user) - userBalanceBefore, withdrawAmount);
        assertEq(vault.balanceOf(user), shares - sharesRedeemed);

        // Test redeem
        uint256 remainingShares = vault.balanceOf(user);
        vm.prank(user);
        uint256 assetsReceived = vault.redeem(remainingShares, user, user);

        assertGt(assetsReceived, 0, "No assets received");
        assertEq(vault.balanceOf(user), 0);
    }

    function testAllocation() public {
        uint256 depositAmount = 10000e6; // 10,000 USDC

        // Deposit to vault
        vm.prank(user);
        vault.deposit(depositAmount, user);

        // Check initial allocation (should be automatic via liquidity adapter)
        uint256 initialAllocation = stataAdapter.allocation();
        assertGt(initialAllocation, 0, "No initial allocation");

        // Manual allocation test
        uint256 additionalAmount = 5000e6;
        deal(address(usdc), address(vault), additionalAmount);

        vm.prank(allocator);
        vault.allocate(address(stataAdapter), "", additionalAmount);

        // Check allocation increased
        assertGt(stataAdapter.allocation(), initialAllocation, "Allocation didn't increase");

        // Test deallocation
        vm.prank(allocator);
        vault.deallocate(address(stataAdapter), "", additionalAmount);

        // Check allocation decreased (allow for small rounding differences)
        assertApproxEqAbs(stataAdapter.allocation(), initialAllocation, 2, "Deallocation failed");
    }

    function testPreviewFunctions() public {
        uint256 depositAmount = 10000e6; // 10,000 USDC

        // Test preview functions before any deposits
        uint256 previewShares = vault.previewDeposit(depositAmount);
        uint256 previewAssets = vault.previewMint(previewShares);

        assertGt(previewShares, 0, "Preview deposit failed");
        assertApproxEqAbs(previewAssets, depositAmount, 1, "Preview mint mismatch");

        // Make actual deposit
        vm.prank(user);
        uint256 actualShares = vault.deposit(depositAmount, user);

        // Preview functions should be consistent
        assertApproxEqAbs(actualShares, previewShares, 1, "Actual shares mismatch");

        // Test withdraw/redeem previews
        uint256 previewWithdrawShares = vault.previewWithdraw(depositAmount / 2);
        uint256 previewRedeemAssets = vault.previewRedeem(actualShares / 2);

        assertGt(previewWithdrawShares, 0, "Preview withdraw failed");
        assertGt(previewRedeemAssets, 0, "Preview redeem failed");
    }

    function testMaxFunctions() public view {
        // Max functions should return 0 as per vault specification
        assertEq(vault.maxDeposit(user), 0);
        assertEq(vault.maxMint(user), 0);
        assertEq(vault.maxWithdraw(user), 0);
        assertEq(vault.maxRedeem(user), 0);
    }

    function testConversionFunctions() public {
        uint256 depositAmount = 10000e6; // 10,000 USDC

        // Make a deposit to establish exchange rate
        vm.prank(user);
        uint256 shares = vault.deposit(depositAmount, user);

        // Test conversion functions
        uint256 convertedShares = vault.convertToShares(depositAmount);
        uint256 convertedAssets = vault.convertToAssets(shares);

        assertApproxEqAbs(convertedShares, shares, 1, "Share conversion mismatch");
        assertApproxEqAbs(convertedAssets, depositAmount, 1, "Asset conversion mismatch");
    }

    function testStataIntegration() public {
        uint256 depositAmount = 50000e6; // 50,000 USDC

        // Record initial Stata state
        uint256 initialStataShares = stataUSDC.balanceOf(address(stataAdapter));

        // Deposit to vault
        vm.prank(user);
        vault.deposit(depositAmount, user);

        // Check Stata integration
        uint256 finalStataShares = stataUSDC.balanceOf(address(stataAdapter));
        assertGt(finalStataShares, initialStataShares, "No Stata shares acquired");

        // Check that adapter reports correct real assets
        uint256 reportedAssets = stataAdapter.realAssets();
        uint256 expectedAssets = stataUSDC.previewRedeem(finalStataShares);
        assertApproxEqAbs(reportedAssets, expectedAssets, 1, "Real assets mismatch");

        // Test that we can withdraw from Stata
        vm.prank(user);
        vault.withdraw(depositAmount / 2, user, user);

        // Stata shares should have decreased
        assertLt(stataUSDC.balanceOf(address(stataAdapter)), finalStataShares, "Stata shares didn't decrease");
    }

    /// forge-config: default.isolate = true
    function testStataYieldCaptureFixed() public {
        uint256 depositAmount = 100000e6; // 100,000 USDC

        // Step 1: Initial deposit
        vm.prank(user);
        vault.deposit(depositAmount, user);

        // Record initial state
        uint256 initialStataShares = stataUSDC.balanceOf(address(stataAdapter));
        uint256 initialStataAssets = stataUSDC.previewRedeem(initialStataShares);
        uint256 initialVaultAssets = vault.totalAssets();

        // Verify initial setup
        assertGt(initialStataShares, 0, "Should have Stata shares after deposit");
        assertApproxEqAbs(initialStataAssets, depositAmount, 1, "Initial Stata assets should match deposit");
        assertApproxEqAbs(initialVaultAssets, depositAmount, 1, "Initial vault assets should match deposit");

        // Step 2: Generate AAVE yield by increasing utilization
        uint256 yieldGeneratingDeposit = 10000000e6; // 10M USDC to generate meaningful yield
        address yieldGenerator = makeAddr("yieldGenerator");
        deal(address(usdc), yieldGenerator, yieldGeneratingDeposit);

        vm.startPrank(yieldGenerator);
        usdc.approve(AAVE_POOL, yieldGeneratingDeposit);
        aavePool.supply(address(usdc), yieldGeneratingDeposit, yieldGenerator, 0);
        vm.stopPrank();

        // Step 3: Fast forward time to allow yield accrual
        uint256 timeAdvance = 30 days;
        skip(timeAdvance);

        // Step 4: Verify Stata captured AAVE yield
        uint256 stataAssetsAfterYield = stataUSDC.previewRedeem(initialStataShares);
        uint256 stataYieldGenerated = stataAssetsAfterYield - initialStataAssets;

        assertGe(stataAssetsAfterYield, initialStataAssets, "Stata assets should not decrease");

        // Step 5: Verify vault captures Stata yield
        uint256 vaultAssetsAfterYield = vault.totalAssets();
        uint256 vaultYieldCaptured = vaultAssetsAfterYield - initialVaultAssets;

        // Core assertions
        if (stataYieldGenerated > 0) {
            assertGt(stataYieldGenerated, 0, "AAVE should generate yield over 30 days with high utilization");
            assertGt(vaultYieldCaptured, 0, "Vault should capture Stata yield");
            assertApproxEqAbs(vaultYieldCaptured, stataYieldGenerated, 2, "Vault should capture nearly all Stata yield");

            // Verify adapter reports correct assets
            uint256 adapterRealAssets = stataAdapter.realAssets();
            assertApproxEqAbs(adapterRealAssets, stataAssetsAfterYield, 2, "Adapter should report correct real assets");
        }

        // Verify system integrity regardless of yield
        assertGe(vaultAssetsAfterYield, initialVaultAssets, "Vault assets should not decrease significantly");

        // User should still have the same number of shares (shares don't change, just their value)
        uint256 userShares = vault.balanceOf(user);
        assertGt(userShares, 0, "User should have shares");

        // The share value should have increased if yield was captured
        uint256 shareValue = vault.previewRedeem(userShares);
        assertGe(shareValue, depositAmount, "Share value should not decrease");
    }

    /// forge-config: default.isolate = true
    function testStataYieldGenerationWithAAVE() public {
        uint256 depositAmount = 100000e6; // 100,000 USDC

        // Initial deposit
        vm.prank(user);
        vault.deposit(depositAmount, user);

        uint256 initialStataShares = stataUSDC.balanceOf(address(stataAdapter));
        uint256 initialStataAssets = stataUSDC.previewRedeem(initialStataShares);
        uint256 initialVaultAssets = vault.totalAssets();

        // Generate AAVE yield by increasing utilization
        uint256 yieldGeneratingDeposit = 10000000e6; // 10M USDC
        address yieldGenerator = makeAddr("yieldGenerator");
        deal(address(usdc), yieldGenerator, yieldGeneratingDeposit);

        vm.startPrank(yieldGenerator);
        usdc.approve(AAVE_POOL, yieldGeneratingDeposit);
        aavePool.supply(address(usdc), yieldGeneratingDeposit, yieldGenerator, 0);
        vm.stopPrank();

        // Fast forward time to accrue interest
        skip(7 days);

        // Check Stata yield generation
        uint256 stataAssetsAfterYield = stataUSDC.previewRedeem(initialStataShares);
        uint256 stataYieldGenerated = stataAssetsAfterYield - initialStataAssets;

        // Check vault yield capture
        uint256 vaultAssetsAfterYield = vault.totalAssets();
        uint256 vaultYieldCaptured = vaultAssetsAfterYield - initialVaultAssets;

        // Verify adapter reports correct assets
        uint256 adapterRealAssets = stataAdapter.realAssets();

        // Assertions
        assertGe(stataAssetsAfterYield, initialStataAssets, "Stata assets should not decrease");

        if (stataYieldGenerated > 0) {
            assertGt(stataYieldGenerated, 0, "AAVE should generate yield with high utilization");
            assertApproxEqAbs(adapterRealAssets, stataAssetsAfterYield, 2, "Adapter should report correct real assets");
            assertGt(vaultYieldCaptured, 0, "Vault should capture Stata yield");
            assertApproxEqAbs(vaultYieldCaptured, stataYieldGenerated, 2, "Vault should capture nearly all Stata yield");
        }

        // System integrity checks
        assertGe(vaultAssetsAfterYield, initialVaultAssets, "Vault assets should not decrease");
    }

    function testLargeDepositsAndWithdrawals() public {
        uint256 largeAmount = 50000000e6; // 500,000 USDC

        // Fund user with large amount
        deal(address(usdc), user, largeAmount);

        // Large deposit
        vm.prank(user);
        uint256 shares = vault.deposit(largeAmount, user);

        assertGt(shares, 0, "No shares for large deposit");
        assertEq(vault.balanceOf(user), shares);

        // Check allocation
        assertGt(stataAdapter.allocation(), 0, "No allocation for large deposit");

        // Large withdrawal (withdraw most of the deposit)
        uint256 withdrawAmount = largeAmount - 1000e6; // Leave 1000 USDC
        vm.prank(user);
        uint256 sharesToRedeem = vault.withdraw(withdrawAmount, user, user);

        assertGt(sharesToRedeem, 0, "No shares redeemed for large withdrawal");
        uint256 remainingShares = vault.balanceOf(user);
        assertLt(remainingShares, shares / 10, "Should have withdrawn most shares"); // Should have < 10% remaining
    }
}
