// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import { Base } from "../../Base.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";
import { IStrategy } from "src/interfaces/IStrategy.sol";
import { IStrategyNFT } from "src/interfaces/IStrategyNFT.sol";
import { deployAutoCompoundStrategy } from "src/utils/Deployers.sol";

contract VaultSetStrategyTest is Base {
    address internal newStrategy;

    function setUp() public override {
        super.setUp();

        (, address newStrategy_) = deployAutoCompoundStrategy(
            address(dao), address(escrow), address(swapper), address(vault), address(merklDistributor)
        );
        newStrategy = newStrategy_;
    }

    function testRevert_IfCallerNotAuthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(vault), alice, vault.VAULT_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        vault.setStrategy(newStrategy);
    }

    function test_SetsStrategy() public {
        vm.expectEmit(true, true, true, true);
        emit Vault.StrategySet(newStrategy);

        vault.setStrategy(newStrategy);

        assertEq(address(vault.strategy()), newStrategy);
    }

    function test_SetStrategyToZeroAddress() public {
        vault.setStrategy(address(0));

        assertEq(address(vault.strategy()), address(defaultStrategy));
    }

    function testRevert_IfSetSameStrategy() public {
        vm.expectRevert(Vault.SameStrategyNotAllowed.selector);
        vault.setStrategy(address(acStrategy));
    }

    function test_SetStrategyAfterDeposit() public {
        uint256 amount = _parseToken(100);
        _mintAndApprove(alice, address(vault), amount);

        // Alice deposits
        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();
        address oldStrategy = address(vault.strategy());

        // Verify old strategy owns the master token before
        assertEq(lockNft.ownerOf(masterTokenId), oldStrategy);

        // Expect StrategyRetired event from old strategy
        vm.expectEmit(true, false, false, true);
        emit IStrategy.StrategyRetired(address(vault), masterTokenId);

        // Expect MasterTokenReceived event from new strategy
        vm.expectEmit(true, false, false, false);
        emit IStrategyNFT.MasterTokenReceived(masterTokenId);

        // Change strategy
        vault.setStrategy(newStrategy);

        // Verify vault state
        assertEq(address(vault.strategy()), newStrategy);
        assertEq(vault.totalAssets(), totalAssetsBefore);

        // Verify master token was transferred to new strategy
        assertEq(lockNft.ownerOf(masterTokenId), newStrategy);

        // Verify new strategy has the correct master token ID
        assertEq(IStrategy(newStrategy).totalAssets(), totalAssetsBefore);
    }

    function test_StrategyChangeWhileUserWithdrawing() public {
        // Setup: Alice has deposited
        uint256 depositAmount = _parseToken(100);
        _mintAndApprove(alice, address(vault), depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Bob also deposits
        _mintAndApprove(bob, address(vault), depositAmount);
        vm.prank(bob);
        vault.deposit(depositAmount, bob);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        // Alice initiates withdrawal of half her deposit
        uint256 withdrawAmount = _parseToken(50);

        // Strategy changes right before Alice's withdraw executes
        vault.setStrategy(newStrategy);

        lockNft.setWhitelisted(address(newStrategy), true);
        escrow.setEnableSplit(address(newStrategy), true);

        // Expect Withdrawn event from the new strategy (tokenId will be dynamically created)
        vm.expectEmit(true, false, false, true);
        emit IStrategy.Withdrawn(alice, 4, withdrawAmount); // tokenId 4 based on test setup

        // Alice's withdraw now executes with NEW strategy
        vm.prank(alice, alice);
        uint256 sharesRedeemed = vault.withdraw(withdrawAmount, alice, alice);

        // Verify the withdrawal worked correctly even though strategy changed
        assertEq(vault.balanceOf(alice), aliceSharesBefore - sharesRedeemed, "Alice shares not reduced correctly");
        assertEq(vault.totalAssets(), totalAssetsBefore - withdrawAmount, "Total assets not reduced correctly");

        // Verify the NEW strategy handled the split (not the old one)
        assertEq(
            IStrategy(newStrategy).totalAssets(),
            totalAssetsBefore - withdrawAmount,
            "New strategy should have correct assets"
        );

        // Verify Alice received an NFT from the split
        uint256[] memory aliceTokens = escrow.ownedTokens(alice);
        assertEq(aliceTokens.length, 1, "Alice should have received 1 NFT from withdrawal");
        assertEq(escrow.locked(aliceTokens[0]).amount, withdrawAmount, "NFT should have correct amount");
    }
}
