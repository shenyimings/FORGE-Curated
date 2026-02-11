// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {Test} from "forge-std/Test.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";

contract BurningStethSharesTest is Test, SetupStvStETHPool {
    uint256 ethToDeposit = 4 ether;
    uint256 stethSharesToMint = 1 * 10 ** 18; // 1 stETH share

    function setUp() public override {
        super.setUp();
        // Deposit ETH and mint stETH shares for testing burn functionality
        pool.depositETH{value: ethToDeposit}(address(this), address(0));
        pool.mintStethShares(stethSharesToMint);

        // Approve pool to spend stETH shares for burning
        steth.approve(address(pool), type(uint256).max);
    }

    // Initial state tests

    function test_InitialState_HasMintedStethShares() public view {
        assertEq(pool.totalMintedStethShares(), stethSharesToMint);
        assertEq(pool.mintedStethSharesOf(address(this)), stethSharesToMint);
    }

    function test_InitialState_HasStethBalance() public view {
        assertGe(steth.sharesOf(address(this)), stethSharesToMint);
    }

    // burn stETH shares tests

    function test_BurnStethShares_DecreasesTotalMintedShares() public {
        uint256 totalBefore = pool.totalMintedStethShares();
        uint256 sharesToBurn = stethSharesToMint / 2;

        pool.burnStethShares(sharesToBurn);

        assertEq(pool.totalMintedStethShares(), totalBefore - sharesToBurn);
    }

    function test_BurnStethShares_DecreasesUserMintedShares() public {
        uint256 userMintedBefore = pool.mintedStethSharesOf(address(this));
        uint256 sharesToBurn = stethSharesToMint / 2;

        pool.burnStethShares(sharesToBurn);

        assertEq(pool.mintedStethSharesOf(address(this)), userMintedBefore - sharesToBurn);
    }

    function test_BurnStethShares_EmitsEvent() public {
        uint256 sharesToBurn = stethSharesToMint / 2;

        vm.expectEmit(true, false, false, true);
        emit StvStETHPool.StethSharesBurned(address(this), sharesToBurn);

        pool.burnStethShares(sharesToBurn);
    }

    function test_BurnStethShares_CallsDashboardBurnShares() public {
        uint256 sharesToBurn = stethSharesToMint / 2;

        vm.expectCall(address(dashboard), abi.encodeWithSelector(dashboard.burnShares.selector, sharesToBurn));

        pool.burnStethShares(sharesToBurn);
    }

    function test_BurnStethShares_TransfersStethFromUser() public {
        uint256 sharesToBurn = stethSharesToMint / 2;
        uint256 userBalanceBefore = steth.sharesOf(address(this));

        pool.burnStethShares(sharesToBurn);

        assertEq(steth.sharesOf(address(this)), userBalanceBefore - sharesToBurn);
    }

    function test_BurnStethShares_DoesNotLeaveStethOnPool() public {
        uint256 sharesToBurn = stethSharesToMint / 2;

        pool.burnStethShares(sharesToBurn);

        assertEq(steth.sharesOf(address(pool)), 0);
    }

    function test_BurnStethShares_IncreasesAvailableCapacity() public {
        uint256 capacityBefore = pool.remainingMintingCapacitySharesOf(address(this), 0);
        uint256 sharesToBurn = stethSharesToMint / 2;

        pool.burnStethShares(sharesToBurn);

        uint256 capacityAfter = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertEq(capacityAfter, capacityBefore + sharesToBurn);
    }

    function test_BurnStethShares_PartialBurn() public {
        uint256 sharesToBurn = stethSharesToMint / 4;

        pool.burnStethShares(sharesToBurn);

        assertEq(pool.mintedStethSharesOf(address(this)), stethSharesToMint - sharesToBurn);
        assertEq(pool.totalMintedStethShares(), stethSharesToMint - sharesToBurn);
    }

    function test_BurnStethShares_FullBurn() public {
        pool.burnStethShares(stethSharesToMint);

        assertEq(pool.mintedStethSharesOf(address(this)), 0);
        assertEq(pool.totalMintedStethShares(), 0);
    }

    function test_BurnStethShares_MultipleBurns() public {
        uint256 firstBurn = stethSharesToMint / 3;
        uint256 secondBurn = stethSharesToMint / 3;

        pool.burnStethShares(firstBurn);
        pool.burnStethShares(secondBurn);

        assertEq(pool.mintedStethSharesOf(address(this)), stethSharesToMint - firstBurn - secondBurn);
        assertEq(pool.totalMintedStethShares(), stethSharesToMint - firstBurn - secondBurn);
    }

    // Error cases

    function test_BurnStethShares_RevertOnZeroAmount() public {
        vm.expectRevert(StvStETHPool.ZeroArgument.selector);
        pool.burnStethShares(0);
    }

    function test_BurnStethShares_RevertOnInsufficientMintedShares() public {
        uint256 excessiveAmount = stethSharesToMint + 1;

        vm.expectRevert(StvStETHPool.InsufficientMintedShares.selector);
        pool.burnStethShares(excessiveAmount);
    }

    function test_BurnStethShares_RevertOnInsufficientStethBalance() public {
        // Transfer away stETH so user doesn't have enough
        assertTrue(steth.transfer(userAlice, steth.balanceOf(address(this))));

        vm.expectRevert(); // Should revert on transferSharesFrom
        pool.burnStethShares(stethSharesToMint);
    }

    function test_BurnStethShares_RevertAfterFullBurn() public {
        // First burn all shares
        pool.burnStethShares(stethSharesToMint);

        // Then try to burn more
        vm.expectRevert(StvStETHPool.InsufficientMintedShares.selector);
        pool.burnStethShares(1);
    }

    // Different users tests

    function test_BurnStethShares_DifferentUsers() public {
        // Setup other users with deposits and mints
        vm.startPrank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));
        pool.mintStethShares(stethSharesToMint);
        steth.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(userBob);
        pool.depositETH{value: ethToDeposit}(userBob, address(0));
        pool.mintStethShares(stethSharesToMint);
        steth.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        uint256 totalBefore = pool.totalMintedStethShares();
        uint256 sharesToBurn = stethSharesToMint / 2;

        // Alice burns
        vm.prank(userAlice);
        pool.burnStethShares(sharesToBurn);

        // Bob burns
        vm.prank(userBob);
        pool.burnStethShares(sharesToBurn);

        assertEq(pool.mintedStethSharesOf(userAlice), stethSharesToMint - sharesToBurn);
        assertEq(pool.mintedStethSharesOf(userBob), stethSharesToMint - sharesToBurn);
        assertEq(pool.totalMintedStethShares(), totalBefore - (sharesToBurn * 2));
    }

    function test_BurnStethShares_DoesNotAffectOtherUsers() public {
        // Setup Alice with minted shares
        vm.startPrank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));
        pool.mintStethShares(stethSharesToMint);
        steth.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        uint256 aliceMintedBefore = pool.mintedStethSharesOf(userAlice);
        uint256 sharesToBurn = stethSharesToMint / 2;

        // This contract burns, should not affect Alice
        pool.burnStethShares(sharesToBurn);

        assertEq(pool.mintedStethSharesOf(userAlice), aliceMintedBefore);
    }

    // Capacity restoration tests

    function test_BurnStethShares_RestoresFullCapacity() public {
        // Use up all capacity
        uint256 additionalMint = pool.remainingMintingCapacitySharesOf(address(this), 0);
        pool.mintStethShares(additionalMint);

        // Burn all shares
        uint256 totalMinted = pool.mintedStethSharesOf(address(this));
        pool.burnStethShares(totalMinted);

        // Capacity should be fully restored
        uint256 capacityAfterBurn = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertEq(capacityAfterBurn, totalMinted);
    }

    function test_BurnStethShares_PartialCapacityRestore() public {
        uint256 additionalMint = pool.remainingMintingCapacitySharesOf(address(this), 0);
        pool.mintStethShares(additionalMint);

        uint256 capacityBefore = pool.remainingMintingCapacitySharesOf(address(this), 0);
        uint256 sharesToBurn = additionalMint / 2;

        pool.burnStethShares(sharesToBurn);

        uint256 capacityAfter = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertEq(capacityAfter, capacityBefore + sharesToBurn);
    }

    // Edge cases

    function test_BurnStethShares_WithMinimalAmount() public {
        uint256 minimalBurn = 1; // 1 wei
        uint256 mintedBefore = pool.mintedStethSharesOf(address(this));

        pool.burnStethShares(minimalBurn);

        assertEq(pool.mintedStethSharesOf(address(this)), mintedBefore - minimalBurn);
    }

    function test_BurnStethShares_AfterRewards() public {
        // Simulate rewards accrual
        dashboard.mock_simulateRewards(int256(1 ether));

        uint256 sharesToBurn = stethSharesToMint / 2;
        uint256 capacityBefore = pool.remainingMintingCapacitySharesOf(address(this), 0);

        pool.burnStethShares(sharesToBurn);

        uint256 capacityAfter = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertGe(capacityAfter, capacityBefore + sharesToBurn); // Should be at least as high due to rewards
    }

    function test_BurnStethShares_ExactBurnOfAllShares() public {
        uint256 allMintedShares = pool.mintedStethSharesOf(address(this));

        pool.burnStethShares(allMintedShares);

        assertEq(pool.mintedStethSharesOf(address(this)), 0);
        assertEq(pool.totalMintedStethShares(), 0);
    }

    // Approvals

    function test_BurnStethShares_RequiresApproval() public {
        // Test that burning requires proper stETH approval
        uint256 sharesToBurn = stethSharesToMint / 2;

        // Reset approval (assuming it was set during setup)
        steth.approve(address(pool), 0);

        // Should fail without approval
        vm.expectRevert();
        pool.burnStethShares(sharesToBurn);

        // Should succeed with approval (need to approve stETH amount, not shares)
        uint256 stethAmount = steth.getPooledEthByShares(sharesToBurn);
        steth.approve(address(pool), stethAmount);
        pool.burnStethShares(sharesToBurn);

        assertEq(pool.mintedStethSharesOf(address(this)), stethSharesToMint - sharesToBurn);
    }
}
