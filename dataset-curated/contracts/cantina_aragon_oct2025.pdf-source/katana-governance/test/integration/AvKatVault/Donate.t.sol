// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import { Base } from "../../Base.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";
import { IVotingEscrowCoreErrors } from "@escrow/IVotingEscrowIncreasing_v1_2_0.sol";

contract VaultDonateTest is Base {
    using ProxyLib for address;

    event Donation(address indexed donor, uint256 amount);

    function setUp() public override {
        super.setUp();

        _mintAndApprove(alice, address(vault), _parseToken(1000));
        _mintAndApprove(bob, address(vault), _parseToken(1000));
    }

    function testRevert_IfPaused() public {
        address base = address(new Vault());

        Vault newVault = Vault(
            base.deployUUPSProxy(
                abi.encodeCall(
                    Vault.initialize, (address(dao), address(escrow), address(defaultStrategy), "Test Vault", "TEST")
                )
            )
        );

        vm.startPrank(alice);
        escrowToken.approve(address(newVault), _parseToken(100));

        vm.expectRevert("Pausable: paused");
        newVault.donate(_parseToken(100));
        vm.stopPrank();
    }

    function testRevert_IfZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IVotingEscrowCoreErrors.ZeroAmount.selector);
        vault.donate(0);
    }

    function testRevert_IfInsufficientAllowance() public {
        vm.startPrank(alice);
        escrowToken.approve(address(vault), _parseToken(50) - 1);

        vm.expectRevert();
        vault.donate(_parseToken(50));
        vm.stopPrank();
    }

    function test_DonateIncreasesTotalAssetsWithoutMintingShares() public {
        uint256 donateAmount = _parseToken(100);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        vm.prank(alice);
        vault.donate(donateAmount);

        // Total assets should increase
        assertEq(vault.totalAssets(), totalAssetsBefore + donateAmount, "Total assets should increase");

        // Total supply should remain the same (no shares minted)
        assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should not change");

        // Alice's shares should remain the same
        assertEq(vault.balanceOf(alice), aliceSharesBefore, "Alice's shares should not change");
    }

    function test_DonateIncreasesShareValue() public {
        // First, alice deposits to get shares
        uint256 depositAmount = _parseToken(100);
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(depositAmount, alice);

        uint256 shareValueBefore = vault.convertToAssets(1e18);

        // Bob donates
        uint256 donateAmount = _parseToken(50);
        vm.prank(bob);
        vault.donate(donateAmount);

        uint256 shareValueAfter = vault.convertToAssets(1e18);

        // Share value should increase
        assertGt(shareValueAfter, shareValueBefore, "Share value should increase after donation");

        // Alice's shares are now worth more
        uint256 aliceAssetsAfter = vault.convertToAssets(aliceShares);
        assertGt(aliceAssetsAfter, depositAmount, "Alice's shares should be worth more than initial deposit");
    }

    function test_DonateWithMultipleShareholdersBenefitsAll() public {
        // Alice and Bob deposit equal amounts
        vm.prank(alice);
        vault.deposit(_parseToken(100), alice);

        vm.prank(bob);
        vault.deposit(_parseToken(100), bob);

        uint256 aliceSharesBefore = vault.balanceOf(alice);
        uint256 bobSharesBefore = vault.balanceOf(bob);

        uint256 aliceValueBefore = vault.convertToAssets(aliceSharesBefore);
        uint256 bobValueBefore = vault.convertToAssets(bobSharesBefore);

        // Charlie donates
        address charlie = vm.createWallet("charlie").addr;
        _mintAndApprove(charlie, address(vault), _parseToken(100));

        vm.prank(charlie);
        vault.donate(_parseToken(100));

        // Both alice and bob benefit proportionally
        uint256 aliceValueAfter = vault.convertToAssets(aliceSharesBefore);
        uint256 bobValueAfter = vault.convertToAssets(bobSharesBefore);

        assertGt(aliceValueAfter, aliceValueBefore, "Alice's share value should increase");
        assertGt(bobValueAfter, bobValueBefore, "Bob's share value should increase");

        // They should benefit equally (since they had equal shares)
        assertEq(aliceValueAfter - aliceValueBefore, bobValueAfter - bobValueBefore, "Benefit should be proportional");
    }

    function test_DonateTransfersTokensFromDonor() public {
        uint256 donateAmount = _parseToken(100);
        uint256 aliceBalanceBefore = escrowToken.balanceOf(alice);

        vm.prank(alice);
        vault.donate(donateAmount);

        assertEq(
            escrowToken.balanceOf(alice), aliceBalanceBefore - donateAmount, "Tokens should be transferred from donor"
        );
    }

    function test_DonateMergesIntoMasterToken() public {
        uint256 donateAmount = _parseToken(100);
        uint256 masterTokenAmountBefore = escrow.locked(masterTokenId).amount;

        vm.prank(alice);
        vault.donate(donateAmount);

        uint256 masterTokenAmountAfter = escrow.locked(masterTokenId).amount;

        assertEq(
            masterTokenAmountAfter,
            masterTokenAmountBefore + donateAmount,
            "Master token amount should increase by donation amount"
        );
    }

    function test_DonateDoesNotAffectVaultTokenBalance() public {
        uint256 donateAmount = _parseToken(100);

        vm.prank(alice);
        vault.donate(donateAmount);

        // Vault should not hold any raw tokens (all in escrow)
        assertEq(escrowToken.balanceOf(address(vault)), 0, "Vault should not hold tokens after donation");
    }

    function test_MultipleDonationsCompound() public {
        // Alice deposits to get shares
        vm.prank(alice);
        vault.deposit(_parseToken(100), alice);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        // Bob donates twice
        vm.startPrank(bob);
        vault.donate(_parseToken(50));
        vault.donate(_parseToken(30));
        vm.stopPrank();

        assertEq(vault.totalAssets(), totalAssetsBefore + _parseToken(80), "Total assets should increase by sum");
        assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");
    }

    function testFuzz_DonateAlwaysIncreasesShareValue(uint256 depositAmount, uint256 donateAmount) public {
        depositAmount = bound(depositAmount, escrow.minDeposit(), type(uint128).max);
        donateAmount = bound(donateAmount, escrow.minDeposit(), type(uint128).max);
        _mintAndApprove(alice, address(vault), depositAmount);
        _mintAndApprove(bob, address(vault), donateAmount);

        // Alice deposits
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        // Bob donates
        vm.prank(bob);
        vault.donate(donateAmount);

        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 totalSupplyAfter = vault.totalSupply();

        // Total assets should increase by donation amount
        assertEq(totalAssetsAfter, totalAssetsBefore + donateAmount, "Total assets should increase by donation");

        // Total supply should remain unchanged
        assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply should remain unchanged");

        // Since totalAssets increased and totalSupply stayed the same, share value must increase
        // (though it may not be observable due to rounding when checking convertToAssets(1e18))
    }
}
