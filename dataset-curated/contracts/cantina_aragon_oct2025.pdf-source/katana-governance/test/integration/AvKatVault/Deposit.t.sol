// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import { Base } from "../../Base.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";
import { IVotingEscrowCoreErrors } from "@escrow/IVotingEscrowIncreasing_v1_2_0.sol";

import { deployVault } from "src/utils/Deployers.sol";

contract VaultDepositTest is Base {
    using ProxyLib for address;

    function setUp() public override {
        super.setUp();

        _mintAndApprove(alice, address(vault), _parseToken(1000));
        _mintAndApprove(alice, address(escrow), _parseToken(1000));
    }

    function testRevert_IfPaused() public {
        (, address vaultAddr) =
            deployVault(address(dao), address(escrow), address(defaultStrategy), "Test Vault", "TEST");

        vm.expectRevert("Pausable: paused");
        Vault(vaultAddr).deposit(_parseToken(100), alice);
    }

    function testRevert_DepositsToZeroReceiver() public {
        vm.expectRevert();
        vm.prank(alice);
        vault.deposit(_parseToken(100), address(0));
    }

    function testRevert_IfZeroAmount() public {
        vm.expectRevert(IVotingEscrowCoreErrors.ZeroAmount.selector);
        vault.deposit(0, alice);
    }

    function testRevert_IfInsufficientAllowance() public {
        vm.startPrank(alice);
        escrowToken.approve(address(vault), _parseToken(50) - 1);

        vm.expectRevert();
        vault.deposit(_parseToken(50), alice);
        vm.stopPrank();
    }

    function test_Deposit() public {
        uint256 depositAmount = _parseToken(100);

        uint256 assetBefore = escrowToken.balanceOf(alice);
        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 totalAssetsBefore = vault.totalAssets();

        vm.expectEmit();
        emit IERC4626.Deposit(alice, alice, depositAmount, depositAmount);

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        uint256 totalAssetsAfter = totalAssetsBefore + depositAmount;

        assertEq(vault.balanceOf(alice), sharesBefore + shares);
        assertEq(vault.totalAssets(), totalAssetsAfter);
        assertEq(escrowToken.balanceOf(alice), assetBefore - depositAmount);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsAfter);

        assertEq(shares, depositAmount);
    }

    function test_DepositsToReceiver() public {
        address receiver = vm.createWallet("receiver").addr;

        uint256 depositAmount = _parseToken(100);

        vm.expectEmit();
        emit IERC4626.Deposit(alice, receiver, depositAmount, depositAmount);

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, receiver);

        assertEq(vault.balanceOf(receiver), shares);
    }

    function test_DepositMultipleTimes() public {
        uint256 depositAmount1 = _parseToken(50);
        uint256 depositAmount2 = _parseToken(75);

        vm.startPrank(alice);
        uint256 shares1 = vault.deposit(depositAmount1, alice);
        uint256 shares2 = vault.deposit(depositAmount2, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), shares1 + shares2);
        // After first deposit, ratio should be approximately 1:1 for subsequent deposits
        assertApproxEqRel(shares1, depositAmount1, 0.01e18); // 1% tolerance
        assertApproxEqRel(shares2, depositAmount2, 0.01e18);
    }

    function test_DepositFromMultipleUsers() public {
        _mintAndApprove(bob, address(vault), _parseToken(200));

        uint256 aliceAmount = _parseToken(100);
        uint256 bobAmount = _parseToken(150);

        vm.prank(alice);
        uint256 aliceShares = vault.deposit(aliceAmount, alice);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(bobAmount, bob);

        assertEq(vault.balanceOf(alice), aliceShares);
        assertEq(vault.balanceOf(bob), bobShares);
        // Total assets includes minDeposit initial amount, so it's slightly more than total supply
        assertApproxEqRel(vault.totalAssets(), vault.totalSupply(), 0.01e18);
    }

    function test_DepositAfterDonation() public {
        _mintAndApprove(bob, address(vault), _parseToken(100));

        // Bob donates first to increase share value
        uint256 donateAmount = _parseToken(100);
        vm.expectEmit(true, true, true, true);
        emit Vault.AssetsDonated(donateAmount);
        vm.prank(bob);
        vault.donate(donateAmount);

        uint256 depositAmount = _parseToken(100);
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        // Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Shares should be less than deposit amount due to increased share value
        assertLt(shares, depositAmount);
        assertEq(vault.totalAssets(), totalAssetsBefore + depositAmount);
        assertEq(vault.totalSupply(), totalSupplyBefore + shares);
    }

    function test_DepositCreatesAndMergesTokenIntoMasterToken() public {
        uint256 depositAmount = _parseToken(100);
        uint256 masterTokenAmountBefore = escrow.locked(masterTokenId).amount;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 masterTokenAmountAfter = escrow.locked(masterTokenId).amount;

        // Master token should have increased by deposit amount
        assertEq(masterTokenAmountAfter, masterTokenAmountBefore + depositAmount);
    }

    function test_DepositDoesNotLeaveTokensInVault() public {
        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Vault should not hold any raw tokens (all locked in escrow)
        assertEq(escrowToken.balanceOf(address(vault)), 0);
    }

    function test_DepositPreviewMatchesActual() public {
        uint256 depositAmount = _parseToken(100);

        uint256 previewedShares = vault.previewDeposit(depositAmount);

        vm.prank(alice);
        uint256 actualShares = vault.deposit(depositAmount, alice);

        assertEq(actualShares, previewedShares);
    }

    function test_DepositMaxDeposit() public {
        uint256 maxDepositAmount = vault.maxDeposit(alice);

        // Should be able to deposit up to max
        assertGt(maxDepositAmount, 0);

        uint256 depositAmount = _parseToken(100);
        assertLe(depositAmount, maxDepositAmount);

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        assertGt(shares, 0);
    }

    function test_DepositSharesRoundDown() public {
        _mintAndApprove(bob, address(vault), _parseToken(100));

        // Create a scenario where shares might round down
        vm.prank(bob);
        vault.donate(_parseToken(1)); // Small donation to shift the ratio

        uint256 depositAmount = _parseToken(100);

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Shares should be less than or equal to deposit
        assertLe(shares, depositAmount);
    }

    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, escrow.minDeposit(), type(uint128).max);

        _mintAndApprove(alice, address(vault), amount);

        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), totalAssetsBefore + amount);
    }
}
