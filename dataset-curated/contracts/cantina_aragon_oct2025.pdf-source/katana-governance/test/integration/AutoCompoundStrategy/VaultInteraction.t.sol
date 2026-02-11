// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { AutoCompoundBase } from "./AutoCompoundBase.t.sol";
import { IStrategy } from "src/interfaces/IStrategy.sol";
import { IStrategyNFT } from "src/interfaces/IStrategyNFT.sol";
import { AragonMerklAutoCompoundStrategy as AutoCompoundStrategy } from
    "src/strategies/AragonMerklAutoCompoundStrategy.sol";
import { deployAutoCompoundStrategy } from "src/utils/Deployers.sol";
import { MockERC20 } from "@mocks/MockERC20.sol";

contract AutoCompoundVaultInteractionTest is AutoCompoundBase {
    // ============= OnlyVault Modifier Tests =============

    function testRevert_OnlyVaultCanCall_Withdraw() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        acStrategy.withdraw(alice, 100e18);
    }

    function testRevert_OnlyVaultCanCall_DepositTokenId() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        acStrategy.depositTokenId(1);
    }

    function testRevert_OnlyVaultCanCall_RetireStrategy() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        acStrategy.retireStrategy();
    }

    function testRevert_OnlyVaultCanCall_ReceiveMasterToken() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        acStrategy.receiveMasterToken(123);
    }

    // ============= Master Token Not Set Tests =============

    function testRevert_MasterTokenNotSet_Withdraw() public {
        // Deploy a new strategy without master token set
        (, address newStrategy) = deployAutoCompoundStrategy(
            address(dao), address(escrow), address(swapper), address(vault), address(merklDistributor)
        );

        vm.expectRevert(IStrategyNFT.MasterTokenNotSet.selector);
        vm.prank(address(vault));
        AutoCompoundStrategy(newStrategy).withdraw(alice, 100e18);
    }

    function testRevert_MasterTokenNotSet_DepositTokenId() public {
        // Deploy a new strategy without master token set
        (, address newStrategy) = deployAutoCompoundStrategy(
            address(dao), address(escrow), address(swapper), address(vault), address(merklDistributor)
        );

        vm.expectRevert(IStrategyNFT.MasterTokenNotSet.selector);
        vm.prank(address(vault));
        AutoCompoundStrategy(newStrategy).depositTokenId(1);
    }

    // ============= Deposit Tests =============

    function test_Deposit() public {
        uint256 depositAmount = 50e18;

        // Mint tokens to alice
        MockERC20(address(escrowToken)).mint(alice, depositAmount);

        // Alice approves strategy
        vm.prank(alice);
        escrowToken.approve(address(acStrategy), depositAmount);

        // Get initial total assets
        uint256 totalAssetsBefore = acStrategy.totalAssets();

        // Expect Deposited event (don't check tokenId as it's dynamically created)
        vm.expectEmit(true, false, false, true);
        emit IStrategy.Deposited(alice, 2, depositAmount); // tokenId will be 2 based on test setup

        // Alice deposits
        vm.prank(alice);
        acStrategy.deposit(depositAmount);

        // Check total assets increased
        assertEq(acStrategy.totalAssets(), totalAssetsBefore + depositAmount);
    }

    // ============= Total Assets Tests =============

    function test_TotalAssets_ZeroWhenNoMasterToken() public {
        // Deploy a new strategy without master token set
        (, address newStrategy) = deployAutoCompoundStrategy(
            address(dao), address(escrow), address(swapper), address(vault), address(merklDistributor)
        );

        assertEq(AutoCompoundStrategy(newStrategy).totalAssets(), 0);
    }

    function test_TotalAssets_ReturnsCorrectAmount() public view {
        uint256 expectedAmount = escrow.locked(acStrategy.masterTokenId()).amount;
        assertEq(acStrategy.totalAssets(), expectedAmount);
    }

    // ============= Retire Strategy Tests =============

    function test_RetireStrategy() public {
        // Store initial state
        uint256 strategyMasterTokenId = acStrategy.masterTokenId();

        // Delegate to someone first
        address delegatee = address(0x123);
        acStrategy.delegate(delegatee);
        assertEq(acStrategy.delegatee(), delegatee);

        // Expect StrategyRetired event
        vm.expectEmit(true, false, false, true);
        emit IStrategy.StrategyRetired(address(vault), strategyMasterTokenId);

        // Only vault can retire
        vm.prank(address(vault));
        acStrategy.retireStrategy();

        // Check that delegation was revoked
        assertEq(ivotesAdapter.delegates(address(acStrategy)), address(0));

        // Check that master token was transferred to vault
        assertEq(lockNft.ownerOf(strategyMasterTokenId), address(vault));
    }

    // ============= Receive Master Token Tests =============

    function test_ReceiveMasterToken() public {
        // Deploy a new strategy without master token
        (, address newStrategy) = deployAutoCompoundStrategy(
            address(dao), address(escrow), address(swapper), address(vault), address(merklDistributor)
        );

        // Initially no master token
        assertEq(AutoCompoundStrategy(newStrategy).masterTokenId(), 0);

        // Vault sets master token
        uint256 newMasterTokenId = 999;

        // Expect MasterTokenReceived event
        vm.expectEmit(true, false, false, false);
        emit IStrategyNFT.MasterTokenReceived(newMasterTokenId);

        vm.prank(address(vault));
        AutoCompoundStrategy(newStrategy).receiveMasterToken(newMasterTokenId);

        // Verify master token is set
        assertEq(AutoCompoundStrategy(newStrategy).masterTokenId(), newMasterTokenId);
    }

    function testRevert_ReceiveMasterToken_WhenMasterTokenAlreadySet() public {
        // The strategy already has a master token set from setUp
        uint256 existingMasterTokenId = acStrategy.masterTokenId();
        assertTrue(existingMasterTokenId != 0, "Master token should be set");

        // Try to set a different master token
        uint256 differentTokenId = existingMasterTokenId + 1;

        vm.expectRevert(IStrategyNFT.MasterTokenAlreadySet.selector);
        vm.prank(address(vault));
        acStrategy.receiveMasterToken(differentTokenId);

        // Verify the original master token is still set
        assertEq(acStrategy.masterTokenId(), existingMasterTokenId);
    }

    function test_ReceiveMasterToken_AllowsSameTokenId() public {
        // The strategy already has a master token set from setUp
        uint256 existingMasterTokenId = acStrategy.masterTokenId();
        assertTrue(existingMasterTokenId != 0, "Master token should be set");

        // Setting the same master token ID should be allowed (no-op)
        vm.prank(address(vault));
        acStrategy.receiveMasterToken(existingMasterTokenId);

        // Verify the master token is unchanged
        assertEq(acStrategy.masterTokenId(), existingMasterTokenId);
    }
}
