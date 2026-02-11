// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {Test} from "forge-std/Test.sol";
import {StvPool} from "src/StvPool.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract RebalanceExceedingMintedStethSharesTest is Test, SetupStvStETHPool {
    uint256 constant SHARE_RATE_TOLERANCE = 2;
    uint256 ethToDeposit = 10 ether;
    uint256 stethSharesToMint = 1 * 10 ** 18;

    function setUp() public override {
        super.setUp();
        pool.depositETH{value: ethToDeposit}(address(this), address(0));
        pool.mintStethShares(stethSharesToMint);

        // Create exceeding shares by external rebalancing on vault
        dashboard.rebalanceVaultWithShares(stethSharesToMint);
    }

    // Initial state

    function test_RebalanceExceedingMintedStethShares_InitialState_HasExceedingShares() public view {
        assertEq(pool.totalExceedingMintedStethShares(), stethSharesToMint);
    }

    // Error cases

    function test_RebalanceExceedingMintedStethShares_RevertOnZeroAmount() public {
        vm.expectRevert(StvStETHPool.ZeroArgument.selector);
        pool.rebalanceExceedingMintedStethShares(0);
    }

    function test_RebalanceExceedingMintedStethShares_RevertOnInsufficientMintedShares() public {
        vm.expectRevert(StvStETHPool.InsufficientMintedShares.selector);
        pool.rebalanceExceedingMintedStethShares(stethSharesToMint + 1);
    }

    function test_RebalanceExceedingMintedStethShares_RevertOnInsufficientExceedingShares() public {
        // Mint more shares to have more minted than exceeding
        pool.depositETH{value: ethToDeposit}(address(this), address(0));
        pool.mintStethShares(stethSharesToMint);

        uint256 exceeding = pool.totalExceedingMintedStethShares();
        uint256 minted = pool.mintedStethSharesOf(address(this));
        assertGt(minted, exceeding);

        vm.expectRevert(StvStETHPool.InsufficientExceedingShares.selector);
        pool.rebalanceExceedingMintedStethShares(exceeding + 1);
    }

    function test_RebalanceExceedingMintedStethShares_RevertOnStaleReport() public {
        dashboard.VAULT_HUB().mock_setReportFreshness(dashboard.stakingVault(), false);

        vm.expectRevert(StvPool.VaultReportStale.selector);
        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);
    }

    // Basic functionality

    function test_RebalanceExceedingMintedStethShares_DecreasesMintedStethShares() public {
        uint256 mintedBefore = pool.mintedStethSharesOf(address(this));

        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);

        assertEq(pool.mintedStethSharesOf(address(this)), mintedBefore - stethSharesToMint);
    }

    function test_RebalanceExceedingMintedStethShares_DecreasesTotalMintedStethShares() public {
        uint256 totalBefore = pool.totalMintedStethShares();

        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);

        assertEq(pool.totalMintedStethShares(), totalBefore - stethSharesToMint);
    }

    function test_RebalanceExceedingMintedStethShares_DecreasesExceedingShares() public {
        uint256 exceedingBefore = pool.totalExceedingMintedStethShares();

        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);

        assertEq(pool.totalExceedingMintedStethShares(), exceedingBefore - stethSharesToMint);
    }

    function test_RebalanceExceedingMintedStethShares_BurnsStv() public {
        uint256 balanceBefore = pool.balanceOf(address(this));

        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);

        assertLt(pool.balanceOf(address(this)), balanceBefore);
    }

    function test_RebalanceExceedingMintedStethShares_DecreasesTotalSupply() public {
        uint256 supplyBefore = pool.totalSupply();

        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);

        assertLt(pool.totalSupply(), supplyBefore);
    }

    function test_RebalanceExceedingMintedStethShares_ReturnsStvBurned() public {
        uint256 stvBurned = pool.rebalanceExceedingMintedStethShares(stethSharesToMint);

        assertGt(stvBurned, 0);
    }

    // Events

    function test_RebalanceExceedingMintedStethShares_EmitsStethSharesRebalancedEvent() public {
        vm.expectEmit(true, false, false, false);
        emit StvStETHPool.StethSharesRebalanced(address(this), stethSharesToMint, 0);

        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);
    }

    function test_RebalanceExceedingMintedStethShares_EmitsStethSharesBurnedEvent() public {
        vm.expectEmit(true, false, false, true);
        emit StvStETHPool.StethSharesBurned(address(this), stethSharesToMint);

        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);
    }

    // Partial rebalance

    function test_RebalanceExceedingMintedStethShares_PartialRebalance_DecreasesMintedShares() public {
        uint256 sharesToRebalance = stethSharesToMint / 2;
        uint256 mintedBefore = pool.mintedStethSharesOf(address(this));

        pool.rebalanceExceedingMintedStethShares(sharesToRebalance);

        assertEq(pool.mintedStethSharesOf(address(this)), mintedBefore - sharesToRebalance);
    }

    function test_RebalanceExceedingMintedStethShares_PartialRebalance_DecreasesExceedingShares() public {
        uint256 sharesToRebalance = stethSharesToMint / 2;
        uint256 exceedingBefore = pool.totalExceedingMintedStethShares();

        pool.rebalanceExceedingMintedStethShares(sharesToRebalance);

        assertEq(pool.totalExceedingMintedStethShares(), exceedingBefore - sharesToRebalance);
    }

    function test_RebalanceExceedingMintedStethShares_PartialRebalance_AllowsMultipleCalls() public {
        uint256 firstRebalance = stethSharesToMint / 3;
        uint256 secondRebalance = stethSharesToMint / 3;

        pool.rebalanceExceedingMintedStethShares(firstRebalance);
        pool.rebalanceExceedingMintedStethShares(secondRebalance);

        assertEq(pool.mintedStethSharesOf(address(this)), stethSharesToMint - firstRebalance - secondRebalance);
    }

    // Minimal amount

    function test_RebalanceExceedingMintedStethShares_MinimalAmount_Works() public {
        uint256 mintedBefore = pool.mintedStethSharesOf(address(this));

        pool.rebalanceExceedingMintedStethShares(1);

        assertEq(pool.mintedStethSharesOf(address(this)), mintedBefore - 1);
    }

    // Different users

    function test_RebalanceExceedingMintedStethShares_DifferentUser_CanRebalance() public {
        vm.startPrank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));
        pool.mintStethShares(stethSharesToMint / 2);
        vm.stopPrank();

        // Create more exceeding shares
        dashboard.rebalanceVaultWithShares(stethSharesToMint / 2);

        uint256 aliceMinted = pool.mintedStethSharesOf(userAlice);

        vm.prank(userAlice);
        pool.rebalanceExceedingMintedStethShares(aliceMinted);

        assertEq(pool.mintedStethSharesOf(userAlice), 0);
    }

    function test_RebalanceExceedingMintedStethShares_DoesNotAffectOtherUsersMintedShares() public {
        vm.startPrank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));
        pool.mintStethShares(stethSharesToMint / 2);
        vm.stopPrank();

        // Create more exceeding shares
        dashboard.rebalanceVaultWithShares(stethSharesToMint / 2);

        uint256 aliceMintedBefore = pool.mintedStethSharesOf(userAlice);

        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);

        assertEq(pool.mintedStethSharesOf(userAlice), aliceMintedBefore);
    }

    // Does not call dashboard rebalance

    function test_RebalanceExceedingMintedStethShares_DoesNotCallDashboardRebalance() public {
        // Verify that rebalanceVaultWithShares is NOT called on dashboard
        // (since we're only reducing exceeding shares, not vault liability)
        uint256 vaultLiabilityBefore = pool.totalLiabilityShares();

        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);

        // Vault liability should remain unchanged
        assertEq(pool.totalLiabilityShares(), vaultLiabilityBefore);
    }

    // Total assets impact

    function test_RebalanceExceedingMintedStethShares_DecreasesTotalAssets() public {
        uint256 assetsBefore = pool.totalAssets();

        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);

        assertLt(pool.totalAssets(), assetsBefore);
    }

    // Full rebalance

    function test_RebalanceExceedingMintedStethShares_FullRebalance_ZerosMintedShares() public {
        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);

        assertEq(pool.mintedStethSharesOf(address(this)), 0);
    }

    function test_RebalanceExceedingMintedStethShares_FullRebalance_ZerosExceedingShares() public {
        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);

        assertEq(pool.totalExceedingMintedStethShares(), 0);
    }

    // Does not affect other users' assets

    function test_RebalanceExceedingMintedStethShares_DoesNotDecreaseOtherUsersAssets() public {
        vm.startPrank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));
        pool.mintStethShares(stethSharesToMint / 2);
        vm.stopPrank();

        // Create more exceeding shares
        dashboard.rebalanceVaultWithShares(stethSharesToMint / 2);

        uint256 aliceAssetsBefore = pool.assetsOf(userAlice);

        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);

        // Alice's assets should not decrease (may increase slightly due to rounding)
        assertGe(pool.assetsOf(userAlice), aliceAssetsBefore);
    }

    // Does not change totalNominalAssets

    function test_RebalanceExceedingMintedStethShares_DoesNotChangeTotalNominalAssets() public {
        uint256 nominalAssetsBefore = pool.totalNominalAssets();

        pool.rebalanceExceedingMintedStethShares(stethSharesToMint);

        assertEq(pool.totalNominalAssets(), nominalAssetsBefore);
    }

    // Unhealthy account

    function test_RebalanceExceedingMintedStethShares_WorksWhenAccountIsUnhealthy() public {
        uint256 maxShares = pool.remainingMintingCapacitySharesOf(address(this), 0);
        pool.mintStethShares(maxShares);

        // Create exceeding shares by external rebalancing on vault
        // (rebalance partial amount to keep some liability)
        uint256 totalMinted = pool.totalMintedStethShares();
        uint256 partialRebalance = totalMinted / 4;
        dashboard.rebalanceVaultWithShares(partialRebalance);

        uint256 exceedingShares = pool.totalExceedingMintedStethShares();
        assertGt(exceedingShares, 0, "should have exceeding shares");

        // Simulate loss to make account unhealthy
        dashboard.mock_simulateRewards(-5 ether);

        assertFalse(pool.isHealthyOf(address(this)), "account should be unhealthy");

        uint256 mintedBefore = pool.mintedStethSharesOf(address(this));
        uint256 sharesToRebalance = pool.totalExceedingMintedStethShares();

        // Should work - rebalanceExceedingMintedStethShares doesn't check health
        pool.rebalanceExceedingMintedStethShares(sharesToRebalance);

        assertEq(pool.mintedStethSharesOf(address(this)), mintedBefore - sharesToRebalance);
    }

    // Undercollateralized account

    function test_RebalanceExceedingMintedStethShares_WorksWhenAccountIsUndercollateralized() public {
        // Deposit more to have enough STV for rebalancing after losses
        pool.depositETH{value: 20 ether}(address(this), address(0));

        // First, mint max shares to create a leveraged position
        uint256 maxShares = pool.remainingMintingCapacitySharesOf(address(this), 0);
        pool.mintStethShares(maxShares);

        // Create exceeding shares by external rebalancing on vault
        // (rebalance partial amount to keep some liability)
        uint256 totalMinted = pool.totalMintedStethShares();
        uint256 partialRebalance = totalMinted / 4;
        dashboard.rebalanceVaultWithShares(partialRebalance);

        uint256 exceedingShares = pool.totalExceedingMintedStethShares();
        assertGt(exceedingShares, 0, "should have exceeding shares");

        // Simulate large loss to make account undercollateralized
        dashboard.mock_simulateRewards(-15 ether);

        (, , bool isUndercollateralized) = pool.previewForceRebalance(address(this));
        assertTrue(isUndercollateralized, "account should be undercollateralized");

        uint256 mintedBefore = pool.mintedStethSharesOf(address(this));
        uint256 sharesToRebalance = pool.totalExceedingMintedStethShares();

        // Should still work - rebalanceExceedingMintedStethShares doesn't check collateralization
        pool.rebalanceExceedingMintedStethShares(sharesToRebalance);

        assertEq(pool.mintedStethSharesOf(address(this)), mintedBefore - sharesToRebalance);
    }

    function test_RebalanceExceedingMintedStethShares_BadDebt_KeepsShareRate() public {
        // Deposit more to have enough STV for rebalancing after losses
        pool.depositETH{value: 20 ether}(address(this), address(0));

        // First, mint max shares to create a leveraged position
        uint256 maxShares = pool.remainingMintingCapacitySharesOf(address(this), 0);
        pool.mintStethShares(maxShares);

        // Create exceeding shares by external rebalancing on vault
        // (rebalance partial amount to keep some liability)
        uint256 totalMinted = pool.totalMintedStethShares();
        uint256 partialRebalance = totalMinted / 4;
        dashboard.rebalanceVaultWithShares(partialRebalance);

        uint256 exceedingShares = pool.totalExceedingMintedStethShares();
        assertGt(exceedingShares, 0, "should have exceeding shares");

        // Simulate loss to make bad debt on vault
        uint256 liabilityShares = pool.totalLiabilityShares();
        uint256 vaultValue = dashboard.VAULT_HUB().totalValue(dashboard.stakingVault());
        uint256 minValueToCoverLiability = steth.getPooledEthBySharesRoundUp(liabilityShares);
        assertGt(vaultValue, minValueToCoverLiability);

        uint256 loss = vaultValue - minValueToCoverLiability + 1;
        dashboard.mock_simulateRewards(-int256(loss));

        uint256 valueShares = steth.getSharesByPooledEth(dashboard.VAULT_HUB().totalValue(dashboard.stakingVault()));
        assertLt(valueShares, pool.totalLiabilityShares(), "vault should have bad debt");

        uint256 rateBefore = pool.previewRedeem(1e27);

        uint256 sharesToRebalance = exceedingShares / 2;
        uint256 stvRequired = pool.previewWithdraw(steth.getPooledEthBySharesRoundUp(sharesToRebalance));
        assertLe(stvRequired, pool.balanceOf(address(this)));

        pool.rebalanceExceedingMintedStethShares(sharesToRebalance);

        uint256 rateAfter = pool.previewRedeem(1e27);
        assertGe(rateAfter, rateBefore, "share rate should not decrease");
        assertApproxEqAbs(rateAfter, rateBefore, SHARE_RATE_TOLERANCE, "share rate should be equal within tolerance");
    }

    // Undercollateralized account cannot rebalance full debt due to insufficient STV

    function test_RebalanceExceedingMintedStethShares_RevertsWhenInsufficientStvToBurn() public {
        // Mint more shares to increase liability
        uint256 maxShares = pool.remainingMintingCapacitySharesOf(address(this), 0);
        pool.mintStethShares(maxShares);

        // Create more exceeding shares
        dashboard.rebalanceVaultWithShares(maxShares);

        // Simulate large loss to reduce STV value significantly
        // This makes the STV worth less than the stETH liability
        dashboard.mock_simulateRewards(-9 ether);

        // User has minted shares and there are exceeding shares
        uint256 userMinted = pool.mintedStethSharesOf(address(this));
        uint256 userStv = pool.balanceOf(address(this));
        uint256 stvRequired = pool.previewWithdraw(steth.getPooledEthBySharesRoundUp(userMinted));

        // Verify user doesn't have enough STV to cover the rebalance
        assertGt(stvRequired, userStv, "user should not have enough STV");

        // Should revert with ERC20InsufficientBalance
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), userStv, stvRequired)
        );
        pool.rebalanceExceedingMintedStethShares(userMinted);
    }
}
