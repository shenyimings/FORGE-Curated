// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import { Base } from "../../Base.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";
import { IVaultNFT as IVault } from "src/interfaces/IVaultNFT.sol";
import { console2 as console } from "forge-std/console2.sol";

import { deployVault } from "src/utils/Deployers.sol";

contract VaultWithdrawTest is Base {
    function setUp() public override {
        super.setUp();

        _mintAndApprove(alice, address(vault), _parseToken(1000));
        _mintAndApprove(alice, address(escrow), _parseToken(1000));
        _mintAndApprove(bob, address(vault), _parseToken(1000));
    }

    function testRevert_1_IfPaused() public {
        (, address vault) = deployVault(address(dao), address(escrow), address(defaultStrategy), "Test Vault", "TEST");

        vm.expectRevert("Pausable: paused");
        Vault(vault).deposit(_parseToken(100), alice);
    }

    function test_withdraw() public {
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        // Alice deposits 100
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // before amounts
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 sharesBefore = vault.balanceOf(alice);

        // Alice withdraws 50
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Withdraw(alice, alice, alice, withdrawAmount, withdrawAmount);

        vm.prank(alice);
        uint256 sharesAfter = vault.withdraw(withdrawAmount, alice, alice);

        // after amounts
        assertEq(sharesAfter, _parseToken(50));
        assertEq(vault.balanceOf(alice), sharesBefore - sharesAfter);
        assertEq(vault.totalAssets(), totalAssetsBefore - withdrawAmount);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsBefore - withdrawAmount);
    }

    function test_withdrawsToReceiver() public {
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

        // alice withdraws and specifies `receiver` as recipient.
        vm.prank(alice);
        uint256 shares = vault.withdraw(withdrawAmount, receiver, alice);

        assertEq(shares, _parseToken(50));
        assertEq(lockNft.ownerOf(expectedTokenId), receiver);
        assertEq(escrow.locked(expectedTokenId).amount, withdrawAmount);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsBefore - withdrawAmount);
    }

    function test_withdrawWithAllowance() public {
        // alice deposits
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);

        // alice approves bob
        vault.approve(bob, depositAmount);
        vm.stopPrank();

        // bob withdraws on behalf of alice
        vm.prank(bob);
        uint256 shares = vault.withdraw(withdrawAmount, bob, alice);

        assertEq(shares, _parseToken(50));
        uint256 remaining = depositAmount - withdrawAmount;
        assertEq(vault.balanceOf(alice), remaining);
        assertEq(vault.allowance(alice, bob), remaining);
    }

    function testRevert_IfWithdrawMoreThanBalance() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.expectRevert();
        vm.prank(alice);
        vault.withdraw(depositAmount + 1, alice, alice);
    }

    function testRevert_IfWithdrawWithoutAllowance() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Bob tries to withdraw without approval
        vm.expectRevert();
        vm.prank(bob);
        vault.withdraw(_parseToken(50), bob, alice);
    }

    function testRevert_IfWithdrawExceedsAllowance() public {
        uint256 depositAmount = _parseToken(100);

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);
        vault.approve(bob, _parseToken(50));
        vm.stopPrank();

        // Bob tries to withdraw more than approved
        vm.expectRevert();
        vm.prank(bob);
        vault.withdraw(_parseToken(51), bob, alice);
    }

    function testRevert_IfWithdrawZeroAmount() public {
        vm.prank(alice);
        vault.deposit(_parseToken(100), alice);

        vm.expectRevert();
        vm.prank(alice);
        vault.withdraw(0, alice, alice);
    }

    function test_WithdrawAll() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 shares = vault.withdraw(depositAmount, alice, alice);

        assertEq(shares, depositAmount);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalAssets(), totalAssetsBefore - depositAmount);
    }

    function test_WithdrawCreatesNewTokenId() public {
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 lastIndex = lockNft.totalSupply() - 1;
        uint256 expectedTokenId = lockNft.tokenByIndex(lastIndex) + 2;

        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);

        // Verify new token created with correct amount
        assertEq(lockNft.ownerOf(expectedTokenId), alice);
        assertEq(escrow.locked(expectedTokenId).amount, withdrawAmount);
    }

    function test_WithdrawMultipleTimes() public {
        uint256 depositAmount = _parseToken(150);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.startPrank(alice);
        vault.withdraw(_parseToken(30), alice, alice);
        vault.withdraw(_parseToken(50), alice, alice);
        vault.withdraw(_parseToken(20), alice, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), _parseToken(50));
    }

    function test_WithdrawAfterDonation() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Bob donates
        _mintAndApprove(bob, address(vault), _parseToken(100));
        vm.prank(bob);
        vault.donate(_parseToken(100));

        uint256 sharesBefore = vault.balanceOf(alice);

        // Alice withdraws assets (should burn fewer shares due to donation)
        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(_parseToken(100), alice, alice);

        assertLt(sharesBurned, _parseToken(100));
        assertEq(vault.balanceOf(alice), sharesBefore - sharesBurned);
    }

    function test_WithdrawPreviewMatchesActual() public {
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 previewedShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        uint256 actualShares = vault.withdraw(withdrawAmount, alice, alice);

        assertEq(actualShares, previewedShares);
    }

    function test_WithdrawMaxWithdraw() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 maxWithdrawAmount = vault.maxWithdraw(alice);

        assertEq(maxWithdrawAmount, depositAmount);

        vm.prank(alice);
        vault.withdraw(maxWithdrawAmount, alice, alice);

        assertEq(vault.balanceOf(alice), 0);
    }

    function test_WithdrawSplitsMasterToken() public {
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(40);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 masterTokenAmountBefore = escrow.locked(masterTokenId).amount;

        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);

        uint256 masterTokenAmountAfter = escrow.locked(masterTokenId).amount;

        // Master token should have decreased by withdraw amount
        assertEq(masterTokenAmountAfter, masterTokenAmountBefore - withdrawAmount);
    }

    function test_WithdrawFromMultipleUsers() public {
        _mintAndApprove(bob, address(vault), _parseToken(200));

        vm.prank(alice);
        vault.deposit(_parseToken(100), alice);

        vm.prank(bob);
        vault.deposit(_parseToken(150), bob);

        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        vault.withdraw(_parseToken(50), alice, alice);

        vm.prank(bob);
        vault.withdraw(_parseToken(75), bob, bob);

        assertEq(vault.totalAssets(), totalAssetsBefore - _parseToken(125));
        assertEq(vault.balanceOf(alice), _parseToken(50));
        assertEq(vault.balanceOf(bob), _parseToken(75));
    }

    function testFuzz_Withdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, escrow.minDeposit(), type(uint128).max);
        withdrawAmount = bound(withdrawAmount, escrow.minDeposit(), depositAmount);

        _mintAndApprove(alice, address(vault), depositAmount);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 shares = vault.withdraw(withdrawAmount, alice, alice);

        assertLe(shares, depositAmount);
        assertEq(vault.totalAssets(), totalAssetsBefore - withdrawAmount);
    }

    // ================== WithdrawTokenId Tests ==================

    function test_WithdrawTokenId() public {
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 sharesBefore = vault.balanceOf(alice);

        uint256 lastIndex = lockNft.totalSupply() - 1;
        uint256 expectedTokenId = lockNft.tokenByIndex(lastIndex) + 2;

        vm.expectEmit();
        emit IVault.TokenIdWithdrawn(expectedTokenId, alice);
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Withdraw(alice, alice, alice, withdrawAmount, withdrawAmount);

        vm.prank(alice);
        uint256 tokenId = vault.withdrawTokenId(withdrawAmount, alice, alice);

        assertEq(tokenId, expectedTokenId);
        assertEq(lockNft.ownerOf(tokenId), alice);
        assertEq(escrow.locked(tokenId).amount, withdrawAmount);
        assertEq(vault.balanceOf(alice), sharesBefore - withdrawAmount);
        assertEq(vault.totalAssets(), totalAssetsBefore - withdrawAmount);
    }

    function test_WithdrawTokenIdToReceiver() public {
        address receiver = address(789);
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(60);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 lastIndex = lockNft.totalSupply() - 1;
        uint256 expectedTokenId = lockNft.tokenByIndex(lastIndex) + 2;

        vm.expectEmit(true, true, true, true);
        emit IVault.TokenIdWithdrawn(expectedTokenId, receiver);
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Withdraw(alice, receiver, alice, withdrawAmount, withdrawAmount);

        vm.prank(alice);
        uint256 tokenId = vault.withdrawTokenId(withdrawAmount, receiver, alice);

        assertEq(lockNft.ownerOf(tokenId), receiver);
        assertEq(escrow.locked(tokenId).amount, withdrawAmount);
    }

    function test_WithdrawTokenIdWithAllowance() public {
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);
        vault.approve(bob, depositAmount);
        vm.stopPrank();

        vm.prank(bob);
        uint256 tokenId = vault.withdrawTokenId(withdrawAmount, bob, alice);

        assertEq(lockNft.ownerOf(tokenId), bob);
        assertEq(vault.allowance(alice, bob), depositAmount - withdrawAmount);
    }

    function testRevert_WithdrawTokenIdMoreThanBalance() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.expectRevert();
        vm.prank(alice);
        vault.withdrawTokenId(depositAmount + 1, alice, alice);
    }

    function testRevert_WithdrawTokenIdWithoutAllowance() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.expectRevert();
        vm.prank(bob);
        vault.withdrawTokenId(_parseToken(50), bob, alice);
    }

    function test_WithdrawTokenIdAll() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.prank(alice);
        uint256 tokenId = vault.withdrawTokenId(depositAmount, alice, alice);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(escrow.locked(tokenId).amount, depositAmount);
    }

    function test_WithdrawTokenIdMultipleTimes() public {
        uint256 depositAmount = _parseToken(150);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.startPrank(alice);
        uint256 tokenId1 = vault.withdrawTokenId(_parseToken(30), alice, alice);
        uint256 tokenId2 = vault.withdrawTokenId(_parseToken(50), alice, alice);
        uint256 tokenId3 = vault.withdrawTokenId(_parseToken(20), alice, alice);
        vm.stopPrank();

        assertEq(escrow.locked(tokenId1).amount, _parseToken(30));
        assertEq(escrow.locked(tokenId2).amount, _parseToken(50));
        assertEq(escrow.locked(tokenId3).amount, _parseToken(20));
        assertEq(vault.balanceOf(alice), _parseToken(50));
    }

    function test_WithdrawTokenIdAfterDonation() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        _mintAndApprove(bob, address(vault), _parseToken(100));
        vm.prank(bob);
        vault.donate(_parseToken(100));

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 previewShares = vault.previewWithdraw(_parseToken(100));

        vm.prank(alice);
        vault.withdrawTokenId(_parseToken(100), alice, alice);

        assertLt(previewShares, _parseToken(100));
        assertEq(vault.balanceOf(alice), sharesBefore - previewShares);
    }

    function test_WithdrawTokenIdPreviewMatchesActual() public {
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 previewedShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        vault.withdrawTokenId(withdrawAmount, alice, alice);

        uint256 sharesBurned = depositAmount - vault.balanceOf(alice);
        assertEq(sharesBurned, previewedShares);
    }

    function testFuzz_WithdrawTokenId(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, escrow.minDeposit(), type(uint128).max);
        withdrawAmount = bound(withdrawAmount, escrow.minDeposit(), depositAmount);

        _mintAndApprove(alice, address(vault), depositAmount);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 tokenId = vault.withdrawTokenId(withdrawAmount, alice, alice);

        assertEq(escrow.locked(tokenId).amount, withdrawAmount);
        assertEq(lockNft.ownerOf(tokenId), alice);
        assertEq(vault.totalAssets(), totalAssetsBefore - withdrawAmount);
    }

    // ================== Recover NFT ==================
    function testRevert_RecoverNFTUnauthorized() public {
        vm.prank(alice);
        uint256 tokenId = escrow.createLockFor(_parseToken(50), address(this));

        lockNft.transferFrom(address(this), address(vault), tokenId);

        vm.expectRevert(
            abi.encodeWithSelector(DaoUnauthorized.selector, address(dao), address(vault), alice, vault.SWEEPER_ROLE())
        );
        vm.prank(alice);
        vault.recoverNFT(tokenId, alice);
    }

    function testRevert_IfRecoversAlreadyDeposittedToken() public {
        vm.startPrank(alice);
        uint256 tokenId = escrow.createLock(_parseToken(50));
        lockNft.setApprovalForAll(address(vault), true);
        vault.depositTokenId(tokenId, alice);
        vm.stopPrank();

        vm.expectRevert("ERC721: invalid token ID");
        vault.recoverNFT(tokenId, address(this));
    }

    function testRevert_IfRecoversMasterTokenId() public {
        vm.expectRevert();
        vault.recoverNFT(masterTokenId, address(this));

        // set strategy to address 0. This transfers master token id to vault
        vault.setStrategy(address(0));

        // It shouldn't allow to withdraw master token id.
        vm.expectRevert(IVault.CannotTransferMasterToken.selector);
        vault.recoverNFT(masterTokenId, address(this));
    }

    function test_RecoversMistakenlyTransferedNFT() public {
        vm.prank(alice);
        uint256 tokenId = escrow.createLockFor(_parseToken(50), address(this));

        // send nft by mistake
        lockNft.transferFrom(address(this), address(vault), tokenId);

        // recover
        vault.recoverNFT(tokenId, address(this));
        assertEq(lockNft.ownerOf(tokenId), address(this));
    }

    function test_RecoverNFTEmitsEvent() public {
        vm.prank(alice);
        uint256 tokenId = escrow.createLockFor(_parseToken(50), address(this));

        lockNft.transferFrom(address(this), address(vault), tokenId);

        vm.expectEmit(true, true, true, true);
        emit IVault.Sweep(tokenId, address(this));

        vault.recoverNFT(tokenId, address(this));
    }

    function test_RecoverNFTDoesNotAffectVaultState() public {
        vm.prank(alice);
        uint256 tokenId = escrow.createLockFor(_parseToken(50), address(this));

        lockNft.transferFrom(address(this), address(vault), tokenId);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        vault.recoverNFT(tokenId, address(this));

        // Vault state should not change
        assertEq(vault.totalAssets(), totalAssetsBefore);
        assertEq(vault.totalSupply(), totalSupplyBefore);
    }
}
