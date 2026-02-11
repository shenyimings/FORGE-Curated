// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 [Byzantine Finance]
// The implementation of this contract was inspired by Morpho Vault V2, developed by the Morpho Association in 2025.
pragma solidity ^0.8.0;

import "./CompoundV3IntegrationTest.sol";

contract CompoundV3IntegrationInterestTest is CompoundV3IntegrationTest {
    uint16 constant BASIS_POINTS = 10000;

    /// forge-config: default.isolate = true
    function testAccrueInterest(uint256 assets, uint256 elapsed) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 0, 10 * 365 days);

        // setup.
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(compoundAdapter), hex"");
        vault.deposit(assets, address(this));

        uint256 vaultBalanceBefore = comet.balanceOf(address(compoundAdapter));

        skip(elapsed);

        uint256 vaultBalanceAfter = comet.balanceOf(address(compoundAdapter));
        uint256 interestAccrued = vaultBalanceAfter - vaultBalanceBefore;

        assertApproxEqAbs(vault.totalAssets(), assets + interestAccrued, 2 wei, "vault totalAssets");
        assertApproxEqAbs(compoundAdapter.realAssets(), assets + interestAccrued, 2 wei, "Adapter realAssets");
    }

    /// forge-config: default.isolate = true
    function testAccrueInterestAndWithdraw(uint256 assets, uint256 elapsed, uint256 withdrawFactor) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 0, 3 * 365 days);
        withdrawFactor = bound(withdrawFactor, 0, BASIS_POINTS);

        // setup.
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(compoundAdapter), hex"");
        vault.deposit(assets, address(this));

        uint256 vaultBalanceBefore = comet.balanceOf(address(compoundAdapter));

        skip(elapsed);

        uint256 vaultBalanceAfter = comet.balanceOf(address(compoundAdapter));
        uint256 interestAccrued = vaultBalanceAfter - vaultBalanceBefore;

        uint256 sharesToRedeem = vault.totalSupply() * withdrawFactor / BASIS_POINTS;
        vault.redeem(sharesToRedeem, receiver, address(this));

        assertApproxEqAbs(
            vault.totalAssets(),
            (assets * (BASIS_POINTS - withdrawFactor) / BASIS_POINTS)
                + (interestAccrued * (BASIS_POINTS - withdrawFactor) / BASIS_POINTS),
            3 wei,
            "vault totalAssets"
        );
        assertApproxEqAbs(
            usdc.balanceOf(receiver),
            (assets * withdrawFactor / BASIS_POINTS) + (interestAccrued * withdrawFactor / BASIS_POINTS),
            3 wei,
            "vault balance"
        );
    }
}
