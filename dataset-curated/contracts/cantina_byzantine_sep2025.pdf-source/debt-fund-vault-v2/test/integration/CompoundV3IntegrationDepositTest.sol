// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 [Byzantine Finance]
// The implementation of this contract was inspired by Morpho Vault V2, developed by the Morpho Association in 2025.
pragma solidity ^0.8.0;

import "./CompoundV3IntegrationTest.sol";

contract CompoundV3IntegrationDepositTest is CompoundV3IntegrationTest {
    function testDepositNoLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        uint256 cometUSDCBalanceBefore = usdc.balanceOf(address(comet));
        vault.deposit(assets, address(this));

        assertEq(compoundAdapter.allocation(), 0, "allocation");
        assertEq(comet.balanceOf(address(compoundAdapter)), 0, "balance of comet");
        assertEq(usdc.balanceOf(address(comet)), cometUSDCBalanceBefore, "underlying balance of comet");
        assertEq(usdc.balanceOf(address(compoundAdapter)), 0, "underlying balance of adapter");
        assertEq(usdc.balanceOf(address(vault)), assets, "underlying balance of vault");
    }

    function testDepositLiquidityAdapterSuccess(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(compoundAdapter), hex"");

        uint256 cometUSDCBalanceBefore = usdc.balanceOf(address(comet));
        vault.deposit(assets, address(this));

        assertApproxEqAbs(compoundAdapter.allocation(), assets, 2 wei, "allocation");
        assertEq(usdc.balanceOf(address(comet)), cometUSDCBalanceBefore + assets, "underlying balance of comet");
        assertApproxEqAbs(comet.balanceOf(address(compoundAdapter)), assets, 2 wei, "balance of comet");
        assertEq(usdc.balanceOf(address(compoundAdapter)), 0, "underlying balance of adapter");
        assertEq(usdc.balanceOf(address(vault)), 0, "underlying balance of vault");
    }
}
