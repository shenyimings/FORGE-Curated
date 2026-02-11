pragma solidity ^0.8.17;

import { StdInvariant } from "forge-std/StdInvariant.sol";

import { Base } from "../Base.sol";
import { AvKatVaultHandler as Handler } from "./handlers/AvKatVaultHandler.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";

contract VaultInvariant is StdInvariant, Base {
    Handler internal h;

    function setUp() public override {
        super.setUp();

        h = new Handler(vault, swapper);

        targetContract(address(h));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.withdraw.selector;
        selectors[2] = Handler.depositToken.selector;
        selectors[3] = Handler.donate.selector;
        selectors[4] = Handler.redeem.selector;
        selectors[5] = Handler.setStrategy.selector;

        FuzzSelector memory a = FuzzSelector(address(h), selectors);
        targetSelector(a);
    }

    function invariant_strategyOwnsMasterTokenOnly() public view {
        address owner = vault.lockNft().ownerOf(masterTokenId);

        assertEq(owner, address(vault.strategy()), "Strategy must always own master token");

        // Strategy should only hold the master token, no other NFTs
        uint256 strategyNftBalance = vault.lockNft().balanceOf(address(vault.strategy()));
        assertEq(strategyNftBalance, 1, "Strategy should only hold master token NFT");
    }

    function invariant_vaultHoldsNoNFTs() public view {
        // Vault should not hold any NFTs (they are held by strategy)
        uint256 vaultNftBalance = vault.lockNft().balanceOf(address(vault));
        assertEq(vaultNftBalance, 0, "Vault should not hold any NFTs");
    }

    function invariant_strategyDelegation() public view {
        address delegatee = acStrategy.delegatee();

        if (delegatee == address(0)) {
            return;
        }

        // If delegatee is set, master token must be delegated to it
        assertTrue(
            ivotesAdapter.tokenIsDelegated(masterTokenId), "Master token must be delegated when delegatee is set"
        );

        address actualDelegatee = ivotesAdapter.delegates(address(acStrategy));
        assertEq(actualDelegatee, delegatee, "Strategy must delegate to configured delegatee");
    }

    // ==== ASSETS AND SHARES INVARIANTS ====

    function invariant_totalAssetsInEscrow() public view {
        uint256 vaultTotalAssets = vault.totalAssets();
        uint256 escrowLocked = escrow.locked(masterTokenId).amount;

        assertEq(vaultTotalAssets, escrowLocked, "Vault total assets must equal escrow locked amount");
    }

    function invariant_vaultHoldsNoAssets() public view {
        uint256 vaultBalance = MockERC20(vault.asset()).balanceOf(address(vault));
        assertEq(vaultBalance, 0, "Vault should not hold assets (all should be in escrow)");
    }

    function invariant_totalAssetsMatchesNetFlow() public view {
        uint256 totalDeposited = h.totalDeposited();
        uint256 totalWithdrawn = h.totalWithdrawn();
        uint256 totalDonated = h.totalDonated();
        uint256 currentAssets = vault.totalAssets();

        assertEq(
            totalDeposited + totalDonated - totalWithdrawn,
            currentAssets,
            "Deposits plus donations minus withdrawals must equal current assets"
        );
    }

    function invariant_shareValueProtection() public view {
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        // Exchange rate protection: Share value should never
        // decrease below initial ratio
        if (totalSupply > 0) {
            uint256 currentRate = vault.convertToAssets(1e18); // Assets per 1e18 shares
            assertGe(currentRate, 1e18, "Share value should never fall below initial 1:1 ratio");

            // Total assets should be at least equal to total supply (donations only increase this)
            assertGe(totalAssets, totalSupply, "Total assets should >= total supply after donations");
        }

        //  Rounding favors the vault (protects existing shareholders)
        if (totalSupply > 0 && totalAssets > 0) {
            // When depositing: assets -> shares should round down
            uint256 oddAssets = 1e18 + 1; // Odd number to force rounding
            uint256 sharesFromOddAssets = vault.convertToShares(oddAssets);
            uint256 backToAssets = vault.convertToAssets(sharesFromOddAssets);

            // User should get back less or equal assets (vault keeps the rounding difference)
            assertLe(backToAssets, oddAssets, "Rounding should favor the vault on deposit");

            // When withdrawing: shares -> assets should round down
            uint256 oddShares = 1e18 + 1;
            uint256 assetsFromOddShares = vault.convertToAssets(oddShares);
            uint256 backToShares = vault.convertToShares(assetsFromOddShares);

            // User should get back less or equal shares (vault keeps the rounding difference)
            assertLe(backToShares, oddShares, "Rounding should favor the vault on withdrawal");
        }

        if (totalSupply > 0) {
            // The maximum anyone could withdraw is bounded by total assets
            uint256 maxWithdrawable = vault.convertToAssets(totalSupply);
            assertLe(maxWithdrawable, totalAssets, "Max withdrawable should be less than or equal to total assets");

            // No single share can be worth more than total assets
            uint256 singleShareValue = vault.convertToAssets(1);
            assertLe(singleShareValue, totalAssets, "Single share value bounded by total assets");
        }
    }

    function invariant_sumOfSharesEqualsTotalSupply() public view {
        uint256 totalSupply = vault.totalSupply();
        uint256 sumOfActorShares = h.sumOfActorShares();

        // vault initializes with master token in Base contract.
        uint256 initialShares = vault.balanceOf(address(this));

        assertEq(sumOfActorShares + initialShares, totalSupply, "Sum of all shares must equal total supply");
    }

    function invariant_donationsIncreaseShareValue() public view {
        uint256 totalDonated = h.totalDonated();

        if (totalDonated > 0) {
            // If donations occurred, totalAssets should be greater than totalSupply
            // (since initial ratio was 1:1 but donations add assets without shares)
            uint256 totalAssets = vault.totalAssets();
            uint256 totalSupply = vault.totalSupply();

            assertGt(totalAssets, totalSupply, "Donations should make totalAssets > totalSupply");

            uint256 valuePerShare = vault.convertToAssets(1e18);

            assertGe(valuePerShare, 1e18, "Donations must increase share value above 1:1");
        }
    }
}
