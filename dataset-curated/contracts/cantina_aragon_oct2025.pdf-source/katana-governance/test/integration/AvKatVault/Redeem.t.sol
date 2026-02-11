// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { Base } from "../../Base.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";
import { IVaultNFT as IVault } from "src/interfaces/IVaultNFT.sol";

import { deployVault } from "src/utils/Deployers.sol";

contract VaultRedeemTest is Base {
    function setUp() public override {
        super.setUp();

        _mintAndApprove(alice, address(vault), _parseToken(1000));
        _mintAndApprove(alice, address(escrow), _parseToken(1000));
        _mintAndApprove(bob, address(vault), _parseToken(1000));
    }

    function testRevert_IfPaused() public {
        (, address vault) = deployVault(address(dao), address(escrow), address(defaultStrategy), "Test Vault", "TEST");

        vm.expectRevert("Pausable: paused");
        Vault(vault).deposit(_parseToken(100), alice);
    }

    function test_redeem() public {
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        // Alice deposits 100
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // before amounts
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 sharesBefore = vault.balanceOf(alice);

        // Alice redeems 50
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Withdraw(alice, alice, alice, withdrawAmount, withdrawAmount);

        vm.prank(alice);
        uint256 assets = vault.redeem(withdrawAmount, alice, alice);

        // after amounts
        assertEq(assets, _parseToken(50));
        assertEq(vault.balanceOf(alice), sharesBefore - assets);
        assertEq(vault.totalAssets(), totalAssetsBefore - withdrawAmount);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsBefore - withdrawAmount);
    }

    function test_redeemsToReceiver() public {
        address receiver = address(456);

        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        // alice deposits 100
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();

        // `deposit` burns (reduces supply due to merge),
        // so withdraw mints the next id after the burned one → +2
        uint256 lastIndex = lockNft.totalSupply() - 1;
        uint256 expectedTokenId = lockNft.tokenByIndex(lastIndex) + 2;

        vm.expectEmit();
        emit IVault.TokenIdWithdrawn(expectedTokenId, receiver);

        // alice redeems and specifies `receiver` as recipient.
        vm.prank(alice);
        uint256 assets = vault.redeem(withdrawAmount, receiver, alice);

        assertEq(assets, _parseToken(50));
        assertEq(lockNft.ownerOf(expectedTokenId), receiver);
        assertEq(escrow.locked(expectedTokenId).amount, withdrawAmount);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsBefore - withdrawAmount);
    }

    function test_redeemsWithAllowance() public {
        // alice deposits
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);

        // alice approves bob
        vault.approve(bob, depositAmount);
        vm.stopPrank();

        // bob redeems on behalf of alice
        vm.prank(bob);
        uint256 assets = vault.redeem(withdrawAmount, bob, alice);

        assertEq(assets, _parseToken(50));
        uint256 remaining = depositAmount - withdrawAmount;
        assertEq(vault.balanceOf(alice), remaining);
        assertEq(vault.allowance(alice, bob), remaining);
    }

    function testRevert_IfRedeemMoreThanBalance() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.expectRevert();
        vm.prank(alice);
        vault.redeem(depositAmount + 1, alice, alice);
    }

    function testRevert_IfRedeemWithoutAllowance() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Bob tries to redeem without approval
        vm.expectRevert();
        vm.prank(bob);
        vault.redeem(_parseToken(50), bob, alice);
    }

    function testRevert_IfRedeemExceedsAllowance() public {
        uint256 depositAmount = _parseToken(100);

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);
        vault.approve(bob, _parseToken(50));
        vm.stopPrank();

        // Bob tries to redeem more than approved
        vm.expectRevert();
        vm.prank(bob);
        vault.redeem(_parseToken(51), bob, alice);
    }

    function testRevert_IfRedeemZeroShares() public {
        vm.prank(alice);
        vault.deposit(_parseToken(100), alice);

        vm.expectRevert();
        vm.prank(alice);
        vault.redeem(0, alice, alice);
    }

    function test_RedeemAll() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);

        assertEq(assets, depositAmount);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalAssets(), totalAssetsBefore - assets);
    }

    function test_RedeemCreatesNewTokenId() public {
        uint256 depositAmount = _parseToken(100);
        uint256 redeemShares = _parseToken(50);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 lastIndex = lockNft.totalSupply() - 1;
        uint256 expectedTokenId = lockNft.tokenByIndex(lastIndex) + 2;

        vm.prank(alice);
        uint256 assets = vault.redeem(redeemShares, alice, alice);

        // Verify new token created with correct amount
        assertEq(lockNft.ownerOf(expectedTokenId), alice);
        assertEq(escrow.locked(expectedTokenId).amount, assets);
    }

    function test_RedeemMultipleTimes() public {
        uint256 depositAmount = _parseToken(150);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.startPrank(alice);
        vault.redeem(_parseToken(30), alice, alice);
        vault.redeem(_parseToken(50), alice, alice);
        vault.redeem(_parseToken(20), alice, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), _parseToken(50));
    }

    function test_RedeemAfterDonation() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 sharesBefore = vault.balanceOf(alice);

        // Bob donates to increase share value
        _mintAndApprove(bob, address(vault), _parseToken(100));
        vm.prank(bob);
        vault.donate(_parseToken(100));

        // Alice redeems shares (should get more assets due to donation)
        vm.prank(alice);
        uint256 assets = vault.redeem(_parseToken(50), alice, alice);

        assertGt(assets, _parseToken(50)); // Gets more assets than shares redeemed
        assertEq(vault.balanceOf(alice), sharesBefore - _parseToken(50));
    }

    function test_RedeemPreviewMatchesActual() public {
        uint256 depositAmount = _parseToken(100);
        uint256 redeemShares = _parseToken(50);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 previewedAssets = vault.previewRedeem(redeemShares);

        vm.prank(alice);
        uint256 actualAssets = vault.redeem(redeemShares, alice, alice);

        assertEq(actualAssets, previewedAssets);
    }

    function test_RedeemMaxRedeem() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 maxRedeemShares = vault.maxRedeem(alice);

        assertEq(maxRedeemShares, depositAmount);

        vm.prank(alice);
        vault.redeem(maxRedeemShares, alice, alice);

        assertEq(vault.balanceOf(alice), 0);
    }

    function test_RedeemSplitsMasterToken() public {
        uint256 depositAmount = _parseToken(100);
        uint256 redeemShares = _parseToken(40);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 masterTokenAmountBefore = escrow.locked(masterTokenId).amount;

        vm.prank(alice);
        uint256 assets = vault.redeem(redeemShares, alice, alice);

        uint256 masterTokenAmountAfter = escrow.locked(masterTokenId).amount;

        // Master token should have decreased by redeemed assets
        assertEq(masterTokenAmountAfter, masterTokenAmountBefore - assets);
    }

    function test_RedeemFromMultipleUsers() public {
        _mintAndApprove(bob, address(vault), _parseToken(200));

        vm.prank(alice);
        vault.deposit(_parseToken(100), alice);

        vm.prank(bob);
        vault.deposit(_parseToken(150), bob);

        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 aliceAssets = vault.redeem(_parseToken(50), alice, alice);

        vm.prank(bob);
        uint256 bobAssets = vault.redeem(_parseToken(75), bob, bob);

        assertEq(vault.totalAssets(), totalAssetsBefore - aliceAssets - bobAssets);
        assertEq(vault.balanceOf(alice), _parseToken(50));
        assertEq(vault.balanceOf(bob), _parseToken(75));
    }

    function test_RedeemWithInfiniteAllowance() public {
        uint256 depositAmount = _parseToken(100);

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);
        vault.approve(bob, type(uint256).max);
        vm.stopPrank();

        vm.prank(bob);
        vault.redeem(_parseToken(50), bob, alice);

        // Infinite allowance should remain infinite
        assertEq(vault.allowance(alice, bob), type(uint256).max);
    }

    function test_RedeemReturnsCorrectAssets() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(_parseToken(50), alice, alice);

        // In 1:1 ratio scenario, assets should equal shares
        assertEq(assets, _parseToken(50));
    }

    function test_RedeemPartialShares() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Redeem 25% of shares
        uint256 sharesToRedeem = depositAmount / 4;

        vm.prank(alice);
        uint256 assets = vault.redeem(sharesToRedeem, alice, alice);

        assertEq(vault.balanceOf(alice), depositAmount - sharesToRedeem);
        assertEq(assets, sharesToRedeem); // 1:1 in base case
    }

    function test_RedeemConvertsToAssetsCorrectly() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 sharesToRedeem = _parseToken(60);
        uint256 expectedAssets = vault.convertToAssets(sharesToRedeem);

        vm.prank(alice);
        uint256 actualAssets = vault.redeem(sharesToRedeem, alice, alice);

        assertEq(actualAssets, expectedAssets);
    }

    function testFuzz_Redeem(uint256 depositAmount, uint256 redeemShares) public {
        depositAmount = bound(depositAmount, escrow.minDeposit(), type(uint128).max);
        redeemShares = bound(redeemShares, escrow.minDeposit(), depositAmount);

        _mintAndApprove(alice, address(vault), depositAmount);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 assets = vault.redeem(redeemShares, alice, alice);

        assertGe(assets, 0);
        assertEq(vault.balanceOf(alice), depositAmount - redeemShares);
        assertLe(vault.totalAssets(), totalAssetsBefore);
    }
}
