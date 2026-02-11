// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import "./helpers/IntegrationTest.sol";

uint256 constant CAP2 = 100e18;
uint256 constant INITIAL_DEPOSIT = 4 * CAP2;

contract ReallocateIdleTest is IntegrationTest {
    MarketAllocation[] internal allocations;

    function setUp() public override {
        super.setUp();

        loanToken.setBalance(SUPPLIER, INITIAL_DEPOSIT);

        vm.prank(SUPPLIER);
        vault.deposit(INITIAL_DEPOSIT, ONBEHALF);

        _setCap(allMarkets[0], CAP2);
        _setCap(allMarkets[1], CAP2);
        _setCap(allMarkets[2], CAP2);

        _sortSupplyQueueIdleLast();
    }

    function testReallocateSupplyIdle(uint256[3] memory suppliedAssets) public {
        suppliedAssets[0] = bound(suppliedAssets[0], 1, CAP2);
        suppliedAssets[1] = bound(suppliedAssets[1], 1, CAP2);
        suppliedAssets[2] = bound(suppliedAssets[2], 1, CAP2);

        allocations.push(MarketAllocation(idleVault, 0));
        allocations.push(MarketAllocation(allMarkets[0], suppliedAssets[0]));
        allocations.push(MarketAllocation(allMarkets[1], suppliedAssets[1]));
        allocations.push(MarketAllocation(allMarkets[2], suppliedAssets[2]));
        allocations.push(MarketAllocation(idleVault, type(uint256).max));

        uint256 idleBefore = _idle();

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);

        assertEq(allMarkets[0].balanceOf(address(vault)), suppliedAssets[0], "balanceOf(0)");
        assertEq(allMarkets[1].balanceOf(address(vault)), suppliedAssets[1], "balanceOf(1)");
        assertEq(allMarkets[2].balanceOf(address(vault)), suppliedAssets[2], "balanceOf(2)");

        uint256 expectedIdle = idleBefore - suppliedAssets[0] - suppliedAssets[1] - suppliedAssets[2];
        assertEq(_idle(), expectedIdle, "idle");
    }
}
