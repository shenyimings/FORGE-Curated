// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {StakedFatBERAV3} from "../src/StakedFatBERAV3.sol";
import {fatBERA} from "../src/fatBERA.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract StakedFatBERAV3Test is Test {
    StakedFatBERAV3 public vault;
    fatBERA public fatberaVault;
    MockERC20 public wbera;
    MockERC20 public rewardToken;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant EXIT_FEE_BPS = 50; // 0.5%
    uint256 constant INITIAL_DEPOSIT = 1000e18;
    uint256 constant INITIAL_MINT = 10000e18;

    function setUp() public {
        // Deploy mock WBERA at the expected address using vm.etch
        wbera = new MockERC20("Wrapped BERA", "WBERA", 18);
        vm.etch(0x6969696969696969696969696969696969696969, address(wbera).code);
        wbera = MockERC20(0x6969696969696969696969696969696969696969);

        // Deploy fatBERA vault
        bytes memory fatBeraInitData = abi.encodeWithSelector(
            fatBERA.initialize.selector,
            address(wbera),
            owner,
            100000000e18 // max deposits
        );
        address fatBeraProxy = Upgrades.deployUUPSProxy("fatBERA.sol:fatBERA", fatBeraInitData);
        fatberaVault = fatBERA(payable(fatBeraProxy));

        // Deploy StakedFatBERAV3
        bytes memory initData =
            abi.encodeWithSelector(StakedFatBERAV3.initialize.selector, owner, address(fatberaVault));
        address proxy = Upgrades.deployUUPSProxy("StakedFatBERAV3.sol:StakedFatBERAV3", initData);
        vault = StakedFatBERAV3(address(proxy));

        // Setup roles and fees
        vm.startPrank(owner);
        vault.setExitFee(EXIT_FEE_BPS);
        vault.setTreasury(treasury);
        // Set reward duration for fatBERA vault
        fatberaVault.setRewardsDuration(address(wbera), 7 days);
        vm.stopPrank();

        // Give Alice and Bob some WBERA
        wbera.mint(alice, INITIAL_MINT);
        wbera.mint(bob, INITIAL_MINT);

        // Alice and Bob deposit WBERA into fatBERA vault to get fatBERA
        vm.prank(alice);
        wbera.approve(address(fatberaVault), type(uint256).max);
        vm.prank(alice);
        fatberaVault.deposit(INITIAL_MINT, alice);

        vm.prank(bob);
        wbera.approve(address(fatberaVault), type(uint256).max);
        vm.prank(bob);
        fatberaVault.deposit(INITIAL_MINT, bob);

        // Approve StakedFatBERAV3 vault
        vm.prank(alice);
        fatberaVault.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        fatberaVault.approve(address(vault), type(uint256).max);
    }

    /*────────────────────────────────────────────────────────────────────────────
        BASIC FUNCTIONALITY TESTS
    ────────────────────────────────────────────────────────────────────────────*/

    function testDepositAndRedeem() public {
        // Alice deposits
        vm.startPrank(alice);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, alice);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(fatberaVault.balanceOf(alice), INITIAL_MINT - INITIAL_DEPOSIT);

        // Alice redeems
        uint256 assets = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        // Check fee was applied (rounded up)
        uint256 expectedFee = (shares * EXIT_FEE_BPS + 9999) / 10000;
        uint256 expectedAssets = vault.convertToAssets(shares - expectedFee);
        assertApproxEqAbs(assets, expectedAssets, 1); // Allow 1 wei rounding

        // Check treasury got fee shares
        assertEq(vault.balanceOf(treasury), expectedFee);
    }

    function testDepositAndWithdraw() public {
        // Alice deposits
        vm.startPrank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);

        // Alice withdraws specific amount
        uint256 assetsToWithdraw = 500e18;
        uint256 sharesBurned = vault.withdraw(assetsToWithdraw, alice, alice);
        vm.stopPrank();

        // Verify alice received exact amount requested
        assertEq(fatberaVault.balanceOf(alice), INITIAL_MINT - INITIAL_DEPOSIT + assetsToWithdraw);

        // Check treasury got fee shares
        assertTrue(vault.balanceOf(treasury) > 0);
    }

    /*────────────────────────────────────────────────────────────────────────────
        PREVIEW FUNCTION ACCURACY TESTS
    ────────────────────────────────────────────────────────────────────────────*/

    function testPreviewRedeemAccuracy() public {
        // Setup: Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, alice);

        // Preview redeem
        uint256 previewedAssets = vault.previewRedeem(shares);

        // Actual redeem
        vm.prank(alice);
        uint256 actualAssets = vault.redeem(shares, alice, alice);

        // Preview should match actual
        assertEq(previewedAssets, actualAssets, "previewRedeem should match actual redeem");
    }

    function testPreviewWithdrawAccuracy() public {
        // Setup: Alice deposits
        vm.prank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);

        uint256 assetsToWithdraw = 500e18;

        // Preview withdraw
        uint256 previewedShares = vault.previewWithdraw(assetsToWithdraw);

        // Actual withdraw
        vm.prank(alice);
        uint256 actualShares = vault.withdraw(assetsToWithdraw, alice, alice);

        // Preview should match actual
        assertEq(previewedShares, actualShares, "previewWithdraw should match actual withdraw");
    }

    /*────────────────────────────────────────────────────────────────────────────
        DOUBLE FEE BUG TESTS
    ────────────────────────────────────────────────────────────────────────────*/

    function testNoDoubleFeeOnRedeem() public {
        // Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, alice);

        // Calculate expected assets with single fee application
        uint256 feeInShares = (shares * EXIT_FEE_BPS + 9999) / 10000; // Round up
        uint256 sharesAfterFee = shares - feeInShares;
        uint256 expectedAssets = vault.convertToAssets(sharesAfterFee);

        // Redeem
        vm.prank(alice);
        uint256 actualAssets = vault.redeem(shares, alice, alice);

        // Should only have one fee application
        assertApproxEqAbs(actualAssets, expectedAssets, 1, "Should only apply fee once");

        // Verify it's not applying fee twice (old bug would give less)
        uint256 doubleFeeBugAmount = vault.convertToAssets(shares);
        doubleFeeBugAmount = doubleFeeBugAmount - (doubleFeeBugAmount * EXIT_FEE_BPS) / 10000; // First fee
        doubleFeeBugAmount = doubleFeeBugAmount - (doubleFeeBugAmount * EXIT_FEE_BPS) / 10000; // Second fee (bug)

        assertTrue(actualAssets > doubleFeeBugAmount, "Should receive more than double fee bug amount");
    }

    function testNoDoubleFeeOnWithdraw() public {
        // Alice deposits
        vm.prank(alice);
        uint256 depositedShares = vault.deposit(INITIAL_DEPOSIT, alice);

        uint256 assetsToWithdraw = 500e18;

        // Calculate shares needed
        uint256 baseShares = vault.previewWithdraw(assetsToWithdraw);

        // Withdraw
        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(assetsToWithdraw, alice, alice);

        // Alice should receive exactly what she requested
        assertEq(fatberaVault.balanceOf(alice), INITIAL_MINT - INITIAL_DEPOSIT + assetsToWithdraw);

        // Shares burned should match preview
        assertEq(sharesBurned, baseShares, "Shares burned should match preview");
    }

    /*────────────────────────────────────────────────────────────────────────────
        FEE CALCULATION TESTS
    ────────────────────────────────────────────────────────────────────────────*/

    function testFeeCalculation() public {
        // Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, alice);

        // Redeem all shares
        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        // Check treasury received correct fee (using mulDivUp for consistency)
        uint256 expectedFeeShares = (shares * EXIT_FEE_BPS + 9999) / 10000; // Rounded up
        assertEq(vault.balanceOf(treasury), expectedFeeShares, "Treasury should receive correct fee shares");
    }

    function testTreasuryNoFee() public {
        // Treasury needs some fatBERA - mint WBERA and deposit to fatBERA vault
        wbera.mint(treasury, INITIAL_DEPOSIT);
        vm.startPrank(treasury);
        wbera.approve(address(fatberaVault), type(uint256).max);
        fatberaVault.deposit(INITIAL_DEPOSIT, treasury);
        fatberaVault.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, treasury);

        // Treasury redeems - should pay no fee
        uint256 assets = vault.redeem(shares, treasury, treasury);
        vm.stopPrank();

        // Treasury should get back full value (no fee)
        assertEq(assets, vault.convertToAssets(shares), "Treasury should pay no fee");
        assertEq(vault.balanceOf(treasury), 0, "Treasury should not receive fee shares from itself");
    }

    /*────────────────────────────────────────────────────────────────────────────
        EDGE CASES AND ROUNDING
    ────────────────────────────────────────────────────────────────────────────*/

    function testSmallRedemption() public {
        // Alice deposits
        vm.prank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);

        // Redeem very small amount
        uint256 smallShares = 100; // Very small
        vm.prank(alice);
        uint256 assets = vault.redeem(smallShares, alice, alice);

        // Should still work correctly
        assertTrue(assets > 0, "Should receive some assets");
        assertTrue(vault.balanceOf(treasury) > 0, "Treasury should receive fee");
    }

    function testZeroFee() public {
        // Set fee to 0
        vm.prank(owner);
        vault.setExitFee(0);

        // Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, alice);

        // Preview should show full value
        uint256 previewedAssets = vault.previewRedeem(shares);
        assertEq(previewedAssets, vault.convertToAssets(shares), "With zero fee, preview should equal convertToAssets");

        // Redeem should give full value
        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);
        assertEq(assets, vault.convertToAssets(shares), "With zero fee, should receive full value");

        // Treasury should receive no fee
        assertEq(vault.balanceOf(treasury), 0, "Treasury should receive no fee when fee is 0");
    }

    /*────────────────────────────────────────────────────────────────────────────
        COMPOUND YIELD TEST
    ────────────────────────────────────────────────────────────────────────────*/

    function testTreasurySharesCompound() public {
        // Alice deposits and redeems, generating fee shares for treasury
        vm.startPrank(alice);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, alice);
        vault.redeem(shares, alice, alice);
        vm.stopPrank();

        uint256 treasuryShares = vault.balanceOf(treasury);
        assertTrue(treasuryShares > 0, "Treasury should have fee shares");

        // Simulate vault appreciation by minting fatBERA directly to vault
        // First mint WBERA to vault address, then have vault deposit it
        wbera.mint(address(fatberaVault), INITIAL_DEPOSIT);

        // Treasury's shares should now be worth more
        uint256 treasuryAssets = vault.convertToAssets(treasuryShares);
        assertTrue(treasuryAssets > 0, "Treasury shares should have value");

        // Treasury can redeem without fee
        vm.prank(treasury);
        uint256 redeemedAssets = vault.redeem(treasuryShares, treasury, treasury);
        assertEq(redeemedAssets, treasuryAssets, "Treasury should redeem full value");
    }

    /*────────────────────────────────────────────────────────────────────────────
        MULTIPLE USER INTERACTION
    ────────────────────────────────────────────────────────────────────────────*/

    function testMultipleUsersWithFees() public {
        // Alice deposits
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(INITIAL_DEPOSIT, alice);

        // Bob deposits
        vm.prank(bob);
        uint256 bobShares = vault.deposit(INITIAL_DEPOSIT * 2, bob);

        // Alice withdraws half
        vm.prank(alice);
        vault.withdraw(INITIAL_DEPOSIT / 2, alice, alice);

        // Bob redeems all
        vm.prank(bob);
        vault.redeem(bobShares, bob, bob);

        // Treasury should have accumulated fees from both
        assertTrue(vault.balanceOf(treasury) > 0, "Treasury should have fees from multiple users");

        // Vault should still be functional
        assertTrue(vault.totalAssets() > 0, "Vault should still have assets");
        assertTrue(vault.totalSupply() > 0, "Vault should still have shares");
    }

    /*────────────────────────────────────────────────────────────────────────────
        MATHEMATICAL CONSISTENCY TESTS
    ────────────────────────────────────────────────────────────────────────────*/

    function testMathematicalConsistency() public {
        // Deposit initial amount
        vm.prank(alice);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, alice);

        // Test that preview functions are consistent
        uint256 assets = 500e18;
        uint256 sharesToBurn = vault.previewWithdraw(assets);
        uint256 assetsFromRedeem = vault.previewRedeem(sharesToBurn);

        // Due to rounding and fees, assetsFromRedeem should be approximately assets
        // but slightly less due to fee application
        assertTrue(assetsFromRedeem <= assets, "Assets from redeem should account for fees");

        // The difference should be roughly the fee amount
        uint256 difference = assets - assetsFromRedeem;
        uint256 expectedMaxDifference = (assets * EXIT_FEE_BPS) / 10000 + 10; // Add small buffer for rounding
        assertTrue(difference <= expectedMaxDifference, "Difference should be approximately the fee");
    }

    /*────────────────────────────────────────────────────────────────────────────
        FEE VALIDATION
    ────────────────────────────────────────────────────────────────────────────*/

    function testInvalidFee() public {
        // Try to set fee >= 100%
        vm.prank(owner);
        vm.expectRevert("invalid fee");
        vault.setExitFee(10000);

        vm.prank(owner);
        vm.expectRevert("invalid fee");
        vault.setExitFee(10001);
    }

    function testMaxFee() public {
        // Set max valid fee (99.99%)
        vm.prank(owner);
        vault.setExitFee(9999);

        // Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, alice);

        // Redeem should still work but give minimal assets
        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);

        // With 99.99% fee, should receive very little
        assertTrue(assets < INITIAL_DEPOSIT / 100, "Should receive less than 1% with 99.99% fee");

        // Treasury should get almost all shares
        assertApproxEqRel(vault.balanceOf(treasury), shares, 0.01e18, "Treasury should get ~99.99% of shares");
    }

  /*────────────────────────────────────────────────────────────────────────────
      EXPLOIT DEMONSTRATION (PRE-FIX BEHAVIOR)
    ────────────────────────────────────────────────────────────────────────────*/

  function testTreasuryWithdrawBurnsSharesAfterFix() public {
      // Treasury obtains xfatBERA shares
      wbera.mint(treasury, INITIAL_DEPOSIT);
      vm.startPrank(treasury);
      wbera.approve(address(fatberaVault), type(uint256).max);
      fatberaVault.deposit(INITIAL_DEPOSIT, treasury);
      fatberaVault.approve(address(vault), type(uint256).max);
      uint256 mintedShares = vault.deposit(INITIAL_DEPOSIT, treasury);
      vm.stopPrank();

      // Manipulate exchange rate so that totalAssets > totalSupply by transferring
      // a dust amount of fatBERA directly to the vault (no shares minted)
      vm.prank(alice);
      fatberaVault.transfer(address(vault), 1);

      // Sanity: ratio totalSupply/totalAssets < 1 ensures floor conversion can be zero
      assertLt(vault.totalSupply(), vault.totalAssets(), "test setup failed: ratio not < 1");

      // After fix: treasury withdraws 1 wei of assets and must burn at least 1 share due to ceil rounding
      vm.startPrank(treasury);
      uint256 sharesBurned = vault.withdraw(1, treasury, treasury);
      vm.stopPrank();

      assertGt(sharesBurned, 0, "Must burn non-zero shares for non-zero asset withdrawal");
      assertEq(fatberaVault.balanceOf(treasury), 1, "Treasury should receive the withdrawn asset");
      assertEq(vault.totalSupply(), mintedShares - sharesBurned, "Total supply should decrease by burned shares");
  }
}
